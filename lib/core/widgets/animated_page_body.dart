// lib/core/widgets/animated_page_body.dart
//
// 层级：core/widgets
// 职责：带交错入场动画的页面内容容器，统一全局子页面内容动画。
//
// 开启页面动画时：仅前几项短暂交错入场，后续滚动内容立即显示。
// SizedBox 等间距组件不生成动画。关闭时直接显示最终状态并保留子组件 State。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';

/// 带交错入场动画的可滚动页面内容。
///
/// 复用列表入场策略，间距不计入序列，整体入场不超过半秒。
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
    var contentIndex = 0;
    return ListView(
      controller: controller,
      padding: padding,
      children: [
        for (final child in children)
          if (AnimateList.ignoreTypes.contains(child.runtimeType))
            child
          else
            child.animateListItem(context, index: contentIndex++),
      ],
    );
  }
}
