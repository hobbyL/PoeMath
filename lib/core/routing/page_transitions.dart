// lib/core/routing/page_transitions.dart
//
// 层级：core/routing
// 职责：全局页面转场动画 — 淡入 + 从下方上滑，与复习计划页内容动画风格一致。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// GoRouter 路由使用的自定义转场页面。
///
/// 效果：淡入 + 从底部上滑（0.08 高度偏移），与复习计划页的
/// `flutter_animate` 内容动画（fadeIn + slideY 0.1）风格统一。
CustomTransitionPage<T> fadeSlideTransitionPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: _fadeSlideUpTransition,
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
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: _fadeSlideUpTransition,
  );
}

/// 共用的转场动画构建器：fadeIn + slideUp。
///
/// 进入效果：从下方 0.08 偏移淡入上滑（与 poem_review_page 的
/// `.animate().fadeIn(400.ms).slideY(begin: 0.1)` 视觉一致）。
/// 退出效果：轻微下沉 + 淡出。
Widget _fadeSlideUpTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final fadeIn = CurveTween(curve: Curves.easeOut).animate(animation);
  final slideIn = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);

  // 当前页面被新页面覆盖时的退出效果：微淡出 + 微下沉
  final fadeOut = Tween<double>(begin: 1.0, end: 0.94)
      .chain(CurveTween(curve: Curves.easeIn))
      .animate(secondaryAnimation);
  final slideOut = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(0, 0.02),
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
