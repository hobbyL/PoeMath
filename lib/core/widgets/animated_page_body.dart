// lib/core/widgets/animated_page_body.dart
//
// 层级：core/widgets
// 职责：带交错入场动画的页面内容容器，统一全局子页面内容动画。
//
// 效果与复习计划页的 flutter_animate 动画一致：
// 每个子组件依次 fadeIn + slideY(0.08) 浮现，间隔 60ms，时长 400ms。
// SizedBox 等间距组件自动跳过，不计入动画序列。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 带交错入场动画的可滚动页面内容。
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
    this.interval = const Duration(milliseconds: 60),
    this.duration = const Duration(milliseconds: 400),
    this.controller,
  }) {
    // 确保 SizedBox 间距组件不计入动画序列（仅首次生效）
    AnimateList.ignoreTypes.add(SizedBox);
  }

  /// 子组件列表。
  final List<Widget> children;

  /// 外边距，默认 `SpacingTokens.md`。
  final EdgeInsetsGeometry padding;

  /// 相邻子组件的动画间隔，默认 60ms。
  final Duration interval;

  /// 单个子组件的动画时长，默认 400ms。
  final Duration duration;

  /// 可选的滚动控制器。
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: padding,
      children: children
          .animate(interval: interval)
          .fadeIn(duration: duration, curve: Curves.easeOut)
          .slideY(
            begin: 0.08,
            end: 0,
            duration: duration,
            curve: Curves.easeOutCubic,
          ),
    );
  }
}
