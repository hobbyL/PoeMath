// lib/features/shell/main_shell.dart
//
// 层级：features/shell
// 职责：应用主体的 5-Tab Shell（首页 / 诗词 / 学习 / 口算 / 我的）。
//       - 5 个 tab 以 NavigationBar 平级展示，不再使用中央浮动按钮。
// 依赖：go_router / Riverpod / AppRoutes。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 5 个 tab 对应的目标路由（顺序与 NavigationDestination 一致）。
  static const List<String> _routes = [
    AppRoutes.home,
    AppRoutes.poemTab,
    AppRoutes.studyHub,
    AppRoutes.mathTab,
    AppRoutes.profile,
  ];

  /// 根据当前路由推导 tab index。
  int _indexFromRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == AppRoutes.poemTab) return 1;
    if (location == AppRoutes.studyHub) return 2;
    if (location == AppRoutes.mathTab) return 3;
    if (location == AppRoutes.profile) return 4;
    return 0;
  }

  void _switch(int i) {
    context.go(_routes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexFromRoute(context);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: _switch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: '诗词',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: '知识库',
          ),
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate_rounded),
            label: '口算',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
