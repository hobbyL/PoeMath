// test/data/repositories/check_in_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late CheckInRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = CheckInRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('CheckInRepository', () {
    test('getToday 无记录返回 null', () {
      expect(repo.getToday(), isNull);
    });

    test('isCheckedInToday 默认返回 false', () {
      expect(repo.isCheckedInToday(), isFalse);
    });

    test('updateToday 创建活动记录但不自动打卡', () async {
      await repo.updateToday(addPoems: 1, addDuration: 30);

      final record = repo.getToday()!;
      expect(record.hasActivitySummary, isTrue);
      expect(record.isCheckedIn, isFalse);
      expect(repo.isCheckedInToday(), isFalse);
      expect(repo.calculateStreak(), 0);
    });

    test('checkInToday 将已有活动记录标记为已打卡并保留数据', () async {
      await repo.updateToday(addPoems: 2, addStars: 3);

      final record = await repo.checkInToday();

      expect(record.isCheckedIn, isTrue);
      expect(record.poemCount, 2);
      expect(record.starsEarned, 3);
      expect(repo.isCheckedInToday(), isTrue);
    });

    test('checkInToday 创建打卡记录', () async {
      final record = await repo.checkInToday();
      expect(record.profileId, 'default');
      expect(repo.isCheckedInToday(), isTrue);
    });

    test('checkInToday 重复调用返回已有记录', () async {
      final first = await repo.checkInToday();
      first.poemCount = 5;
      await first.save();

      final second = await repo.checkInToday();
      expect(second.poemCount, 5); // 应保留已有数据
    });

    test('updateToday 增加学习数据', () async {
      await repo.checkInToday();
      await repo.updateToday(
        addPoems: 3,
        addMathTotal: 12,
        addMathCorrect: 10,
        addStars: 5,
        addDuration: 600,
      );

      final record = repo.getToday()!;
      expect(record.poemCount, 3);
      expect(record.mathTotalCount, 12);
      expect(record.mathCorrectCount, 10);
      expect(record.legacyCompatibleMathTotalCount, 12);
      expect(record.starsEarned, 5);
      expect(record.durationSeconds, 600);
      expect(record.hasActivitySummary, isTrue);
    });

    test('旧版记录用 mathCorrectCount 兼容展示总题数', () {
      final record = CheckIn(
        profileId: 'default',
        date: '2026-07-20',
        mathCorrectCount: 10,
      );

      expect(record.hasActivitySummary, isFalse);
      expect(record.legacyCompatibleMathTotalCount, 10);
    });

    test('updateToday 多次累加', () async {
      await repo.updateToday(addPoems: 2);
      await repo.updateToday(addPoems: 3);

      expect(repo.getToday()!.poemCount, 5);
    });

    test('updateToday 同一活动并发重放只汇总一次', () async {
      await Future.wait([
        repo.updateToday(
          activityId: 'challenge-1',
          addMathTotal: 10,
          addMathCorrect: 9,
          addStars: 2,
          addDuration: 60,
        ),
        repo.updateToday(
          activityId: 'challenge-1',
          addMathTotal: 10,
          addMathCorrect: 9,
          addStars: 2,
          addDuration: 60,
        ),
      ]);

      final record = repo.getToday()!;
      expect(record.mathTotalCount, 10);
      expect(record.mathCorrectCount, 9);
      expect(record.starsEarned, 2);
      expect(record.durationSeconds, 60);
    });

    test('updateToday 不同活动分别汇总', () async {
      for (final id in ['practice-1', 'practice-2']) {
        await repo.updateToday(
          activityId: id,
          addMathTotal: 5,
          addStars: 1,
        );
      }

      expect(repo.getToday()!.mathTotalCount, 10);
      expect(repo.getToday()!.starsEarned, 2);
    });

    test('calculateStreak 无打卡返回 0', () {
      expect(repo.calculateStreak(), 0);
    });

    test('calculateStreak 今日打卡返回 1', () async {
      await repo.checkInToday();
      expect(repo.calculateStreak(), 1);
    });

    test('calculateStreak 连续打卡计算正确', () async {
      final now = DateTime.now();

      // 手动添加昨天和前天的打卡记录
      for (var i = 0; i < 3; i++) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final key = ProfileScope.key(dateStr);
        await HiveBoxes.checkIns.put(
          key,
          CheckIn(profileId: ProfileScope.currentId, date: dateStr),
        );
      }

      expect(repo.calculateStreak(), 3);
    });

    test('calculateStreak 中断后重新开始', () async {
      final now = DateTime.now();

      // 今天打卡
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await HiveBoxes.checkIns.put(
        ProfileScope.key(todayStr),
        CheckIn(profileId: ProfileScope.currentId, date: todayStr),
      );

      // 前天打卡（跳过昨天）
      final dayBefore = now.subtract(const Duration(days: 2));
      final dayBeforeStr =
          '${dayBefore.year}-${dayBefore.month.toString().padLeft(2, '0')}-${dayBefore.day.toString().padLeft(2, '0')}';
      await HiveBoxes.checkIns.put(
        ProfileScope.key(dayBeforeStr),
        CheckIn(profileId: ProfileScope.currentId, date: dayBeforeStr),
      );

      expect(repo.calculateStreak(), 1); // 只有今天
    });

    test('getByMonth 返回指定月份记录', () async {
      final now = DateTime.now();
      await repo.checkInToday();

      final monthly = repo.getByMonth(now.year, now.month);
      expect(monthly.length, 1);
    });

    test('getMonthlyCount 返回正确计数', () async {
      final now = DateTime.now();
      await repo.checkInToday();

      expect(repo.getMonthlyCount(now.year, now.month), 1);
      expect(
        repo.getMonthlyCount(
          now.year,
          now.month + 1 > 12 ? 1 : now.month + 1,
        ),
        0,
      );
    });

    test('getByMonth 不包含其他 profile 的数据', () async {
      final now = DateTime.now();
      await repo.checkInToday();

      ProfileScope.switchTo('kid2');
      final kid2Repo = CheckInRepository();
      expect(kid2Repo.getByMonth(now.year, now.month).length, 0);

      ProfileScope.reset();
    });
  });
}
