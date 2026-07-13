// lib/core/widgets/colored_card.dart
//
// 层级：core/widgets
// 职责：基于主色调的半透明卡片容器 — 全局统一的卡片视觉基底。
//
// 用法：
//   ColoredCard(
//     color: theme.colorScheme.primary,
//     child: Text('内容'),
//   )
//
// 所有页面的信息卡片、快捷入口、设置项等都应使用此组件，
// 而非各自手写 BoxDecoration。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 全局统一的半透明彩色卡片。
///
/// 视觉规则：
/// - 背景色 = [color] × 8% 透明度
/// - 圆角 = [SpacingTokens.radiusMedium] (16)
/// - 无边框、无阴影
///
/// 可选参数：
/// - [onTap] 添加点击水波纹
/// - [padding] 覆盖默认内边距 ([SpacingTokens.md])
/// - [backgroundOpacity] 覆盖默认背景透明度 (0.08)
class ColoredCard extends StatelessWidget {
  const ColoredCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.padding,
    this.backgroundOpacity = 0.08,
    this.width,
    this.constraints,
  });

  /// 卡片主色调，背景色将基于此色生成。
  final Color color;

  /// 卡片内容。
  final Widget child;

  /// 点击回调；为 null 时不显示水波纹。
  final VoidCallback? onTap;

  /// 内边距，默认 [SpacingTokens.md]。
  final EdgeInsetsGeometry? padding;

  /// 背景色透明度，默认 0.08。
  final double backgroundOpacity;

  /// 卡片宽度，默认不限制。
  final double? width;

  /// 卡片约束，默认不限制。
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color.withValues(alpha: backgroundOpacity),
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
    );

    final container = Container(
      width: width,
      constraints: constraints,
      padding: padding ?? const EdgeInsets.all(SpacingTokens.md),
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return container;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: container,
    );
  }
}
