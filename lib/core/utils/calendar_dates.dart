/// 按日历移动日期，保留墙上时钟时间；一天不一定等于 24 小时。
DateTime addCalendarDays(DateTime date, int days) {
  final create = date.isUtc ? DateTime.utc : DateTime.new;
  return create(
    date.year,
    date.month,
    date.day + days,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

/// 只比较年月日，避免夏令时的 23/25 小时影响天数标签。
int calendarDaysBetween(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
