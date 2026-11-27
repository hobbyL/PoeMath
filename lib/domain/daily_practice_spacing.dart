import 'package:poemath/core/utils/calendar_dates.dart';

/// 同一内容计入每日目标后，下一次可计入的自然日间隔。
const dailyPracticeSpacingDays = 5;

typedef DailyPracticeCompletion = ({String contentId, DateTime completedAt});

/// 每日目标与练习列表共用一次回放结果。
class DailyPracticeSpacing {
  const DailyPracticeSpacing({
    required this.countedToday,
    required this.hiddenContentIds,
  });

  final int countedToday;

  /// 计入后的第 2–5 天隐藏；当天仍显示，第 6 天恢复。
  final Set<String> hiddenContentIds;
}

/// 从已知完成历史计算目标日可计入的不同内容数，不改变实际学习记录。
int countSpacedDailyPractices(
  Iterable<DailyPracticeCompletion> history, {
  required DateTime day,
}) => evaluateDailyPracticeSpacing(history, day: day).countedToday;

/// 计算目标计数及仍在五天间隔内、应从练习列表隐藏的内容。
///
/// 必须传入完整已知历史：限制期内的复习不更新计入日，不能仅检查最近
/// 四天是否练过。日期先转本地，再按日历比较，避免 UTC 与夏令时偏差。
DailyPracticeSpacing evaluateDailyPracticeSpacing(
  Iterable<DailyPracticeCompletion> history, {
  required DateTime day,
}) {
  final bounds = localDayBounds(day);
  final completions =
      history.where((entry) => entry.completedAt.isBefore(bounds.end)).toList()
        ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
  final lastCounted = <String, DateTime>{};
  var count = 0;
  for (final entry in completions) {
    final completedDay = localDayBounds(entry.completedAt).start;
    final previous = lastCounted[entry.contentId];
    if (previous != null &&
        calendarDaysBetween(previous, completedDay) <
            dailyPracticeSpacingDays) {
      continue;
    }
    lastCounted[entry.contentId] = completedDay;
    if (completedDay == bounds.start) count++;
  }
  return DailyPracticeSpacing(
    countedToday: count,
    hiddenContentIds: Set.unmodifiable({
      for (final entry in lastCounted.entries)
        if (entry.value.isBefore(bounds.start) &&
            calendarDaysBetween(entry.value, bounds.start) <
                dailyPracticeSpacingDays)
          entry.key,
    }),
  );
}
