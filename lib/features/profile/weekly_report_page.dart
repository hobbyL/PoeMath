// lib/features/profile/weekly_report_page.dart
//
// 层级：features/profile
// 职责：学习周报页面 — 展示过去 7 天的学习数据汇总、与上周对比、鼓励文案。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

class WeeklyReportPage extends ConsumerWidget {
  const WeeklyReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thisWeek = ref.watch(dailyStatsProvider(7));
    final lastWeek = ref.watch(dailyStatsProvider(14));

    // 上周数据 = 14天数据的前7天
    final lastWeekStats = lastWeek.length >= 14
        ? lastWeek.sublist(0, 7)
        : <DailyStat>[];

    // 聚合本周
    final tw = _aggregate(thisWeek);
    // 聚合上周
    final lw = _aggregate(lastWeekStats);

    // 日期范围
    final endDate = thisWeek.isNotEmpty ? thisWeek.last.date : DateTime.now();
    final startDate =
        thisWeek.isNotEmpty ? thisWeek.first.date : DateTime.now();
    final dateRange =
        '${startDate.month}/${startDate.day} - ${endDate.month}/${endDate.day}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习周报'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.learningStats),
            icon: const Icon(Icons.bar_chart, size: 18),
            label: const Text('详细报告'),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedPageBody(
          children: [
            // 日期范围
            Center(
              child: Text(
                dateRange,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 本周汇总
            _buildSummaryCard(context, tw, lw),
            const SizedBox(height: SpacingTokens.md),

            // 每日练习柱状图
            _buildPracticeChart(context, thisWeek),
            const SizedBox(height: SpacingTokens.md),

            // 鼓励文案
            _buildEncouragement(context, tw, lw),
            const SizedBox(height: SpacingTokens.lg),
          ],
        ),
      ),
    );
  }

  // ============ 数据聚合 ============

  _WeekAggregate _aggregate(List<DailyStat> stats) {
    final totalPoems = stats.fold<int>(0, (sum, s) => sum + s.poemCount);
    final totalMath = stats.fold<int>(0, (sum, s) => sum + s.mathTotal);
    final totalCorrect = stats.fold<int>(0, (sum, s) => sum + s.mathCorrect);
    final totalStars = stats.fold<int>(0, (sum, s) => sum + s.starsEarned);
    final totalMinutes = stats.fold<int>(
      0,
      (sum, s) => sum + s.durationMinutes,
    );
    final activeDays = stats.where(
      (s) => s.poemCount > 0 || s.mathTotal > 0,
    ).length;
    final avgAccuracy =
        totalMath > 0 ? (totalCorrect / totalMath * 100).round() : 0;

    return _WeekAggregate(
      poems: totalPoems,
      math: totalMath,
      accuracy: avgAccuracy,
      stars: totalStars,
      minutes: totalMinutes,
      activeDays: activeDays,
    );
  }

  // ============ 汇总卡片 ============

  Widget _buildSummaryCard(
    BuildContext context,
    _WeekAggregate tw,
    _WeekAggregate lw,
  ) {
    final theme = Theme.of(context);

    return ColoredCard(
      color: theme.colorScheme.primary,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                '本周汇总',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final items = [
                _buildStatItem(
                  theme,
                  Icons.menu_book_rounded,
                  '${tw.poems}',
                  '诗词',
                  theme.colorScheme.primary,
                  _diff(tw.poems, lw.poems),
                ),
                _buildStatItem(
                  theme,
                  Icons.calculate_rounded,
                  '${tw.math}',
                  '口算题',
                  theme.colorScheme.secondary,
                  _diff(tw.math, lw.math),
                ),
                _buildStatItem(
                  theme,
                  Icons.check_circle_outline,
                  '${tw.accuracy}%',
                  '正确率',
                  theme.semantic.success,
                  _diff(tw.accuracy, lw.accuracy),
                ),
                _buildStatItem(
                  theme,
                  Icons.star_rounded,
                  '${tw.stars}',
                  '星星',
                  theme.semantic.caution,
                  _diff(tw.stars, lw.stars),
                ),
                _buildStatItem(
                  theme,
                  Icons.timer_outlined,
                  '${tw.minutes}',
                  '分钟',
                  theme.colorScheme.tertiary,
                  _diff(tw.minutes, lw.minutes),
                ),
                _buildStatItem(
                  theme,
                  Icons.calendar_today,
                  '${tw.activeDays}',
                  '活跃天',
                  theme.colorScheme.primary,
                  _diff(tw.activeDays, lw.activeDays),
                ),
              ];

              // 宽屏（≥480）一行 6 个，窄屏两行各 3 个
              if (constraints.maxWidth >= 480) {
                return Row(
                  children: items
                      .map((item) => Expanded(child: item))
                      .toList(),
                );
              }

              return Column(
                children: [
                  Row(
                    children: items
                        .sublist(0, 3)
                        .map((item) => Expanded(child: item))
                        .toList(),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Row(
                    children: items
                        .sublist(3)
                        .map((item) => Expanded(child: item))
                        .toList(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
    Color color,
    int diff,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (diff != 0) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                diff > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: diff > 0
                    ? theme.semantic.success
                    : theme.colorScheme.error,
              ),
              Text(
                '${diff.abs()}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: diff > 0
                      ? theme.semantic.success
                      : theme.colorScheme.error,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  int _diff(int current, int previous) => current - previous;

  // ============ 每日练习柱状图 ============

  Widget _buildPracticeChart(BuildContext context, List<DailyStat> stats) {
    final theme = Theme.of(context);
    final maxY = stats.fold<double>(0, (prev, s) {
      final m =
          (s.mathTotal > s.poemCount ? s.mathTotal : s.poemCount).toDouble();
      return m > prev ? m : prev;
    });

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '每日练习',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildLegend(theme, '口算', theme.colorScheme.primary),
              const SizedBox(width: SpacingTokens.sm),
              _buildLegend(theme, '诗词', theme.colorScheme.secondary),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: (maxY * 1.2).ceilToDouble().clamp(5, double.infinity),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        rod.toY.toInt().toString(),
                        TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= stats.length) {
                          return const SizedBox.shrink();
                        }
                        final d = stats[i].date;
                        return Padding(
                          padding:
                              const EdgeInsets.only(top: SpacingTokens.xs),
                          child: Text(
                            '${d.month}/${d.day}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(stats.length, (i) {
                  final s = stats[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: s.mathTotal.toDouble(),
                        color: theme.colorScheme.primary,
                        width: 12,
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusSmall,
                        ),
                      ),
                      BarChartRodData(
                        toY: s.poemCount.toDouble(),
                        color: theme.colorScheme.secondary,
                        width: 12,
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusSmall,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(ThemeData theme, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ============ 鼓励文案 ============

  Widget _buildEncouragement(
    BuildContext context,
    _WeekAggregate tw,
    _WeekAggregate lw,
  ) {
    final theme = Theme.of(context);
    final messages = <String>[];

    // 与上周对比
    final poemDiff = tw.poems - lw.poems;
    final mathDiff = tw.math - lw.math;

    if (poemDiff > 0) {
      messages.add('比上周多学了 $poemDiff 首诗词 📚');
    }
    if (mathDiff > 0) {
      messages.add('比上周多做了 $mathDiff 道口算 🧮');
    }

    // 活跃天数
    if (tw.activeDays >= 7) {
      messages.add('连续 7 天坚持学习，太棒了！🌟');
    } else if (tw.activeDays >= 5) {
      messages.add('本周学习了 ${tw.activeDays} 天，非常勤奋！💪');
    } else if (tw.activeDays >= 3) {
      messages.add('本周学习了 ${tw.activeDays} 天，继续加油 🎯');
    }

    // 正确率
    if (tw.accuracy >= 95 && tw.math > 0) {
      messages.add('口算正确率 ${tw.accuracy}%，准确率超高！✨');
    } else if (tw.accuracy >= 80 && tw.math > 0) {
      messages.add('口算正确率 ${tw.accuracy}%，继续保持 👍');
    }

    // 没有数据
    if (tw.poems == 0 && tw.math == 0) {
      messages.add('本周还没有学习记录，快来开始吧！📖');
    }

    // 默认鼓励
    if (messages.isEmpty) {
      messages.add('每天进步一点点，坚持就是胜利！🎉');
    }

    return ColoredCard(
      color: theme.semantic.caution,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_emotions_outlined,
                size: 20,
                color: theme.semantic.caution,
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                '本周亮点',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          ...messages.map(
            (msg) => Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Text(
                msg,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 周聚合数据。
class _WeekAggregate {
  final int poems;
  final int math;
  final int accuracy;
  final int stars;
  final int minutes;
  final int activeDays;

  const _WeekAggregate({
    this.poems = 0,
    this.math = 0,
    this.accuracy = 0,
    this.stars = 0,
    this.minutes = 0,
    this.activeDays = 0,
  });
}
