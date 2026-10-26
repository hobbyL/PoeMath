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
      (label: '课文词句', text: '$firstPart\n游去。”'),
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

  test('跨课移动的已审子节点不能越过新课目归属审批；空拼音不能训练', () {
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
    expect(recognitionTargets(changed, newLesson).single.ready, false);
    final empty =
        editTextbookCourseNode(pack, 'recognition-001', {'pinyin': null});
    expect(recognitionTargets(empty, empty.lessons.single).first.ready, false);
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
  test('草稿预览可见但不能训练；批准课目归属与部分生字即可使用', () {
    final pack = recognitionFixture(approved: false);
    expect(
      recognitionTargets(pack, pack.lessons.single).every((t) => !t.ready),
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
      ['𠀀'],
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
    expect(updated.ready, false);
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
