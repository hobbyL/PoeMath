// lib/features/profile/providers/stats_chart_providers.dart
//
// 层级：features/profile/providers
// 职责：将 poemProgress / mathSessions / mathMistakes 按日聚合，
//       为学习报告图表提供数据。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

/// 单日聚合数据。
class DailyStat {
  final DateTime date;
  final int poemCount;
  final int mathTotal;
  final int mathCorrect;
  final int starsEarned;
  final int durationSeconds;
  final int mistakeCount;

  const DailyStat({
    required this.date,
    this.poemCount = 0,
    this.mathTotal = 0,
    this.mathCorrect = 0,
    this.starsEarned = 0,
    this.durationSeconds = 0,
    this.mistakeCount = 0,
  });

  double get accuracy => mathTotal > 0 ? mathCorrect / mathTotal : 0.0;
  int get durationMinutes => (durationSeconds / 60).ceil();
}

/// 最近 N 天的每日统计。
/// 使用 autoDispose 确保每次进入页面都重新读取最新数据。
final dailyStatsProvider =
    Provider.autoDispose.family<List<DailyStat>, int>((ref, days) {
  return buildDailyStats(days: days);
});

/// 从持久化数据构建最近 [days] 天日报；[now] 仅用于确定性测试。
List<DailyStat> buildDailyStats({required int days, DateTime? now}) {
  assert(days > 0);
  final effectiveNow = now ?? DateTime.now();
  final startDate = DateTime(
    effectiveNow.year,
    effectiveNow.month,
    effectiveNow.day,
  )
      .subtract(Duration(days: days - 1));

  // 旧版回退：poemProgress 只能表示每首诗最后一次学习日期。
  final poemMap = <String, int>{};
  for (final p in HiveBoxes.poemProgress.values) {
    if (p.profileId != ProfileScope.currentId || p.lastStudiedAt == null) {
      continue;
    }
    final key = _dateKey(p.lastStudiedAt!);
    poemMap[key] = (poemMap[key] ?? 0) + 1;
  }

  // 旧版回退：普通口算会话按完成日期聚合。
  final sessionMap =
      <String, ({int total, int correct, int stars, int duration})>{};
  for (final s in HiveBoxes.mathSessions.values) {
    if (s.profileId != ProfileScope.currentId || s.finishedAt == null) continue;
    final key = _dateKey(s.finishedAt!);
    final prev = sessionMap[key] ??
        (total: 0, correct: 0, stars: 0, duration: 0);
    sessionMap[key] = (
      total: prev.total + s.totalProblems,
      correct: prev.correct + s.correctCount,
      stars: prev.stars + s.starsEarned,
      duration: prev.duration + s.durationSeconds,
    );
  }

  // 旧版回退：挑战记录此前未写入每日聚合。
  final challengeMap =
      <String, ({int total, int correct, int stars, int duration})>{};
  for (final r in HiveBoxes.challengeRecords.values) {
    if (r.profileId != ProfileScope.currentId) continue;
    final key = _dateKey(r.createdAt);
    final prev = challengeMap[key] ??
        (total: 0, correct: 0, stars: 0, duration: 0);
    challengeMap[key] = (
      total: prev.total + r.totalAnswered,
      correct: prev.correct + r.correctCount,
      stars: prev.stars + r.starsEarned,
      duration: prev.duration + r.durationSeconds,
    );
  }

  final summaryMap = {
    for (final c in HiveBoxes.checkIns.values)
      if (c.profileId == ProfileScope.currentId) c.date: c,
  };

  // 从 mathMistakes 按日统计新增错题
  final mistakeMap = <String, int>{};
  for (final m in HiveBoxes.mathMistakes.values) {
    if (m.profileId != ProfileScope.currentId) continue;
    final key = _dateKey(m.createdAt);
    mistakeMap[key] = (mistakeMap[key] ?? 0) + 1;
  }

  // 生成连续日期列表
  final result = <DailyStat>[];
  for (var i = 0; i < days; i++) {
    final date = startDate.add(Duration(days: i));
    final key = _dateKey(date);

    final summary = summaryMap[key];
    final session = sessionMap[key];
    final challenge = challengeMap[key];
    final mistakes = mistakeMap[key] ?? 0;

    final hasPoemSummary = summary?.hasPoemActivitySummary ?? false;
    final hasMathSummary = summary?.hasMathActivitySummary ?? false;
    final legacyMathTotal =
        (session?.total ?? 0) + (challenge?.total ?? 0);
    final legacyMathCorrect =
        (session?.correct ?? 0) + (challenge?.correct ?? 0);
    final legacyDuration =
        (session?.duration ?? 0) + (challenge?.duration ?? 0);

    result.add(DailyStat(
      date: date,
      poemCount: hasPoemSummary ? summary!.poemCount : poemMap[key] ?? 0,
      mathTotal: hasMathSummary ? summary!.mathTotalCount : legacyMathTotal,
      mathCorrect:
          hasMathSummary ? summary!.mathCorrectCount : legacyMathCorrect,
      starsEarned: (summary?.starsEarned ?? 0) +
          (hasMathSummary
              ? 0
              : (session?.stars ?? 0) + (challenge?.stars ?? 0)),
      durationSeconds: (summary?.durationSeconds ?? 0) +
          (hasMathSummary ? 0 : legacyDuration),
      mistakeCount: mistakes,
    ),);
  }

  return result;
}

String _dateKey(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
