// lib/features/profile/cloud_usage_history_page.dart
//
// 层级：features/profile
// 职责：云用量历史页 —— 近 7 天三类请求次数柱状图。
//
// 数据来源：`CloudUsageService.recentDaily`（读 `HiveBoxes.meta` 的
// `cloud_usage:YYYY-MM-DD:<kind>`）。存储层只保留最近 32 天，本页展示
// 7 天。本页**只读**，不改计数与限额（那是家长保护页的职责）。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

/// 展示窗口天数。存储保留 32 天，取 7 天是"一眼能看完趋势"的长度。
const int kUsageHistoryDays = 7;

class CloudUsageHistoryPage extends StatelessWidget {
  const CloudUsageHistoryPage({super.key, this.usage, this.days = kUsageHistoryDays});

  /// 注入点（测试用）；null 时读全局单例。
  final CloudUsageService? usage;
  final int days;

  static const Map<CloudUsageKind, IconData> _icons = {
    CloudUsageKind.llm: Icons.smart_toy_outlined,
    CloudUsageKind.asr: Icons.mic_none_rounded,
    CloudUsageKind.tts: Icons.record_voice_over_outlined,
  };

  static const Map<CloudUsageKind, Color Function(ColorScheme)> _colors = {
    CloudUsageKind.llm: _llmColor,
    CloudUsageKind.asr: _asrColor,
    CloudUsageKind.tts: _ttsColor,
  };

  // 三类固定用主题的三个色位，与柱、图例、图标保持一致。
  static Color _llmColor(ColorScheme s) => s.primary;
  static Color _asrColor(ColorScheme s) => s.secondary;
  static Color _ttsColor(ColorScheme s) => s.tertiary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = usage ?? CloudUsageService.instance;
    // 读取失败兜底为空列表，交给下方空态分支 —— 本页是纯展示，不该
    // 因一次读盘异常白屏。
    List<DailyCloudUsage> daily;
    try {
      daily = service.recentDaily(days);
    } on Object {
      daily = const [];
    }
    final hasAny = daily.any((d) => d.total > 0);

    return Scaffold(
      appBar: AppBar(title: const Text('用量历史')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            if (!hasAny)
              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('暂无用量记录', style: theme.textTheme.titleMedium),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      '最近 $days 天没有发送过云端请求。使用 AI 讲解、语音识别或云朗读后，'
                      '这里会按天记录次数。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final kind in CloudUsageKind.values) ...[
                _usageChart(theme, kind, daily),
                const SizedBox(height: SpacingTokens.md),
              ],
            Text(
              '共保留最近 32 天记录，更早的会自动清理。额度按本设备当天实际发送的请求计数，'
              '不随备份恢复迁移，也不是精确费用账单。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
        ),
      ),
    );
  }

  Widget _usageChart(
    ThemeData theme,
    CloudUsageKind kind,
    List<DailyCloudUsage> daily,
  ) {
    final color = _colors[kind]!(theme.colorScheme);
    final values = daily.map((d) => d.of(kind)).toList();
    final maxY = values.fold<int>(0, (a, b) => a > b ? a : b);
    final todayCount = daily.isEmpty ? 0 : daily.last.of(kind);
    final sum = values.fold<int>(0, (a, b) => a + b);

    return ColoredCard(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icons[kind], size: 20, color: color),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                kind.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '今日 $todayCount · 近 ${daily.length} 天 $sum',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                // 全 0 时给个 5 的刻度，否则 fl_chart 的 maxY=0 会让柱子
                // 与轴重合看不出是空图。
                maxY: (maxY * 1.25).ceilToDouble().clamp(5, double.infinity),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final d = daily[groupIndex].date;
                      return BarTooltipItem(
                        '${d.month}/${d.day}：${rod.toY.toInt()} 次',
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
                        if (i < 0 || i >= daily.length) {
                          return const SizedBox.shrink();
                        }
                        final d = daily[i].date;
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
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(daily.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: daily[i].of(kind).toDouble(),
                        color: color,
                        width: 14,
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
}
