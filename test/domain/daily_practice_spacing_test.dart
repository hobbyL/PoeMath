import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/daily_practice_spacing.dart';

void main() {
  test('当天完成仍显示，次日至第五天隐藏，第六天恢复，期间复习不延长', () {
    final history = [
      (contentId: 'same', completedAt: DateTime(2026, 11, 27)),
      (contentId: 'same', completedAt: DateTime(2026, 11, 27, 20)),
      (contentId: 'same', completedAt: DateTime(2026, 11, 28)),
      (contentId: 'same', completedAt: DateTime(2026, 12, 1)),
      (contentId: 'future', completedAt: DateTime(2026, 12, 3)),
    ];
    final today = evaluateDailyPracticeSpacing(
      history,
      day: DateTime(2026, 11, 27),
    );
    expect(today.hiddenContentIds, isEmpty);
    expect(today.countedToday, 1);
    for (final day in [DateTime(2026, 11, 28), DateTime(2026, 12, 1)]) {
      final spacing = evaluateDailyPracticeSpacing(history, day: day);
      expect(spacing.hiddenContentIds, {'same'});
      expect(spacing.countedToday, 0);
    }
    final available = evaluateDailyPracticeSpacing(
      history,
      day: DateTime(2026, 12, 2),
    );
    expect(available.hiddenContentIds, isEmpty);
    expect(available.countedToday, 0);
    final nextCycle = evaluateDailyPracticeSpacing([
      ...history,
      (contentId: 'same', completedAt: DateTime(2026, 12, 2, 12)),
    ], day: DateTime(2026, 12, 2));
    expect(nextCycle.hiddenContentIds, isEmpty);
    expect(nextCycle.countedToday, 1);
  });

  test('每天复习且当天重复，只有第 1、6、11 天计入目标', () {
    final history = [
      for (var offset = 0; offset <= 10; offset++) ...[
        (contentId: 'same', completedAt: DateTime(2026, 11, 27 + offset, 9)),
        (contentId: 'same', completedAt: DateTime(2026, 11, 27 + offset, 20)),
      ],
    ];
    expect(
      [
        for (var offset = 0; offset <= 10; offset++)
          countSpacedDailyPractices(
            history.reversed,
            day: DateTime(2026, 11, 27 + offset),
          ),
      ],
      [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    );
  });

  test('不同内容独立计入，未来记录和没有练习的日期不计入', () {
    final history = [
      (contentId: 'old', completedAt: DateTime(2026, 11, 26)),
      (contentId: 'old', completedAt: DateTime(2026, 11, 27)),
      (contentId: 'new-a', completedAt: DateTime(2026, 11, 27)),
      (contentId: 'new-a', completedAt: DateTime(2026, 11, 27, 23, 59)),
      (contentId: 'new-b', completedAt: DateTime(2026, 11, 27, 12)),
      (contentId: 'tomorrow', completedAt: DateTime(2026, 11, 28)),
    ];
    expect(countSpacedDailyPractices(history, day: DateTime(2026, 11, 27)), 2);
    expect(countSpacedDailyPractices(history, day: DateTime(2026, 12, 10)), 0);
    expect(countSpacedDailyPractices([], day: DateTime(2026, 11, 27)), 0);
  });

  for (final first in [
    DateTime(2026, 12, 29, 23, 59),
    DateTime(2028, 2, 27, 23, 59),
    DateTime(2026, 3, 6, 23, 59),
    DateTime(2026, 10, 30, 23, 59),
  ]) {
    test('跨年、闰日和夏令时按自然日恢复：$first', () {
      final fourth = DateTime(first.year, first.month, first.day + 4, 23, 59);
      final fifth = DateTime(first.year, first.month, first.day + 5);
      final history = [
        (contentId: 'same', completedAt: first.toUtc()),
        (contentId: 'same', completedAt: fourth.toUtc()),
        (contentId: 'same', completedAt: fifth.toUtc()),
      ];
      expect(countSpacedDailyPractices(history, day: fourth.toUtc()), 0);
      expect(countSpacedDailyPractices(history, day: fifth.toUtc()), 1);
    });
  }
}
