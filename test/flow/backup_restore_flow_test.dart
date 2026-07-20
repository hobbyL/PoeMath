// test/flow/backup_restore_flow_test.dart
//
// 流程测试：备份 → 清空 → 恢复 → 验证数据完整性。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

import '../helpers/hive_test_helper.dart';

class _MockPoemFavoriteBox extends Mock implements Box<PoemFavorite> {}

void main() {
  late BackupService backupService;

  setUp(() async {
    await setUpHiveForTesting();
    backupService = BackupService();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('导出空数据库应生成合法 JSON', () {
    final json = backupService.exportToJson();
    expect(json, contains('"version"'));
    expect(json, contains('"exportedAt"'));
    expect(json, contains('"poemProgress": []'));
  });

  test('备份并恢复 PoemProgress 数据', () async {
    // 插入测试数据
    final progress = PoemProgress(
      poemId: 'poem_1',
      profileId: 'default',
      status: LearningStatus.learning,
      masteryLevel: 3,
      studyCount: 5,
      stars: 10,
    );
    await HiveBoxes.poemProgress.put('default_poem_1', progress);

    // 导出
    final json = backupService.exportToJson();

    // 清空
    await HiveBoxes.poemProgress.clear();
    expect(HiveBoxes.poemProgress.isEmpty, isTrue);

    // 恢复
    final count = await backupService.restoreFromJson(json);
    expect(count, greaterThan(0));

    // 验证
    final restored = HiveBoxes.poemProgress.get('default_poem_1');
    expect(restored, isNotNull);
    expect(restored!.poemId, equals('poem_1'));
    expect(restored.status, equals(LearningStatus.learning));
    expect(restored.masteryLevel, equals(3));
    expect(restored.studyCount, equals(5));
    expect(restored.stars, equals(10));
  });

  test('备份并恢复 UserStats 数据', () async {
    final stats = UserStats(
      profileId: 'default',
      totalStars: 42,
      currentStreak: 7,
      longestStreak: 14,
      poemsLearned: 10,
      poemsMastered: 5,
      mathTotalProblems: 200,
      mathTotalCorrect: 180,
      level: 3,
    );
    await HiveBoxes.userStats.put('default_stats', stats);

    final json = backupService.exportToJson();

    await HiveBoxes.userStats.clear();
    expect(HiveBoxes.userStats.isEmpty, isTrue);

    await backupService.restoreFromJson(json);

    final restored = HiveBoxes.userStats.get('default_stats');
    expect(restored, isNotNull);
    expect(restored!.totalStars, equals(42));
    expect(restored.currentStreak, equals(7));
    expect(restored.longestStreak, equals(14));
    expect(restored.level, equals(3));
    expect(restored.mathTotalProblems, equals(200));
    expect(restored.mathTotalCorrect, equals(180));
  });

  test('备份并恢复逐次学习活动，旧备份缺失字段时兼容为空', () async {
    final completedAt = DateTime(2026, 7, 20, 12);
    final activity = LearningActivity(
      id: 'poem_quiz:poem_1:1',
      profileId: 'default',
      activityType: LearningActivityType.poemQuiz.name,
      totalItems: 5,
      successfulItems: 5,
      poemId: 'poem_1',
      starsEarned: 3,
      durationSeconds: 45,
      completedAt: completedAt,
    );
    await HiveBoxes.learningActivities.put(
      'default_${activity.id}',
      activity,
    );

    final json = backupService.exportToJson();
    await HiveBoxes.learningActivities.clear();
    expect(await backupService.restoreFromJson(json), 1);

    final restored = HiveBoxes.learningActivities.get('default_${activity.id}');
    expect(restored, isNotNull);
    expect(restored!.type, LearningActivityType.poemQuiz);
    expect(restored.completedAt, completedAt);

    final legacy = jsonDecode(json) as Map<String, dynamic>;
    legacy.remove('learningActivities');
    await backupService.restoreFromJson(jsonEncode(legacy));
    expect(HiveBoxes.learningActivities, isEmpty);
  });

  test('恢复逐次学习活动时拒绝重复 ID 和未知类型', () async {
    final activity = <String, dynamic>{
      'id': 'duplicate',
      'profileId': 'default',
      'activityType': LearningActivityType.mathPractice.name,
      'totalItems': 1,
      'successfulItems': 1,
      'poemId': null,
      'starsEarned': 3,
      'durationSeconds': 1,
      'completedAt': DateTime(2026, 7, 20).toIso8601String(),
    };
    final duplicateBackup =
        jsonDecode(backupService.exportToJson()) as Map<String, dynamic>;
    duplicateBackup['learningActivities'] = [activity, activity];

    expect(
      () => backupService.restoreFromJson(jsonEncode(duplicateBackup)),
      throwsA(isA<FormatException>()),
    );

    final unknownTypeBackup = Map<String, dynamic>.from(duplicateBackup);
    unknownTypeBackup['learningActivities'] = [
      {...activity, 'activityType': 'unknown'},
    ];
    expect(
      () => backupService.restoreFromJson(jsonEncode(unknownTypeBackup)),
      throwsA(isA<FormatException>()),
    );
  });

  test('备份并恢复多种数据类型', () async {
    // 插入多种数据
    await HiveBoxes.poemFavorites.put(
      'default_poem_1',
      PoemFavorite(poemId: 'poem_1', profileId: 'default'),
    );
    await HiveBoxes.checkIns.put(
      'default_2026-07-13',
      CheckIn(
        profileId: 'default',
        date: '2026-07-13',
        poemCount: 2,
        mathTotalCount: 12,
        mathCorrectCount: 10,
        starsEarned: 5,
        durationSeconds: 600,
        isCheckedIn: false,
        activitySources:
            CheckIn.poemActivitySource | CheckIn.mathActivitySource,
      ),
    );
    await HiveBoxes.userStats.put(
      'default_stats',
      UserStats(profileId: 'default', totalStars: 15),
    );

    final json = backupService.exportToJson();

    // 清空所有
    await HiveBoxes.poemFavorites.clear();
    await HiveBoxes.checkIns.clear();
    await HiveBoxes.userStats.clear();

    // 恢复
    final count = await backupService.restoreFromJson(json);
    expect(count, equals(3)); // 1 favorite + 1 checkin + 1 stats

    // 验证
    expect(HiveBoxes.poemFavorites.length, equals(1));
    expect(HiveBoxes.checkIns.length, equals(1));
    expect(HiveBoxes.userStats.length, equals(1));

    final restoredCheckIn = HiveBoxes.checkIns.get('default_2026-07-13');
    expect(restoredCheckIn!.poemCount, equals(2));
    expect(restoredCheckIn.mathTotalCount, equals(12));
    expect(restoredCheckIn.mathCorrectCount, equals(10));
    expect(restoredCheckIn.starsEarned, equals(5));
    expect(restoredCheckIn.durationSeconds, equals(600));
    expect(restoredCheckIn.isCheckedIn, isFalse);
    expect(restoredCheckIn.hasActivitySummary, isTrue);
  });

  test('恢复无效 JSON 应抛出 FormatException', () {
    expect(
      () => backupService.restoreFromJson('not valid json'),
      throwsA(isA<FormatException>()),
    );
  });

  test('恢复过高版本号应抛出 FormatException', () {
    expect(
      () => backupService.restoreFromJson('{"version": 999}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('顶层 JSON 数组应被拒绝且不修改现有数据', () async {
    final existing = PoemProgress(
      poemId: 'existing',
      profileId: 'default',
      status: LearningStatus.learning,
      studyCount: 4,
    );
    await HiveBoxes.poemProgress.put('default_existing', existing);

    await expectLater(
      backupService.restoreFromJson('[]'),
      throwsA(isA<FormatException>()),
    );

    expect(
      HiveBoxes.poemProgress.get('default_existing')!.studyCount,
      equals(4),
    );
  });

  test('越界学习状态应在清空 Box 前被拒绝', () async {
    final existing = PoemProgress(
      poemId: 'existing',
      profileId: 'default',
      status: LearningStatus.learning,
    );
    await HiveBoxes.poemProgress.put('default_existing', existing);
    final invalid = jsonEncode({
      'version': 1,
      'poemProgress': [
        <String, dynamic>{
          'poemId': 'new',
          'profileId': 'default',
          'status': 99,
        },
      ],
    });

    await expectLater(
      backupService.restoreFromJson(invalid),
      throwsA(isA<FormatException>()),
    );

    expect(HiveBoxes.poemProgress.get('default_existing'), isNotNull);
    expect(HiveBoxes.poemProgress.get('default_new'), isNull);
  });

  test('导出并恢复 Settings KV 数据', () async {
    // 写入设置
    await HiveBoxes.settings.put('tts_speed', 0.8);
    await HiveBoxes.settings.put('pinyin_visible', true);

    final json = backupService.exportToJson();

    // 清除设置
    await HiveBoxes.settings.clear();
    expect(HiveBoxes.settings.isEmpty, isTrue);

    await backupService.restoreFromJson(json);

    expect(HiveBoxes.settings.get('tts_speed'), equals(0.8));
    expect(HiveBoxes.settings.get('pinyin_visible'), equals(true));
  });

  test('恢复 settings 会等待写入并移除备份中不存在的旧键', () async {
    await HiveBoxes.settings.put('stale_setting', 'remove-me');
    final json = jsonEncode({
      'version': 1,
      'settings': <String, dynamic>{'tts_speed': 0.8},
    });

    await backupService.restoreFromJson(json);

    expect(HiveBoxes.settings.get('tts_speed'), equals(0.8));
    expect(HiveBoxes.settings.get('stale_setting'), isNull);
  });

  test('中途写入失败时回滚已写入 Box，并保留原始异常', () async {
    final existing = PoemProgress(
      poemId: 'existing',
      profileId: 'default',
      status: LearningStatus.learning,
      studyCount: 7,
    );
    await HiveBoxes.poemProgress.put('default_existing', existing);
    final json = jsonEncode({
      'version': 1,
      'poemProgress': [
        <String, dynamic>{
          'poemId': 'replacement',
          'profileId': 'default',
          'status': 1,
          'studyCount': 1,
        },
      ],
    });

    final originalBox = HiveBoxes.poemFavorites;
    final failingBox = _MockPoemFavoriteBox();
    var clearCalls = 0;
    when(() => failingBox.values).thenReturn(const <PoemFavorite>[]);
    when(() => failingBox.clear()).thenAnswer((_) async {
      clearCalls++;
      if (clearCalls == 1) throw StateError('simulated write failure');
      return 0;
    });
    HiveBoxes.poemFavorites = failingBox;

    try {
      await expectLater(
        backupService.restoreFromJson(json),
        throwsA(isA<StateError>()),
      );
      expect(clearCalls, equals(2));
      expect(
        HiveBoxes.poemProgress.get('default_existing')!.studyCount,
        equals(7),
      );
      expect(HiveBoxes.poemProgress.get('default_replacement'), isNull);
    } finally {
      HiveBoxes.poemFavorites = originalBox;
    }
  });

  test('回滚失败时抛出带 rollbackFailed 标记的异常', () async {
    final existing = PoemProgress(
      poemId: 'existing',
      profileId: 'default',
      status: LearningStatus.learning,
    );
    await HiveBoxes.poemProgress.put('default_existing', existing);
    final json = jsonEncode({
      'version': 1,
      'poemProgress': [
        <String, dynamic>{
          'poemId': 'replacement',
          'profileId': 'default',
          'status': 1,
        },
      ],
    });

    final originalBox = HiveBoxes.poemFavorites;
    final failingBox = _MockPoemFavoriteBox();
    when(() => failingBox.values).thenReturn(const <PoemFavorite>[]);
    when(
      () => failingBox.clear(),
    ).thenAnswer((_) async => throw StateError('rollback failure'));
    HiveBoxes.poemFavorites = failingBox;

    try {
      await expectLater(
        backupService.restoreFromJson(json),
        throwsA(
          isA<BackupRestoreException>().having(
            (error) => error.rollbackFailed,
            'rollbackFailed',
            isTrue,
          ),
        ),
      );
      expect(
        HiveBoxes.poemProgress.get('default_existing')!.status,
        equals(LearningStatus.learning),
      );
    } finally {
      HiveBoxes.poemFavorites = originalBox;
    }
  });

  test('备份并恢复挑战奖励，旧备份缺少奖励字段时默认为 0', () async {
    final record = ChallengeRecord(
      id: 'challenge',
      profileId: 'default',
      mode: 'fixed',
      score: 90,
      totalAnswered: 10,
      correctCount: 9,
      bestCombo: 6,
      grade: 2,
      semester: '下',
      difficulty: 'hard',
      durationSeconds: 60,
      starsEarned: 2,
    );
    await HiveBoxes.challengeRecords.put('default_challenge', record);

    final json = backupService.exportToJson();
    await HiveBoxes.challengeRecords.clear();
    await backupService.restoreFromJson(json);
    expect(
      HiveBoxes.challengeRecords.get('default_challenge')!.starsEarned,
      2,
    );

    final legacy = jsonDecode(json) as Map<String, dynamic>;
    final records = legacy['challengeRecords'] as List<dynamic>;
    (records.single as Map<String, dynamic>).remove('starsEarned');
    await HiveBoxes.challengeRecords.clear();
    await backupService.restoreFromJson(jsonEncode(legacy));

    expect(
      HiveBoxes.challengeRecords.get('default_challenge')!.starsEarned,
      0,
    );
  });
}
