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
/// - 纯色路径：背景色 = [color] × [backgroundOpacity] 透明度（默认 8%）
/// - 渐变路径：背景 = [gradient]（提供时优先生效，忽略 [color] 着色）
/// - 圆角 = [SpacingTokens.radiusMedium] (16)
/// - 无边框；阴影可选（[boxShadow]，如 [SpacingTokens.softShadow]）
///
/// 可选参数：
/// - [onTap] 添加点击水波纹
/// - [padding] 覆盖默认内边距 ([SpacingTokens.md])
/// - [backgroundOpacity] 覆盖默认背景透明度 (0.08，仅纯色路径生效)
class ColoredCard extends StatelessWidget {
  const ColoredCard({
    super.key,
    this.color,
    this.gradient,
    this.boxShadow,
    required this.child,
    this.onTap,
    this.padding,
    this.backgroundOpacity = 0.08,
    this.width,
    this.constraints,
  }) : assert(
          color != null || gradient != null,
          'color 与 gradient 至少提供一个',
        );

  /// 卡片主色调，背景色将基于此色生成；提供 [gradient] 时可省略。
  final Color? color;

  /// 渐变背景（LinearGradient）；非空时优先于 [color] 渲染。
  final LinearGradient? gradient;

  /// 可选阴影；null = 无阴影（默认，维持原视觉）。
  final List<BoxShadow>? boxShadow;

  /// 卡片内容。
  final Widget child;

  /// 点击回调；为 null 时不显示水波纹。
  final VoidCallback? onTap;

  /// 内边距，默认 [SpacingTokens.md]。
  final EdgeInsetsGeometry? padding;

  /// 背景色透明度，默认 0.08（仅纯色路径生效）。
  final double backgroundOpacity;

  /// 卡片宽度，默认不限制。
  final double? width;

  /// 卡片约束，默认不限制。
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: gradient == null
          ? color!.withValues(alpha: backgroundOpacity)
          : null,
      gradient: gradient,
      boxShadow: boxShadow,
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
