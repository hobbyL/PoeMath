// lib/core/widgets/animated_page_body.dart
//
// 层级：core/widgets
// 职责：带交错入场动画的页面内容容器，统一全局子页面内容动画。
//
// 动画效果完全复制自 poem_review_page 的 flutter_animate 风格：
// - 卡片/大组件：fadeIn 400ms + slideY(0.1) 400ms
// - 列表项/行：fadeIn 300ms + slideX(0.1) 300ms
// - 交错间隔：80ms
// - SizedBox 等间距组件自动跳过，不计入动画序列。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 带交错入场动画的可滚动页面内容。
///
/// 动画效果与复习计划页一致：fadeIn + slideX(0.1)，80ms 交错间隔。
///
/// 用法：
/// ```dart
/// AnimatedPageBody(
///   children: [
///     ColoredCard(...),
///     const SizedBox(height: SpacingTokens.lg), // 自动跳过
///     AppTile(...),
///   ],
/// )
/// ```
class AnimatedPageBody extends StatelessWidget {
  AnimatedPageBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(SpacingTokens.md),
    this.controller,
  }) {
    // 确保 SizedBox 间距组件不计入动画序列（仅首次生效）
    AnimateList.ignoreTypes.add(SizedBox);
  }

  /// 子组件列表。
  final List<Widget> children;

  /// 外边距，默认 `SpacingTokens.md`。
  final EdgeInsetsGeometry padding;

  /// 可选的滚动控制器。
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: padding,
      children: children
          .animate(interval: 80.ms)
          .fadeIn(duration: 300.ms)
          .slideX(begin: 0.1, end: 0, duration: 300.ms),
    );
  }
}
