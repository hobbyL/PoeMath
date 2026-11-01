// lib/core/routing/page_transitions.dart
//
// 层级：core/routing
// 职责：页面转场主题；开启时淡入上滑，关闭时使用 Flutter 平台默认转场。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// GoRouter 与 Navigator 均使用 Material 路由，由应用主题选择转场。
/// 这样关闭自定义动画时保留平台默认的时长、返回手势与预测式返回。
MaterialPage<T> fadeSlideTransitionPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return MaterialPage<T>(
    key: state.pageKey,
    child: child,
  );
}

/// Navigator.push 使用的路由，与 GoRouter 共用应用转场主题。
///
/// 与 [fadeSlideTransitionPage] 效果一致，用于非 GoRouter 的页面跳转。
MaterialPageRoute<T> fadeSlideRoute<T>({
  required WidgetBuilder builder,
}) {
  return MaterialPageRoute<T>(builder: builder);
}

/// 关闭时直接交还平台默认主题，不把默认 push 动画替换为无动画。
PageTransitionsTheme pageTransitionsThemeFor(bool enabled) {
  if (!enabled) return const PageTransitionsTheme();
  return const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.iOS: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.macOS: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.windows: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.linux: FadeSlidePageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeSlidePageTransitionsBuilder(),
    },
  );
}

class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _fadeSlideUpTransition(context, animation, secondaryAnimation, child);
}

/// 共用的转场动画构建器：fadeIn + slideUp。
///
/// 进入效果：从下方 0.1 偏移淡入上滑（与 poem_review_page 的
/// `.animate().fadeIn(400.ms).slideY(begin: 0.1)` 完全一致）。
/// 退出效果：轻微下沉 + 淡出。
Widget _fadeSlideUpTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final fadeIn = CurveTween(curve: Curves.easeOut).animate(animation);
  final slideIn = Tween<Offset>(
    begin: const Offset(0, 0.1),
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
