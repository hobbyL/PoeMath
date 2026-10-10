// lib/core/widgets/stat_overview_card.dart
//
// 层级：core/widgets
// 职责：统计概览卡 —— 主色→次色渐变底 + 竖分隔线 + 大号数字 + 入场动画。
//       口算练习页与应用题题库页共用，保证两处「统计卡」视觉完全一致。
//
// 说明：渐变卡片 ColoredCard 无法表达（仅支持单色半透明背景），故由本
//       共享组件集中承载这唯一一处 BoxDecoration（页面侧仍禁止手写）。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 单项统计数据：大号数值 + 说明文字。
class StatOverviewItem {
  const StatOverviewItem({required this.value, required this.label});

  /// 大号数值文本，如 '12' / '85%'。
  final String value;

  /// 说明文字，如 '已做题'。
  final String label;
}

/// 统计概览卡：渐变底 + 等距分布的多项统计，项间以竖分隔线分隔。
///
/// 视觉与口算练习页统计卡一致（主色→次色渐变、圆角、淡入上滑动画）。
class StatOverviewCard extends StatelessWidget {
  const StatOverviewCard({super.key, required this.items});

  /// 统计项（通常 2-4 项）。
  final List<StatOverviewItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 30,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
          ),
        );
      }
      children.add(_buildStat(theme, items[i]));
    }

    return Container(
      margin: const EdgeInsets.all(SpacingTokens.md),
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            theme.colorScheme.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: children,
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(
          begin: 0.1,
          end: 0,
          duration: 400.ms,
        );
  }

  Widget _buildStat(ThemeData theme, StatOverviewItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          item.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
