// lib/features/profile/providers/stats_chart_providers.dart
//
// 层级：features/profile/providers
// 职责：将 checkIns / mathSessions / mathMistakes 按日聚合，
//       为学习报告图表提供数据。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/check_in.dart';

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

/// 最近 N 天的每日统计（默认 30 天）。
final dailyStatsProvider =
    Provider.family<List<DailyStat>, int>((ref, days) {
  final now = DateTime.now();
  final startDate = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: days - 1));

  // 从 checkIns 按日期聚合
  final checkInMap = <String, CheckIn>{};
  for (final ci in HiveBoxes.checkIns.values) {
    checkInMap[ci.date] = ci;
  }

  // 从 mathSessions 按日期聚合题数
  final sessionMap = <String, ({int total, int correct})>{};
  for (final s in HiveBoxes.mathSessions.values) {
    if (s.finishedAt == null) continue;
    final key = _dateKey(s.startedAt);
    final prev = sessionMap[key] ?? (total: 0, correct: 0);
    sessionMap[key] = (
      total: prev.total + s.totalProblems,
      correct: prev.correct + s.correctCount,
    );
  }

  // 从 mathMistakes 按日期统计新增错题
  final mistakeMap = <String, int>{};
  for (final m in HiveBoxes.mathMistakes.values) {
    final key = _dateKey(m.createdAt);
    mistakeMap[key] = (mistakeMap[key] ?? 0) + 1;
  }

  // 生成连续日期列表
  final result = <DailyStat>[];
  for (var i = 0; i < days; i++) {
    final date = startDate.add(Duration(days: i));
    final key = _dateKey(date);

    final ci = checkInMap[key];
    final session = sessionMap[key];
    final mistakes = mistakeMap[key] ?? 0;

    result.add(DailyStat(
      date: date,
      poemCount: ci?.poemCount ?? 0,
      mathTotal: session?.total ?? 0,
      mathCorrect: session?.correct ?? 0,
      starsEarned: ci?.starsEarned ?? 0,
      durationSeconds: ci?.durationSeconds ?? 0,
      mistakeCount: mistakes,
    ),);
  }

  return result;
});

String _dateKey(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
