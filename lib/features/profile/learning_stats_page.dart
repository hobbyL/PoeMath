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

  static const _dayOptions = {7: '最近 7 天', 14: '最近 14 天', 30: '最近 30 天'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(dailyStatsProvider(_days));

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习报告'),
        actions: [
          TextButton.icon(
            onPressed: () => _showRangePicker(context),
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(_dayOptions[_days] ?? '$_days 天'),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedPageBody(
          children: [
            // 做题数 & 学诗数
            _buildChartCard(
              theme: theme,
              title: '每日练习',
              legend: const {'口算': null, '诗词': null},
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

  void _showRangePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SpacingTokens.md),
              Text(
                '选择时间范围',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              RadioGroup<int>(
                groupValue: _days,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _days = v);
                  Navigator.pop(ctx);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _dayOptions.entries.map((e) {
                    return RadioListTile<int>(
                      title: Text(e.value),
                      value: e.key,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
          ),
        );
      },
    );
  }

  // ============ 图表卡片 ============

  Widget _buildChartCard({
    required ThemeData theme,
    required String title,
    required Widget chart,
    Map<String, Color?>? legend,
  }) {
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (legend != null) ...[
                const Spacer(),
                ...legend.entries.indexed.map((entry) {
                  final (i, e) = entry;
                  final color = e.value ??
                      (i == 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondary);
                  return Padding(
                    padding:
                        const EdgeInsets.only(left: SpacingTokens.sm),
                    child: Row(
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
                          e.key,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  // ============ 图表内容宽度 ============

  /// 根据天数计算图表内容宽度，每组柱占固定宽度。
  double _chartWidth(BuildContext context) {
    final screenWidth =
        MediaQuery.sizeOf(context).width - SpacingTokens.md * 2 - SpacingTokens.md * 2;
    final minWidth = _days * 36.0; // 每天至少 36px
    return minWidth > screenWidth ? minWidth : screenWidth;
  }

  /// 包裹可横向滚动的容器。
  Widget _scrollableChart(Widget chart) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = _chartWidth(context);
        if (contentWidth <= constraints.maxWidth) {
          return chart;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // 默认显示最新的（右侧）
          child: SizedBox(width: contentWidth, child: chart),
        );
      },
    );
  }

  // ============ 各图表 ============

  /// 做题数 + 学诗数（分组柱状图）。
  Widget _buildPracticeChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(0, (prev, s) {
      final m = (s.mathTotal > s.poemCount ? s.mathTotal : s.poemCount)
          .toDouble();
      return m > prev ? m : prev;
    });

    return _scrollableChart(
      BarChart(
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

    return _scrollableChart(
      LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${s.y.toInt()}%',
                      TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
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
              color: theme.semantic.success,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3,
                  color: theme.semantic.success,
                  strokeWidth: 1.5,
                  strokeColor: theme.colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: theme.semantic.success.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 星星数（柱状）。
  Widget _buildStarsChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(
      0,
      (prev, s) =>
          s.starsEarned > prev ? s.starsEarned.toDouble() : prev,
    );

    return _scrollableChart(
      BarChart(
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
                  color: theme.semantic.caution,
                  width: _barWidth,
                  borderRadius: _barRadius,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// 学习时长（柱状，分钟）。
  Widget _buildDurationChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(
      0,
      (prev, s) => s.durationMinutes > prev
          ? s.durationMinutes.toDouble()
          : prev,
    );

    return _scrollableChart(
      BarChart(
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
      ),
    );
  }

  /// 新增错题数（柱状）。
  Widget _buildMistakeChart(ThemeData theme, List<DailyStat> stats) {
    final maxY = stats.fold<double>(
      0,
      (prev, s) =>
          s.mistakeCount > prev ? s.mistakeCount.toDouble() : prev,
    );

    return _scrollableChart(
      BarChart(
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
                  color: theme.colorScheme.error,
                  width: _barWidth,
                  borderRadius: _barRadius,
                ),
              ],
            );
          }),
        ),
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
