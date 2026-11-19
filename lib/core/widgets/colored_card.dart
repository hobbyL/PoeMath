// lib/core/widgets/colored_card.dart
//
// 层级：core/widgets
// 职责：统一主题卡片、语义着色与点击反馈。
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

/// 全局统一的主题卡片。
///
/// 视觉规则：
/// - 普通卡片：在主题底色上叠加 [color]，外观跟随 [AppAppearance.cardStyle]。
/// - [backgroundOpacity] 为 0 / 1 时保留透明 / 实色表面，不附加纸页装饰。
/// - 渐变路径：背景 = [gradient]（提供时优先生效，忽略 [color] 着色）
/// - 默认圆角由 [AppAppearance.cardRadius] 提供。
/// - [border] / [boxShadow] 可覆盖主题默认装饰。
///
/// 可选参数：
/// - [onTap] 添加点击水波纹
/// - [padding] 覆盖默认内边距 ([SpacingTokens.md])
/// - [backgroundOpacity] 覆盖默认纸面着色强度 (0.02，仅纯色路径生效)
class ColoredCard extends StatelessWidget {
  const ColoredCard({
    super.key,
    this.color,
    this.gradient,
    this.boxShadow,
    this.border,
    required this.child,
    this.onTap,
    this.padding,
    this.backgroundOpacity = 0.02,
    this.paperSurface = true,
    this.width,
    this.constraints,
    this.borderRadius,
  }) : assert(color != null || gradient != null, 'color 与 gradient 至少提供一个');

  /// 卡片主色调，背景色将基于此色生成；提供 [gradient] 时可省略。
  final Color? color;

  /// 渐变背景（LinearGradient）；非空时优先于 [color] 渲染。
  final LinearGradient? gradient;

  /// 可选阴影；默认跟随主题，空列表可取消。
  final List<BoxShadow>? boxShadow;

  final BoxBorder? border;

  /// 卡片内容。
  final Widget child;

  /// 点击回调；为 null 时不显示水波纹。
  final VoidCallback? onTap;

  /// 内边距，默认 [SpacingTokens.md]。
  final EdgeInsetsGeometry? padding;

  /// 纸面着色强度，默认 0.02；0 / 1 分别表示透明 / 实色背景。
  final double backgroundOpacity;

  /// 普通卡片使用不透明纸面；叠在内容上方的半透明遮罩应设为 false。
  final bool paperSurface;

  /// 卡片宽度，默认不限制。
  final double? width;

  /// 卡片约束，默认不限制。
  final BoxConstraints? constraints;

  /// 默认卡片圆角；铺满页面的背景区域可显式使用 [BorderRadius.zero]。
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appearance = theme.appearance;
    final radius = borderRadius ?? BorderRadius.circular(appearance.cardRadius);
    final paper =
        paperSurface &&
        gradient == null &&
        backgroundOpacity > 0 &&
        backgroundOpacity < 1;
    final tint = color?.withValues(alpha: backgroundOpacity);
    final decoration = BoxDecoration(
      color: gradient == null
          ? (paper ? Color.alphaBlend(tint!, scheme.surface) : tint)
          : null,
      gradient: gradient,
      boxShadow:
          boxShadow ??
          (paper
              ? switch (appearance.cardStyle) {
                  AppCardStyle.paper => [
                    BoxShadow(
                      color: scheme.outlineVariant.withValues(alpha: .45),
                      offset: const Offset(0, 2),
                    ),
                  ],
                  AppCardStyle.soft => [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .1),
                      blurRadius: SpacingTokens.sm,
                      offset: const Offset(0, SpacingTokens.xs),
                    ),
                  ],
                  AppCardStyle.outlined => null,
                }
              : null),
      border:
          border ??
          (paper
              ? switch (appearance.cardStyle) {
                  AppCardStyle.paper => Border.all(
                    color: scheme.outlineVariant,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                  AppCardStyle.soft => null,
                  AppCardStyle.outlined => Border.all(
                    color: scheme.outlineVariant,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                }
              : null),
      borderRadius: radius,
    );
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(SpacingTokens.md),
      child: child,
    );
    return Container(
      width: width,
      constraints: constraints,
      decoration: decoration,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: content,
              ),
            ),
    );
  }
}
