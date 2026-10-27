import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/narration_audio_identity.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';
import 'package:poemath/domain/textbook_recognition_session.dart';
import '../helpers/recognition_fixture.dart';

void main() {
  test('指定生字只创建该字认读题，已练过未到复习日也可主动进入', () {
    final pack = recognitionFixture();
    final lesson = pack.lessons.single;
    final targets = recognitionTargets(pack, lesson);
    final target = targets.firstWhere((t) => t.id == 'star');
    final progress = RecognitionProgress(
      profileId: 'default',
      bookId: 'book',
      editionId: 'edition',
      records: {
        RecognitionProgress.targetKey(lesson.id, target.id): RecognitionRecord(
          fingerprint: target.fingerprint,
          oralCorrect: 2,
          checkedDay: '2026-10-26',
          nextDay: '2026-11-01',
        ),
      },
    );
    final session = buildRecognitionSession(
      progress: progress,
      lessonId: lesson.id,
      targets: targets,
      id: 'selected',
      now: DateTime(2026, 10, 26),
      epoch: 0,
      targetId: target.id,
    )!;
    expect(session.questions.map((q) => q.targetId).toList(), ['star']);
    expect(session.question.kind, RecognitionQuestionKind.read);
    expect(session.recognitionFirst, true);
    expect(session.hinted, false);
    expect(session.fingerprint, recognitionLessonFingerprint(targets));
    expect(progress.records.values.single.oralCorrect, 2);
    expect(
      () => buildRecognitionSession(
        progress: progress,
        lessonId: lesson.id,
        targets: targets,
        id: 'missing',
        now: DateTime(2026, 10, 26),
        epoch: 0,
        targetId: 'unknown',
      ),
      throwsStateError,
    );
  });

  test('我来认先无提示认读，所有认读在选择题之前，不先曝光新字', () {
    final pack = recognitionFixture(),
        lesson = recognitionFixture().lessons.single;
    final session = buildRecognitionSession(
      progress: const RecognitionProgress(
        profileId: 'default',
        bookId: 'book',
        editionId: 'edition',
      ),
      lessonId: lesson.id,
      targets: recognitionTargets(pack, lesson),
      id: 's',
      now: DateTime(2026, 10, 26),
      epoch: 0,
      recognitionFirst: true,
    )!;
    expect(session.recognitionFirst, isTrue);
    expect(
      session.questions.any((q) => q.kind == RecognitionQuestionKind.study),
      isFalse,
    );
    expect(
      session.questions
          .take(5)
          .every((q) => q.kind == RecognitionQuestionKind.read),
      isTrue,
    );
    expect(
      RecognitionSession.fromJson(session.toJson()).recognitionFirst,
      isTrue,
    );
  });

  test('口语证据独立计数，提示和补题不计独立；跨天才推进间隔，旧 v1 兼容', () {
    const record = RecognitionRecord(fingerprint: 'fp');
    final first = recognitionRecordResult(
      record,
      RecognitionEvidence.oralCorrect,
      day: '2026-10-26',
      hinted: false,
    );
    expect(first.oralCorrect, 1);
    expect(first.correct, 0);
    expect(first.stage, 0);
    expect(recognitionRecordLabel(first), '独立认读通过，待复习');
    final hinted = recognitionRecordResult(
      first,
      RecognitionEvidence.oralCorrect,
      day: '2026-10-27',
      hinted: true,
    );
    expect(hinted.oralCorrect, 1);
    expect(hinted.stage, 0);
    final delayed = recognitionRecordResult(
      first,
      RecognitionEvidence.oralCorrect,
      day: '2026-10-27',
      hinted: false,
    );
    expect(delayed.stage, 1);
    expect(delayed.nextDay, '2026-10-30');
    final old = record.toJson()
      ..remove('oralCorrect')
      ..remove('oralAgain');
    expect(RecognitionRecord.fromJson(old).oralCorrect, 0);
    final failed = recognitionRecordResult(
      delayed,
      RecognitionEvidence.oralAgain,
      day: '2026-10-30',
      hinted: false,
    );
    expect(failed.oralAgain, 1);
    expect(failed.stage, 0);
  });
  test('卡片注音缺失时从课内上下文生成，底部展示完整词语或课文句子', () {
    final raw = recognitionFixture().toJson();
    final lessonRaw = (raw['lessons'] as List).single as Map<String, dynamic>;
    final characters = lessonRaw['recognitionCharacters'] as List;
    final starRaw = characters
        .cast<Map<String, dynamic>>()
        .firstWhere((node) => node['id'] == 'star');
    starRaw['pinyin'] = null;
    ((lessonRaw['paragraphs'] as List).single
        as Map<String, dynamic>)['pinyin'] = null;
    final pack = TextbookCoursePack.fromJson(raw);
    final lesson = pack.lessons.single;
    final star = lesson.recognitionCharacters
        .firstWhere((target) => target.id == 'star');
    final rare = lesson.recognitionCharacters
        .firstWhere((target) => target.id == 'recognition-001');

    expect(recognitionCardPinyin(lesson, star), 'xīng');
    expect(
      recognitionCardNote(lesson, star),
      (label: '课内词语', text: '星月'),
    );
    expect(
      recognitionCardNote(lesson, rare),
      (label: '课文词句', text: '星𠀀，月。'),
    );
  });

  test('课文句子较长时保留完整句子，不截取目标字附近片段', () {
    final raw = recognitionFixture().toJson();
    final lessonRaw = (raw['lessons'] as List).single as Map<String, dynamic>;
    final paragraph =
        (lessonRaw['paragraphs'] as List).single as Map<String, dynamic>;
    paragraph['text'] = '这里有一群小蝌蚪，𠀀的大大的脑袋，黑灰色的身子，拖着长长的尾巴。';
    paragraph['pinyin'] = null;
    final range = ((((lessonRaw['recitations'] as List).single
            as Map<String, dynamic>)['ranges'] as List)
        .single as Map<String, dynamic>);
    range['textSha256'] = textbookTextDigest('这里');
    final lesson = TextbookCoursePack.fromJson(raw).lessons.single;
    final target = lesson.recognitionCharacters.first;

    expect(
      recognitionCardNote(lesson, target),
      (
        label: '课文词句',
        text: '这里有一群小蝌蚪，𠀀的大大的脑袋，黑灰色的身子，拖着长长的尾巴。',
      ),
    );
  });

  test('卡片词句不按 PDF 换行或跨页段落截断，并保留句末引号', () {
    final raw = recognitionFixture().toJson();
    final lessonRaw = (raw['lessons'] as List).single as Map<String, dynamic>;
    final paragraph =
        (lessonRaw['paragraphs'] as List).single as Map<String, dynamic>;
    const firstPart = '“池塘里有一群小蝌蚪， 𠀀大大的脑袋，黑\n灰色的身子，游来';
    const secondPart = '游去。”接着，星星笑了！月亮在哪里？';
    lessonRaw['paragraphs'] = [
      {...paragraph, 'text': firstPart, 'pinyin': null},
      {
        ...paragraph,
        'id': 'paragraph-002',
        'text': secondPart,
        'pinyin': null,
      },
    ];
    lessonRaw['words'] = <Object>[];
    lessonRaw['recitations'] = <Object>[];
    (lessonRaw['coverage'] as Map)['words'] = 'notApplicable';
    (lessonRaw['coverage'] as Map)['recitations'] = 'notApplicable';
    final lesson = TextbookCoursePack.fromJson(raw).lessons.single;
    final target = lesson.recognitionCharacters.first;
    final star = lesson.recognitionCharacters
        .firstWhere((character) => character.id == 'star');
    final moon = lesson.recognitionCharacters
        .firstWhere((character) => character.id == 'moon');

    expect(
      recognitionCardNote(lesson, target),
      (label: '课文词句', text: '“池塘里有一群小蝌蚪，𠀀大大的脑袋，黑灰色的身子，游来游去。”'),
    );
    expect(
      recognitionCardNote(lesson, star),
      (label: '课文词句', text: '接着，星星笑了！'),
    );
    expect(
      recognitionCardNote(lesson, moon),
      (label: '课文词句', text: '月亮在哪里？'),
    );
  });

  test('认字使用当前课目字卡，不要求课目审核；缺少原始拼音复用卡片读音', () {
    final pack = recognitionFixture();
    final raw = pack.toJson();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    final moved = (lesson['recognitionCharacters'] as List).removeAt(0);
    (raw['lessons'] as List).add({
      ...lesson,
      'id': 'lesson-002',
      'title': '另一个课目',
      'lessonNumber': 2,
      'review': newTextbookReview(),
      'recognitionCharacters': [moved],
      'paragraphs': <Object>[],
      'words': <Object>[],
      'writingCharacters': <Object>[],
      'recitations': <Object>[],
      'exercises': <Object>[],
      'coverage': {
        for (final c in TextbookCoursePack.categories)
          c: c == 'recognitionCharacters' ? 'complete' : 'notApplicable',
      },
    });
    (((raw['units'] as List).single as Map)['lessonIds'] as List)
        .add('lesson-002');
    final changed = TextbookCoursePack.fromJson(raw);
    final newLesson = changed.lessons.last;
    expect(newLesson.recognitionCharacters.single.isApproved, true);
    expect(recognitionTargets(changed, newLesson).single.ready, true);
    final empty =
        editTextbookCourseNode(pack, 'recognition-001', {'pinyin': null});
    final target = recognitionTargets(empty, empty.lessons.single).first;
    expect(target.ready, true);
    expect(
      target.pinyin,
      recognitionCardPinyin(empty.lessons.single, target.node),
    );
  });
  test('每日每册10字上限按不同目标计数，完成不自动追加', () {
    final pack = recognitionFixture();
    final lesson = pack.lessons.single;
    final targets = recognitionTargets(pack, lesson);
    final p = RecognitionProgress(
      profileId: 'default',
      bookId: pack.edition.pdfSha256,
      editionId: pack.edition.id,
      records: {
        for (final t in targets)
          RecognitionProgress.targetKey(lesson.id, t.id): RecognitionRecord(
            fingerprint: t.fingerprint,
            studies: 1,
            lastDay: '2026-10-24',
            nextDay: '2026-10-25',
          ),
        for (var i = 0; i < 10; i++)
          RecognitionProgress.targetKey('another', 'target$i'):
              const RecognitionRecord(
            fingerprint: 'fp',
            checkedDay: '2026-10-25',
          ),
      },
    );
    expect(
      buildRecognitionSession(
        progress: p,
        lessonId: lesson.id,
        targets: targets,
        id: 'limited',
        now: DateTime(2026, 10, 25),
        epoch: 0,
      ),
      isNull,
    );
  });
  test('声调数字、带调及ü等价，缺调和歧义不作为音频依据', () {
    expect(recognitionPronunciation(' lǜ '), recognitionPronunciation('lv4'));
    expect(recognitionPronunciation('nu:3'), recognitionPronunciation('nǚ'));
    expect(recognitionPronunciation('xing'), isNull);
    expect(recognitionPronunciation('xíng4'), isNull);
    expect(recognitionPronunciation('de5'), 'de5');
    expect(
      recognitionPronunciation('xíng'),
      isNot(recognitionPronunciation('xìng')),
    );
  });
  test('未审核的本课字卡全部可认字，进入练习不自动批准课程', () {
    final pack = recognitionFixture(approved: false);
    expect(
      recognitionTargets(pack, pack.lessons.single).every((t) => t.ready),
      true,
    );
    var raw = pack.toJson();
    for (final node in [
      pack.lessons.single,
      pack.lessons.single.recognitionCharacters.first,
    ]) {
      raw = reviewTextbookCourse(
        input: raw,
        nodeId: node.id,
        reviewer: '家长',
        decision: 'approved',
        checks: node.requiredChecks,
        notes: '核对部分',
        at: DateTime.utc(2026),
      );
    }
    final partial = TextbookCoursePack.fromJson(raw);
    expect(
      recognitionTargets(partial, partial.lessons.single)
          .where((t) => t.ready)
          .map((t) => t.text),
      ['𠀀', '星', '月', '行', '形'],
    );
    expect(partial.isPublishable, false);
  });
  test('Unicode出现位置对应注音；撤回审核即改变指纹而不是依靠revision', () {
    final pack = recognitionFixture();
    final t = recognitionTargets(pack, pack.lessons.single).first;
    expect(
      t.cues.where((c) => c.nodeId == 'paragraph-001').single.positions,
      [1],
    );
    final raw = reviewTextbookCourse(
      input: pack.toJson(),
      nodeId: t.id,
      reviewer: '家长',
      decision: 'rejected',
      checks: [],
      notes: '读音待确认',
      at: DateTime.utc(2026),
    );
    final rejected = TextbookCoursePack.fromJson(raw);
    final updated = recognitionTargets(rejected, rejected.lessons.single).first;
    expect(updated.ready, true);
    expect(updated.fingerprint, isNot(t.fingerprint));
    expect(rejected.contentRevision, pack.contentRevision);
  });
  test('未确认的音频不建听音题；同音选项和cue内其他字均排除', () {
    final pack = recognitionFixture();
    final targets = recognitionTargets(pack, pack.lessons.single);
    final p = RecognitionProgress(
      profileId: 'default',
      bookId: pack.edition.pdfSha256,
      editionId: pack.edition.id,
    );
    RecognitionSession build(RecognitionProgress progress) =>
        buildRecognitionSession(
          progress: progress,
          lessonId: pack.lessons.single.id,
          targets: targets,
          id: 'round',
          now: DateTime(2026, 10, 25),
          epoch: 0,
        )!;
    expect(
      build(p).questions.where((q) => q.kind == RecognitionQuestionKind.listen),
      isEmpty,
    );
    final confirmed = p.copy(
      audio: {
        for (final t in targets)
          for (final c in t.cues)
            c.key: RecognitionAudioApproval(
              fingerprint: t.fingerprint,
              cueKey: c.key,
              identity: NarrationAudioIdentity(
                cacheKey: 'a' * 64,
                backend: NarrationBackend.system,
                audioSha256: 'b' * 64,
              ),
            ),
      },
    );
    final s = build(confirmed);
    expect(
      s.questions.any((q) => q.kind == RecognitionQuestionKind.context),
      true,
    );
    for (final q
        in s.questions.where((q) => q.kind == RecognitionQuestionKind.listen)) {
      final target = targets.firstWhere((t) => t.id == q.targetId);
      final cue = target.cues.firstWhere((c) => c.key == q.cueKey);
      expect(q.options.where((id) => id == q.targetId).length, 1);
      for (final id in q.options.where((id) => id != q.targetId)) {
        final other = targets.firstWhere((t) => t.id == id);
        expect(
          recognitionPronunciation(other.pinyin),
          isNot(recognitionPronunciation(target.pinyin)),
        );
        expect(cue.text.contains(other.text), false);
      }
    }
    expect(RecognitionSession.fromJson(s.toJson()).toJson(), s.toJson());
  });
  test('自评、曝光和提示不算客观通过；延后通过每日期只推进一次', () {
    const initial = RecognitionRecord(fingerprint: 'fp');
    final studied = recognitionRecordResult(
      initial,
      RecognitionEvidence.study,
      day: '2026-10-25',
      hinted: false,
    );
    final self = recognitionRecordResult(
      studied,
      RecognitionEvidence.selfCorrect,
      day: '2026-10-26',
      hinted: false,
    );
    expect(self.stage, 0);
    expect(self.correct, 0);
    expect(self.parentPassed, isNull);
    final correct = recognitionRecordResult(
      self,
      RecognitionEvidence.correct,
      day: '2026-10-26',
      hinted: false,
    );
    expect(correct.stage, 1);
    expect(correct.nextDay, '2026-10-29');
    final again = recognitionRecordResult(
      correct,
      RecognitionEvidence.parentCorrect,
      day: '2026-10-26',
      hinted: false,
    );
    expect(again.stage, 1);
    expect(again.nextDay, correct.nextDay);
    final hinted = recognitionRecordResult(
      again,
      RecognitionEvidence.correct,
      day: '2026-10-29',
      hinted: true,
    );
    expect(hinted.stage, 0);
    expect(hinted.correct, correct.correct);
    expect(hinted.nextDay, '2026-10-30');
    final endOfMonth = recognitionRecordResult(
      initial,
      RecognitionEvidence.study,
      day: '2026-10-31',
      hinted: false,
    );
    expect(endOfMonth.nextDay, '2026-11-01');
  });
  test('错误至少隔两道其他字的题后补一次，题不足留到下一轮', () {
    final pack = recognitionFixture();
    final targets = recognitionTargets(pack, pack.lessons.single);
    final session = RecognitionSession(
      id: 'round',
      lessonId: pack.lessons.single.id,
      fingerprint: 'fp',
      epoch: 0,
      startedAt: DateTime(2026).toIso8601String(),
      questions: [
        for (var i = 0; i < 4; i++)
          RecognitionQuestion(
            id: 'q$i',
            targetId: targets[i].id,
            kind: RecognitionQuestionKind.read,
          ),
      ],
    );
    var p = RecognitionProgress(
      profileId: 'default',
      bookId: pack.edition.pdfSha256,
      editionId: pack.edition.id,
      session: session,
    );
    p = answerRecognition(
      p,
      targets,
      RecognitionEvidence.selfAgain,
      DateTime(2026),
    );
    expect(p.session!.questions[3].repeat, true);
    expect(p.session!.questions.length, 5);
    p = p.copy(session: p.session!.copy(index: 3, clearFeedback: true));
    p = answerRecognition(
      p,
      targets,
      RecognitionEvidence.selfAgain,
      DateTime(2026),
    );
    expect(p.session!.questions.length, 5);
  });
}
