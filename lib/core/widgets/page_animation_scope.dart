// lib/core/widgets/page_animation_scope.dart
//
// 职责：把页面动画偏好传给页面内容，关闭时直接呈现动画的最终状态。

import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PageAnimationScope extends InheritedWidget {
  const PageAnimationScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PageAnimationScope>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(PageAnimationScope oldWidget) =>
      enabled != oldWidget.enabled;
}

extension PageAnimationExtensions on Widget {
  /// 列表只为开头少量条目播放入场，后续滚入视口的内容直接可见。
  /// 按绝对索引累计延迟会让长列表后部等待数秒，误以为滚动或点击失灵。
  Widget animateListItem(
    BuildContext context, {
    required int index,
    Offset begin = const Offset(0.1, 0),
  }) {
    const animatedItems = 6;
    const stagger = Duration(milliseconds: 40);
    const duration = Duration(milliseconds: 300);
    if (index >= animatedItems) return this;
    return RepaintBoundary(child: this)
        .animatePage(context, delay: stagger * index)
        .fadeIn(duration: duration)
        .slide(begin: begin, end: Offset.zero, duration: duration);
  }

  /// 仅用于页面内容入场；操作反馈、庆祝和播放状态使用各自的动画。
  /// 保留 Animate 子树，切换偏好时不重建表单、滚动项等子组件的 State。
  Animate animatePage(
    BuildContext context, {
    Key? key,
    Duration? delay,
  }) {
    final enabled = PageAnimationScope.enabledOf(context);
    return animate(
      key: key,
      delay: enabled ? delay : Duration.zero,
      autoPlay: enabled,
      value: enabled ? null : 1,
    );
  }
}
