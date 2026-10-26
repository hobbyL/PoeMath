import 'dart:math';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';

RecognitionRecord? recognitionCurrentRecord(
  RecognitionProgress p,
  String lessonId,
  RecognitionTarget t,
) {
  final r = p.records[RecognitionProgress.targetKey(lessonId, t.id)];
  return r?.fingerprint == t.fingerprint ? r : null;
}

RecognitionAudioApproval? recognitionAudio(
  RecognitionProgress p,
  RecognitionTarget t,
  RecognitionCue c,
) {
  final a = p.audio[c.key];
  return a?.fingerprint == t.fingerprint ? a : null;
}

RecognitionSession? buildRecognitionSession({
  required RecognitionProgress progress,
  required String lessonId,
  required List<RecognitionTarget> targets,
  required String id,
  required DateTime now,
  required int epoch,
}) {
  final ready = targets.where((t) => t.ready).toList();
  final day = recognitionDay(now);
  final reviewedToday =
      progress.records.values.where((r) => r.checkedDay == day).length;
  final due = ready.where((t) {
    final r = recognitionCurrentRecord(progress, lessonId, t);
    return r != null &&
        r.nextDay != null &&
        r.nextDay!.compareTo(day) <= 0 &&
        r.checkedDay != day;
  }).toList()
    ..sort((a, b) {
      final ra = recognitionCurrentRecord(progress, lessonId, a)!;
      final rb = recognitionCurrentRecord(progress, lessonId, b)!;
      final error =
          (rb.incorrect + rb.selfAgain).compareTo(ra.incorrect + ra.selfAgain);
      return error != 0 ? error : ra.nextDay!.compareTo(rb.nextDay!);
    });
  final selected = [
    ...due.take(
      (RecognitionPolicy.dailyReviewLimit - reviewedToday)
          .clamp(0, RecognitionPolicy.dailyReviewLimit),
    ),
    ...ready
        .where((t) => recognitionCurrentRecord(progress, lessonId, t) == null),
  ].take(RecognitionPolicy.roundSize).toList();
  if (selected.isEmpty) return null;
  final questions = <RecognitionQuestion>[];
  void add(
    RecognitionTarget t,
    RecognitionQuestionKind kind, {
    RecognitionCue? cue,
    List<String> options = const [],
    List<int> positions = const [],
  }) {
    questions.add(
      RecognitionQuestion(
        id: '$id/${questions.length}',
        targetId: t.id,
        kind: kind,
        cueKey: cue?.key,
        options: options,
        positions: positions,
      ),
    );
  }

  for (final t in selected) {
    if (recognitionCurrentRecord(progress, lessonId, t) == null) {
      add(t, RecognitionQuestionKind.study);
    }
  }
  for (final t in selected) {
    add(t, RecognitionQuestionKind.read);
    final approved =
        t.cues.where((c) => recognitionAudio(progress, t, c) != null).toList();
    if (approved.isEmpty) continue;
    final cue = approved.first;
    final candidates = ready
        .where(
          (other) =>
              other.id != t.id &&
              other.text != t.text &&
              recognitionPronunciation(other.pinyin) !=
                  recognitionPronunciation(t.pinyin) &&
              !cue.text.contains(other.text),
        )
        .toList();
    int priority(RecognitionTarget target) => recognitionCurrentRecord(progress, lessonId, target) != null ? 0 : selected.contains(target) ? 1 : 2;
    candidates.sort((a, b) => priority(a).compareTo(priority(b)));
    final distractors = candidates.map((t) => t.id).toSet().take(3).toList();
    if (distractors.isNotEmpty) {
      final options = [t.id, ...distractors];
      final shift = questions.length % options.length;
      add(
        t,
        RecognitionQuestionKind.listen,
        cue: cue,
        options: [...options.skip(shift), ...options.take(shift)],
      );
    }
    // 词句题使用单字音频作明确 cue；所有同字同音位置均可作答。
    final single = approved.where((c) => c.nodeId == t.id).firstOrNull;
    final context = t.cues
        .where(
          (c) =>
              c.nodeId != t.id &&
              c.text.runes.where(recognitionIsHan).length >= 2,
        )
        .firstOrNull;
    if (single != null && context != null) {
      add(
        t,
        RecognitionQuestionKind.context,
        cue: single,
        options: [context.key],
        positions: context.positions,
      );
    }
  }
  final study =
      questions.where((q) => q.kind == RecognitionQuestionKind.study).toList();
  final practice = questions
      .where((q) => q.kind != RecognitionQuestionKind.study)
      .toList()
    ..shuffle(Random(now.microsecondsSinceEpoch));
  return RecognitionSession(
    id: id,
    lessonId: lessonId,
    fingerprint: recognitionLessonFingerprint(targets),
    epoch: epoch,
    startedAt: now.toIso8601String(),
    questions: [...study, ...practice],
  );
}

RecognitionProgress answerRecognition(
  RecognitionProgress p,
  List<RecognitionTarget> targets,
  RecognitionEvidence evidence,
  DateTime at,
) {
  final session = p.session!;
  if (session.finished || session.feedback != null) throw StateError('这道题已经提交');
  final q = session.question;
  final allowed = switch (q.kind) {
    RecognitionQuestionKind.study => [RecognitionEvidence.study],
    RecognitionQuestionKind.read => [
        RecognitionEvidence.selfCorrect,
        RecognitionEvidence.selfAgain,
      ],
    _ => [RecognitionEvidence.correct, RecognitionEvidence.incorrect],
  };
  if (!allowed.contains(evidence)) throw StateError('认字答案类型不匹配');
  final target = targets.firstWhere((t) => t.id == q.targetId);
  final key = RecognitionProgress.targetKey(session.lessonId, target.id);
  final r = recognitionCurrentRecord(p, session.lessonId, target) ??
      RecognitionRecord(fingerprint: target.fingerprint);
  final questions = [...session.questions];
  final repeated = [...session.repeated];
  if ((evidence == RecognitionEvidence.incorrect ||
          evidence == RecognitionEvidence.selfAgain) &&
      !repeated.contains(target.id)) {
    // 必须至少隔两道其他字的题；找不到位置则留到下一轮。
    var other = 0;
    for (var i = session.index + 1; i < questions.length; i++) {
      if (questions[i].targetId != target.id) other++;
      if (other >= RecognitionPolicy.interveningQuestions) {
        questions.insert(
          i + 1,
          RecognitionQuestion(
            id: '${session.id}/repeat/${target.id}',
            targetId: q.targetId,
            kind: q.kind,
            cueKey: q.cueKey,
            options: q.options,
            positions: q.positions,
            repeat: true,
          ),
        );
        repeated.add(target.id);
        break;
      }
    }
  }
  return p.copy(
    records: {
      ...p.records,
      key: recognitionRecordResult(
        r,
        evidence,
        day: recognitionDay(at),
        hinted: session.hinted,
      ),
    },
    session: session.copy(
      questions: questions,
      repeated: repeated,
      feedback: evidence,
    ),
  );
}
