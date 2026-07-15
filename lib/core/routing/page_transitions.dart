// lib/core/routing/page_transitions.dart
//
// 层级：core/routing
// 职责：全局页面转场动画 — 淡入 + 微滑，统一应用到所有子页面导航。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// GoRouter 路由使用的自定义转场页面。
///
/// 效果：淡入 + 从右侧微滑进入（0.04 宽度偏移），easeOutCubic 曲线。
CustomTransitionPage<T> fadeSlideTransitionPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: _fadeSlideTransition,
  );
}

/// Navigator.push 使用的自定义转场路由。
///
/// 与 [fadeSlideTransitionPage] 效果一致，用于非 GoRouter 的页面跳转。
PageRouteBuilder<T> fadeSlideRoute<T>({
  required WidgetBuilder builder,
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: _fadeSlideTransition,
  );
}

/// 共用的转场动画构建器。
Widget _fadeSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final fadeIn = CurveTween(curve: Curves.easeOut).animate(animation);
  final slideIn = Tween<Offset>(
    begin: const Offset(0.04, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);

  // 当前页面被新页面覆盖时的退出效果：微淡出 + 微左移
  final fadeOut = Tween<double>(begin: 1.0, end: 0.92)
      .chain(CurveTween(curve: Curves.easeIn))
      .animate(secondaryAnimation);
  final slideOut = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-0.02, 0),
  ).chain(CurveTween(curve: Curves.easeInCubic)).animate(secondaryAnimation);

  return FadeTransition(
    opacity: fadeOut,
    child: SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeIn,
        child: SlideTransition(
          position: slideIn,
          child: child,
        ),
      ),
    ),
  );
}
