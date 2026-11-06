import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_feedback_fixture.dart';

class _LegacyAdapter extends TypeAdapter<PictureStoryPracticeRecord> {
  @override
  int get typeId => 21;
  @override
  PictureStoryPracticeRecord read(BinaryReader reader) =>
      PictureStoryPracticeRecordAdapter().read(reader);
  @override
  void write(BinaryWriter writer, PictureStoryPracticeRecord obj) {
    final fields = [
      obj.id,
      obj.profileId,
      obj.promptId,
      obj.promptVersion,
      obj.startedAt,
      obj.completedAt,
      obj.status,
      obj.segmentsJson,
      obj.answerText,
      obj.feedbackJson,
      obj.totalDurationSeconds,
      obj.usedHints,
    ];
    writer.writeByte(fields.length);
    for (final (i, value) in fields.indexed) {
      writer.writeByte(i);
      writer.write(value);
    }
  }
}

class _FailAfterPut extends Fake implements Box<PictureStoryPracticeRecord> {
  _FailAfterPut(this.delegate);
  final Box<PictureStoryPracticeRecord> delegate;
  bool fail = true;
  @override
  PictureStoryPracticeRecord? get(
    dynamic key, {
    PictureStoryPracticeRecord? defaultValue,
  }) => delegate.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, PictureStoryPracticeRecord value) async {
    await delegate.put(key, value);
    if (fail) {
      fail = false;
      throw StateError('模拟落盘后报错');
    }
  }
}

void main() {
  late PictureStoryRepository repo;
  late PictureStoryPracticeRecord original;
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    repo = PictureStoryRepository();
    original = PictureStoryPracticeRecord(
      id: 'review',
      profileId: 'default',
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026),
      completedAt: DateTime(2026),
      status: 'completed',
      segmentsJson: '[]',
      feedbackJson: '{"source":"vision","text":"旧版点评"}',
    );
    original.setSegments([
      const PictureStorySegment(
        id: 'audio',
        position: 0,
        audioPath: '/original.wav',
        durationSeconds: 5,
        transcript: '最初的表达',
      ),
    ]);
    await repo.save(original);
  });
  tearDown(() async {
    ProfileScope.reset();
    Hive.registerAdapter(PictureStoryPracticeRecordAdapter(), override: true);
    await tearDownHiveForTesting();
  });
  String feedback(String answer) => PictureStoryEvaluation.parse(
    jsonEncode(pictureStoryFeedbackFixture(answer: answer)),
    answer: answer,
    questionCount: 2,
  ).encode(answer: answer, prompts: ['问题一', '问题二']);

  test('连续修订持久化配对版本，清空只影响草稿，所有录音元数据不变', () async {
    var saved = await repo.saveFeedbackDraft(original, '');
    expect(saved.revisionDraft, '');
    await expectLater(
      repo.appendFeedback(saved, feedback('别的答案'), check: () {}),
      throwsFormatException,
    );
    for (final answer in ['第二版表达', '第三版表达']) {
      saved = await repo.saveFeedbackDraft(saved, answer);
      saved = await repo.appendFeedback(saved, feedback(answer), check: () {});
    }
    expect(saved.revisions.map((r) => r.answer), ['最初的表达', '第二版表达', '第三版表达']);
    expect(saved.revisions.first.feedbackJson, original.feedbackJson);
    expect(saved.answerText, '第三版表达');
    expect(saved.revisionDraft, isNull);
    expect(saved.segmentsJson, original.segmentsJson);
    expect(saved.totalDurationSeconds, 5);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reloaded = PictureStoryRepository().find('review')!;
    expect(reloaded.revisionsJson, saved.revisionsJson);
    expect(reloaded.feedbackRevision, saved.feedbackRevision);
    expect(reloaded.feedbackJson, feedback('第三版表达'));
    expect(reloaded.segments.single.audioPath, '/original.wav');
  });

  test('旧版本写入和不对应的反馈均拒绝，不覆盖新草稿', () async {
    final first = await repo.saveFeedbackDraft(original, '第一次修改');
    final second = await repo.saveFeedbackDraft(first, '第二次修改');
    await expectLater(
      repo.appendFeedback(first, feedback('第一次修改'), check: () {}),
      throwsFormatException,
    );
    await expectLater(
      repo.appendFeedback(second, feedback('另一个回答'), check: () {}),
      throwsFormatException,
    );
    expect(repo.find('review')!.revisionDraft, '第二次修改');
    expect(repo.find('review')!.answerText, '最初的表达');
    expect(repo.find('review')!.revisions, isEmpty);
  });

  test('写入途中离页回滚旧快照，档案切换不能写入其他孩子', () async {
    final saved = await repo.saveFeedbackDraft(original, '修改草稿');
    var checks = 0;
    await expectLater(
      repo.appendFeedback(
        saved,
        feedback('修改草稿'),
        check: () {
          if (++checks == 2) throw StateError('离页');
        },
      ),
      throwsStateError,
    );
    expect(repo.find('review')!.revisionDraft, '修改草稿');
    expect(repo.find('review')!.feedbackRevision, saved.feedbackRevision);
    final blocked = PictureStoryRepository.exclusive(() async {
      ProfileScope.switchTo('another');
      ProfileScope.reset();
    });
    final pending = repo.saveFeedbackDraft(saved, '不能提交的旧页面');
    await blocked;
    await expectLater(pending, throwsFormatException);
    expect(repo.find('review')!.revisionDraft, '修改草稿');
  });

  test('旧 Hive 记录缺少新增字段仍可读取并进行第一次修订', () async {
    Hive.registerAdapter(_LegacyAdapter(), override: true);
    await HiveBoxes.pictureStoryPractice.put(
      ProfileScope.key('picture_story:review'),
      original.copy(),
    );
    await HiveBoxes.close();
    Hive.registerAdapter(PictureStoryPracticeRecordAdapter(), override: true);
    await HiveBoxes.init();
    final loaded = PictureStoryRepository().find('review')!;
    expect(loaded.revisions, isEmpty);
    expect(loaded.revisionDraft, isNull);
    expect(loaded.feedbackRevision, 0);
    final saved = await PictureStoryRepository().saveFeedbackDraft(
      loaded,
      '第一次修订',
    );
    expect(saved.revisionDraft, '第一次修订');
    expect(saved.answerText, '最初的表达');
  });

  test('点评写入报错后恢复原快照，修改草稿仍可重试', () async {
    final draft = await repo.saveFeedbackDraft(original, '修改后的表达');
    final faulty = PictureStoryRepository(
      records: _FailAfterPut(HiveBoxes.pictureStoryPractice),
    );
    await expectLater(
      faulty.appendFeedback(draft, feedback('修改后的表达'), check: () {}),
      throwsStateError,
    );
    final saved = repo.find('review')!;
    expect(saved.answerText, original.answerText);
    expect(saved.feedbackJson, original.feedbackJson);
    expect(saved.revisionDraft, '修改后的表达');
    expect(saved.revisions, isEmpty);
    expect(saved.feedbackRevision, draft.feedbackRevision);
  });
}
