import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_feedback_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PictureStoryRepository repo;
  late PictureStoryPracticeRecord original;

  PictureStorySegment segment(String id, String text) => PictureStorySegment(
    id: id,
    position: 0,
    audioPath: '/private/$id.wav',
    durationSeconds: 7,
    transcript: text,
  );

  String feedback(String answer) => PictureStoryEvaluation.parse(
    jsonEncode(pictureStoryFeedbackFixture(answer: answer)),
    answer: answer,
    questionCount: 2,
  ).encode(answer: answer, prompts: ['问题一', '问题二']);

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    repo = PictureStoryRepository();
    original = PictureStoryPracticeRecord(
      id: 'practice',
      profileId: 'default',
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026, 11, 17),
      completedAt: DateTime(2026, 11, 17, 0, 1),
      status: 'completed',
      segmentsJson: '[]',
      feedbackJson: '{"source":"unavailable","text":"第一遍点评"}',
    )..setSegments([segment('first', '第一遍口述')]);
    await repo.save(original);
    final firstDraft = await repo.saveFeedbackDraft(original, '第一遍修改后的表达');
    original = await repo.appendFeedback(
      firstDraft,
      feedback('第一遍修改后的表达'),
      check: () {},
    );
    original = await repo.saveFeedbackDraft(original, '第一遍未评草稿');
  });

  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  PictureStoryRetellingDraft draft() => PictureStoryRetellingDraft(
    id: 'second',
    startedAt: DateTime(2026, 11, 17, 0, 2),
    segments: [segment('second-audio', '第二遍完整口述')],
    usedHints: true,
    guided: false,
  );

  test('重讲草稿与原表达隔离，提交归档后重开 Hive 保留各遍与首次完成时间', () async {
    final savedDraft = await repo.saveRetellingDraft(
      original,
      draft(),
      check: () {},
    );
    expect(savedDraft.answerText, '第一遍修改后的表达');
    expect(repo.records().length, 1);
    expect(savedDraft.retellingDraft!.answerText, '第二遍完整口述');
    final completed = await repo.completeRetelling(savedDraft, check: () {});
    expect(completed.takes.map((t) => t.answerText), ['第一遍修改后的表达', '第二遍完整口述']);
    expect(completed.takes.first.revisionsJson, original.revisionsJson);
    expect(completed.takes.first.revisionDraft, '第一遍未评草稿');
    expect(completed.revisionDraft, isNull);
    expect(completed.revisionsJson, '[]');
    expect(completed.completedAt, original.completedAt);
    expect(completed.retellingDraftJson, isNull);
    expect(repo.records().length, 1);
    final expected = completed.takes.map((t) => t.toJson()).toList();
    await HiveBoxes.close();
    await HiveBoxes.init();
    final loaded = PictureStoryRepository().find('practice')!;
    expect(loaded.takes.map((t) => t.toJson()).toList(), expected);
    expect(loaded.allSegments.map((s) => s.audioPath), [
      '/private/first.wav',
      '/private/second-audio.wav',
    ]);
  });

  test('取消草稿保留旧答案；晚到的草稿、点评及后台写入不能覆盖新口述', () async {
    final saved = await repo.saveRetellingDraft(
      original,
      draft(),
      check: () {},
    );
    final discarded = await repo.discardRetellingDraft(saved, check: () {});
    expect(discarded.retellingDraft, isNull);
    expect(discarded.currentTake.toJson(), original.currentTake.toJson());
    await expectLater(
      repo.saveRetellingDraft(saved, draft(), check: () {}),
      throwsFormatException,
    );
    final newDraft = await repo.saveRetellingDraft(
      discarded,
      draft(),
      check: () {},
    );
    var checks = 0;
    await expectLater(
      repo.completeRetelling(
        newDraft,
        check: () {
          if (++checks == 2) throw StateError('离页');
        },
      ),
      throwsStateError,
    );
    expect(repo.find(original.id)!.answerText, '第一遍修改后的表达');
    expect(
      repo.find(original.id)!.retellingDraftJson,
      newDraft.retellingDraftJson,
    );
    final completed = await repo.completeRetelling(newDraft, check: () {});
    await expectLater(
      repo.saveTakeFeedback(original, '{"text":"迟到点评"}', check: () {}),
      throwsFormatException,
    );
    await expectLater(
      repo.saveFeedbackDraft(original, '迟到修改'),
      throwsFormatException,
    );
    final current = repo.find(original.id)!;
    expect(current.answerText, completed.answerText);
    expect(current.takes.first.feedbackJson, original.feedbackJson);
  });

  test('真实备份跨目录恢复各遍文字和点评，移除全部音频及未完成重讲', () async {
    var saved = await repo.saveRetellingDraft(original, draft(), check: () {});
    saved = await repo.completeRetelling(saved, check: () {});
    saved = await repo.saveTakeFeedback(
      saved,
      '{"text":"第二遍点评"}',
      check: () {},
    );
    saved = await repo.saveFeedbackDraft(saved, '第二遍修改后的表达');
    saved = await repo.appendFeedback(
      saved,
      feedback('第二遍修改后的表达'),
      check: () {},
    );
    expect(saved.revisions.first.createdAt, saved.currentTake.completedAt);
    saved = await repo.saveRetellingDraft(
      saved,
      PictureStoryRetellingDraft(
        id: 'third',
        startedAt: DateTime(2026, 11, 17, 0, 3),
        segments: [segment('third-audio', '没有完成的第三遍')],
      ),
      check: () {},
    );
    final expected = saved.takes.map((t) => t.toJson(portable: true)).toList();
    final backup = BackupService();
    final exported = await backup.exportToJson();
    backup.inspectJson(exported);
    expect(exported, isNot(contains('/private/')));
    expect(exported, isNot(contains('没有完成的第三遍')));
    await tearDownHiveForTesting();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    await BackupService().restoreFromJson(exported);
    final restored = PictureStoryRepository().find('practice')!;
    expect(
      restored.takes.map((t) => t.toJson(portable: true)).toList(),
      expected,
    );
    expect(restored.allSegments.map((s) => s.audioPath), ['', '']);
    expect(restored.retellingDraft, isNull);
    expect(PictureStoryRepository().records().length, 1);
  });

  test('同机恢复只复用匹配遍次的音频，旧快照的当前口述可从历史中找回', () async {
    final audioDir = await Directory.systemTemp.createTemp('picture-takes-');
    addTearDown(() => audioDir.delete(recursive: true));
    final audioFiles = [
      for (final name in ['first', 'second', 'third'])
        await File('${audioDir.path}/$name.wav').writeAsBytes([1, 2, 3]),
    ];
    final first = original.copy()
      ..segmentsJson = jsonEncode([
        original.segments.single
            .copyWith(audioPath: audioFiles[0].path)
            .toJson(),
      ]);
    await repo.save(first);
    final secondDraft = draft().copyWith(
      segments: [
        draft().segments.single.copyWith(audioPath: audioFiles[1].path),
      ],
    );
    var saved = await repo.saveRetellingDraft(first, secondDraft, check: () {});
    saved = await repo.completeRetelling(saved, check: () {});
    final exported = await BackupService().exportToJson();
    // 即使下一遍恰好有相同的片段标识/文字/时长，也不能串用该遍录音。
    saved = await repo.saveRetellingDraft(
      saved,
      PictureStoryRetellingDraft(
        id: 'third',
        startedAt: DateTime(2026, 11, 17, 0, 3),
        segments: [
          secondDraft.segments.single.copyWith(audioPath: audioFiles[2].path),
        ],
      ),
      check: () {},
    );
    await repo.completeRetelling(saved, check: () {});
    await unlockParentForTesting();
    await BackupService().restoreFromJson(exported);
    var restored = repo.find(first.id)!;
    expect(restored.takes.map((t) => t.segments.single.audioPath), [
      audioFiles[0].path,
      audioFiles[1].path,
    ]);

    final changed = jsonDecode(exported) as Map<String, dynamic>;
    final item = (changed['pictureStoryPractice'] as List).single as Map;
    (item['retellingState'] as Map)['currentId'] = 'unmatched-take';
    await BackupService().restoreFromJson(jsonEncode(changed));
    restored = repo.find(first.id)!;
    expect(restored.currentTake.segments.single.audioPath, isEmpty);
    expect(restored.takes.first.segments.single.audioPath, audioFiles[0].path);
  });

  test('口述历史坏结构或注入音频路径在恢复写入前拒绝', () async {
    var saved = await repo.saveRetellingDraft(original, draft(), check: () {});
    saved = await repo.completeRetelling(saved, check: () {});
    final exported = await BackupService().exportToJson();
    final before = saved.copy();
    await unlockParentForTesting();
    final changes = <void Function(Map<String, dynamic>)>[
      (state) => state['version'] = 2,
      (state) => state['currentId'] =
          ((state['archived'] as List).single as Map<String, dynamic>)['id'],
      (state) =>
          (((state['archived'] as List).single
                          as Map<String, dynamic>)['segments']
                      as List)
                  .single['audioPath'] =
              '/injected/recording.wav',
    ];
    for (final change in changes) {
      final data = jsonDecode(exported) as Map<String, dynamic>;
      final item =
          (data['pictureStoryPractice'] as List).single as Map<String, dynamic>;
      change(item['retellingState'] as Map<String, dynamic>);
      await expectLater(
        BackupService().restoreFromJson(jsonEncode(data)),
        throwsFormatException,
      );
      final unchanged = repo.find(before.id)!;
      expect(unchanged.retellingStateJson, before.retellingStateJson);
      expect(unchanged.segmentsJson, before.segmentsJson);
      expect(unchanged.feedbackRevision, before.feedbackRevision);
    }
  });
}
