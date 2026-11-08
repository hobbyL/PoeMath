import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/utils/calendar_dates.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

import '../../helpers/hive_test_helper.dart';

String _day(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('日期工具跨月保留时刻、UTC 属性，天数不受夏令时影响', () {
    expect(
      addCalendarDays(DateTime.utc(2024, 2, 28, 23, 30), 2),
      DateTime.utc(2024, 3, 1, 23, 30),
    );
    expect(calendarDaysBetween(DateTime(2026, 3, 8), DateTime(2026, 3, 9)), 1);
    expect(calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 8)), -1);
  });

  // 另以 TZ=America/New_York 运行，覆盖 23/25 小时的日期。
  for (final now in [
    DateTime(2026, 3, 9, 0, 30),
    DateTime(2026, 11, 1, 23, 30),
  ]) {
    test('日统计与用量连续且不丢失日期：${_day(now)}', () {
      final expected = [
        for (var i = 2; i >= 0; i--)
          _day(DateTime(now.year, now.month, now.day - i)),
      ];
      final usage = CloudUsageService(clock: () => now);
      expect(usage.recentDaily(3).map((entry) => _day(entry.date)), expected);
      expect(
        buildDailyStats(days: 3, now: now).map((entry) => _day(entry.date)),
        expected,
      );
    });

    test('连续打卡按日历天计数：${_day(now)}', () async {
      for (var i = 0; i < 3; i++) {
        final date = _day(DateTime(now.year, now.month, now.day - i));
        await HiveBoxes.checkIns.put(
          ProfileScope.key(date),
          CheckIn(profileId: ProfileScope.currentId, date: date),
        );
      }
      expect(CheckInRepository(clock: () => now).calculateStreak(), 3);
    });
  }

  test('明天零点的复习不提前进入今天清单', () async {
    final now = DateTime(2026, 3, 8, 12);
    final repo = ReviewRepository(clock: () => now);
    for (final entry in [
      ('today', DateTime(2026, 3, 8, 23, 59)),
      ('tomorrow', DateTime(2026, 3, 9)),
    ]) {
      await repo.save(
        ReviewSchedule(
          poemId: entry.$1,
          profileId: ProfileScope.currentId,
          nextReviewDate: entry.$2,
        ),
      );
    }
    expect(repo.getDueToday().map((schedule) => schedule.poemId), ['today']);
  });

  test('间隔一天的复习在夏令时前后仍安排在次日', () async {
    final now = DateTime(2026, 3, 7, 23, 30);
    final repo = ReviewRepository(clock: () => now);
    final schedule = await repo.createSchedule('poem');
    expect(_day(schedule.nextReviewDate), '2026-03-08');
    await repo.completeReview('poem', score: 0.5);
    expect(_day(repo.get('poem')!.nextReviewDate), '2026-03-08');
  });
}
