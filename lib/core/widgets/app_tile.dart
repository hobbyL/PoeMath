// lib/core/widgets/app_tile.dart
//
// 层级：core/widgets
// 职责：通用设置行/列表行组件 — 图标 + 标题 + 副标题 + 尾部操作。
//
// 用法：
//   AppTile(
//     icon: Icons.palette_outlined,
//     iconColor: theme.colorScheme.primary,
//     title: '主题设置',
//     subtitle: '诗词',
//     onTap: () => ...,
//   )
//
// 所有设置项、功能列表项等都应使用此组件。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';

/// 通用列表行组件。
///
/// 视觉规则继承 [ColoredCard]（半透明彩色背景 + 圆角），额外提供：
/// - 40×40 圆角图标容器（12% 透明度）
/// - 标题 + 副标题文本列
/// - 尾部组件（默认为 chevron 箭头；可替换为 Switch 等）
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  /// 图标。
  final IconData icon;

  /// 图标主色调，同时决定卡片背景色。
  final Color iconColor;

  /// 标题文本。
  final String title;

  /// 副标题文本。
  final String subtitle;

  /// 点击回调；若 [trailing] 不为空则忽略（由 trailing 自行处理交互）。
  final VoidCallback? onTap;

  /// 尾部组件。为 null 时显示 chevron 箭头。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredCard(
      color: iconColor,
      onTap: trailing == null ? onTap : null,
      constraints: const BoxConstraints(
        minHeight: SpacingTokens.minTapTarget + SpacingTokens.md,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm + 2,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius:
                  BorderRadius.circular(SpacingTokens.radiusSmall),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (trailing == null)
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}
