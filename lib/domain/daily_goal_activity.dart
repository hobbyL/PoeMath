/// 可纳入每日目标的活动类型。
enum DailyGoalActivity {
  poem('诗词'),
  math('口算'),
  textbookRecognition('认一认'),
  textbookWriting('写一写'),
  pictureStoryExpression('看图表达');

  const DailyGoalActivity(this.label);

  final String label;

  static const defaults = {poem, math};

  static Set<DailyGoalActivity> decode(String value) {
    final names = value.split(',');
    final activities = <DailyGoalActivity>{};
    for (final name in names) {
      final activity = DailyGoalActivity.values
          .where((candidate) => candidate.name == name)
          .firstOrNull;
      if (activity == null || !activities.add(activity)) {
        throw const FormatException('每日目标类型无效');
      }
    }
    if (activities.isEmpty) throw const FormatException('每日目标类型不能为空');
    return Set.unmodifiable(activities);
  }

  static String encode(Iterable<DailyGoalActivity> activities) {
    final selected = activities.toSet();
    if (selected.isEmpty) throw ArgumentError('每日目标类型不能为空');
    return [
      for (final activity in values)
        if (selected.contains(activity)) activity.name,
    ].join(',');
  }
}
