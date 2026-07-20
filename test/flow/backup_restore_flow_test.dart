// test/flow/backup_restore_flow_test.dart
//
// 流程测试：备份 → 清空 → 恢复 → 验证数据完整性。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/user_stats.dart';

import '../helpers/hive_test_helper.dart';

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
