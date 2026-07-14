// lib/features/profile/learning_stats_page.dart
//
// 层级：features/profile
// 职责：学习报告页 — 以图表展示每日做题、正确率、星星、耗时等趋势。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

class LearningStatsPage extends ConsumerStatefulWidget {
  const LearningStatsPage({super.key});

  @override
  ConsumerState<LearningStatsPage> createState() => _LearningStatsPageState();
}

class _LearningStatsPageState extends ConsumerState<LearningStatsPage> {
  int _days = 7;

  static const _dayOptions = [7, 14, 30];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(dailyStatsProvider(_days));

    return Scaffold(
      appBar: AppBar(title: const Text('学习报告')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            // 时间范围选择
            _buildRangeSelector(theme),
            const SizedBox(height: SpacingTokens.md),

            // 做题数 & 学诗数
            _buildChartCard(
              theme: theme,
              title: '每日练习',
              chart: _buildPracticeChart(theme, stats),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 正确率
            _buildChartCard(
              theme: theme,
              title: '口算正确率',
              chart: _buildAccuracyChart(theme, stats),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 星星
            _buildChartCard(
              theme: theme,
              title: '每日星星',
              chart: _buildStarsChart(theme, stats),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 耗时
            _buildChartCard(
              theme: theme,
              title: '学习时长（分钟）',
              chart: _buildDurationChart(theme, stats),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 错题
            _buildChartCard(
              theme: theme,
              title: '新增错题',
              chart: _buildMistakeChart(theme, stats),
            ),
            const SizedBox(height: SpacingTokens.lg),
          ],
        ),
      ),
    );
  }

  // ============ 时间范围选择 ============

  Widget _buildRangeSelector(ThemeData theme) {
    return Row(
      children: _dayOptions.map((d) {
        final isSelected = d == _days;
        return Padding(
          padding: const EdgeInsets.only(right: SpacingTokens.sm),
          child: ChoiceChip(
            label: Text('$d 天'),
            selected: isSelected,
            onSelected: (_) => setState(() => _days = d),
          ),
        );
      }).toList(),
    );
  }

  // ============ 图表卡片 ============

  Widget _buildChartCard({
    required ThemeData theme,
    required String title,
    required Widget chart,
  }) {
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  // ============ 各图表 ============

  /// 做题数（柱状）+ 学诗数（柱状），分组柱状图。
  Widget _buildPracticeChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(0, (prev, s) {
      final m = (s.mathTotal > s.poemCount ? s.mathTotal : s.poemCount)
          .toDouble();
      return m > prev ? m : prev;
    });

    return BarChart(
      BarChartData(
        maxY: (maxY * 1.2).ceilToDouble().clamp(5, double.infinity),
        barTouchData: _barTouchData(theme),
        titlesData: _titlesData(theme, stats),
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
                width: _barWidth,
                borderRadius: _barRadius,
              ),
              BarChartRodData(
                toY: s.poemCount.toDouble(),
                color: theme.colorScheme.secondary,
                width: _barWidth,
                borderRadius: _barRadius,
              ),
            ],
          );
        }),
      ),
    );
  }

  /// 正确率（折线图）。
  Widget _buildAccuracyChart(ThemeData theme, List<DailyStat> stats) {
    final spots = <FlSpot>[];
    for (var i = 0; i < stats.length; i++) {
      final s = stats[i];
      if (s.mathTotal > 0) {
        spots.add(FlSpot(i.toDouble(), (s.accuracy * 100).roundToDouble()));
      }
    }

    if (spots.isEmpty) {
      return Center(
        child: Text(
          '暂无数据',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toInt()}%',
                      TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),)
                .toList(),
          ),
        ),
        titlesData: _titlesData(theme, stats),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: ColorTokens.success,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: ColorTokens.success,
                strokeWidth: 1.5,
                strokeColor: theme.colorScheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: ColorTokens.success.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  /// 星星数（柱状）。
  Widget _buildStarsChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(
        0, (prev, s) => s.starsEarned > prev ? s.starsEarned.toDouble() : prev,);

    return BarChart(
      BarChartData(
        maxY: (maxY * 1.2).ceilToDouble().clamp(3, double.infinity),
        barTouchData: _barTouchData(theme),
        titlesData: _titlesData(theme, stats),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(stats.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: stats[i].starsEarned.toDouble(),
                color: ColorTokens.poemGold,
                width: _barWidth,
                borderRadius: _barRadius,
              ),
            ],
          );
        }),
      ),
    );
  }

  /// 学习时长（柱状，分钟）。
  Widget _buildDurationChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(
        0,
        (prev, s) => s.durationMinutes > prev
            ? s.durationMinutes.toDouble()
            : prev,);

    return BarChart(
      BarChartData(
        maxY: (maxY * 1.2).ceilToDouble().clamp(5, double.infinity),
        barTouchData: _barTouchData(theme),
        titlesData: _titlesData(theme, stats),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(stats.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: stats[i].durationMinutes.toDouble(),
                color: theme.colorScheme.tertiary,
                width: _barWidth,
                borderRadius: _barRadius,
              ),
            ],
          );
        }),
      ),
    );
  }

  /// 新增错题数（柱状）。
  Widget _buildMistakeChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(
        0,
        (prev, s) =>
            s.mistakeCount > prev ? s.mistakeCount.toDouble() : prev,);

    return BarChart(
      BarChartData(
        maxY: (maxY * 1.2).ceilToDouble().clamp(3, double.infinity),
        barTouchData: _barTouchData(theme),
        titlesData: _titlesData(theme, stats),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(stats.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: stats[i].mistakeCount.toDouble(),
                color: ColorTokens.error,
                width: _barWidth,
                borderRadius: _barRadius,
              ),
            ],
          );
        }),
      ),
    );
  }

  // ============ 共享配置 ============

  double get _barWidth => _days <= 7 ? 12 : (_days <= 14 ? 8 : 5);

  BorderRadius get _barRadius =>
      BorderRadius.circular(SpacingTokens.radiusSmall);

  BarTouchData _barTouchData(ThemeData theme) {
    return BarTouchData(
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
    );
  }

  FlTitlesData _titlesData(ThemeData theme, List<DailyStat> stats) {
    // X 轴间隔：7天全显示，14天隔1个，30天隔3个
    final interval = _days <= 7 ? 1 : (_days <= 14 ? 2 : 4);

    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: interval.toDouble(),
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= stats.length) return const SizedBox.shrink();
            final d = stats[i].date;
            return Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.xs),
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
    );
  }
}
