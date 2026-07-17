// lib/features/shell/main_shell.dart
//
// 层级：features/shell
// 职责：应用主体的 4-Tab Shell（首页 / 诗词 / 口算 / 我的）。
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
  /// 4 个 tab 对应的目标路由。
  static const List<String> _routes = [
    AppRoutes.home,
    AppRoutes.poemTab,
    AppRoutes.mathTab,
    AppRoutes.profile,
  ];

  /// 根据当前路由推导 tab index。
  int _indexFromRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == AppRoutes.poemTab) return 1;
    if (location == AppRoutes.mathTab) return 2;
    if (location == AppRoutes.profile) return 3;
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
