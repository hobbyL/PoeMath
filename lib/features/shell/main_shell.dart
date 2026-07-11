// lib/features/shell/main_shell.dart
//
// 层级：features/shell
// 职责：应用主体的 5-Tab Shell（首页 / 诗词 / 学习 / 口算 / 我的）。
//       - 5 个 tab 中，第 3 个是中央凸起"学习"入口，其余 4 个用 NotchedBottomBar 展示。
//       - 点击"诗词" tab -> 切换到诗词主题；点击"口算" tab -> 切换到口算主题。
// 依赖：go_router / Riverpod / NotchedBottomBar / AppRoutes / activeSubjectProvider。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/features/shell/widgets/notched_bottom_bar.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const List<NavItem> _tabs = <NavItem>[
    NavItem(icon: Icons.home_rounded, label: '首页'),
    NavItem(icon: Icons.menu_book_rounded, label: '诗词'),
    NavItem(icon: Icons.calculate_rounded, label: '口算'),
    NavItem(icon: Icons.person_rounded, label: '我的'),
  ];

  int _index = 0;

  /// 4 个非中央 tab 对应的目标路由
  String _routeOf(int i) {
    switch (i) {
      case 0:
        return AppRoutes.home;
      case 1:
        return AppRoutes.poemTab;
      case 2:
        return AppRoutes.mathTab;
      case 3:
        return AppRoutes.profile;
      default:
        return AppRoutes.home;
    }
  }

  void _switch(int i) {
    setState(() => _index = i);
    // Tab 联动主题切换：诗词 / 口算 tab 触发学科变更
    if (i == 1) {
      ref.read(activeSubjectProvider.notifier).state = AppSubject.poem;
    } else if (i == 2) {
      ref.read(activeSubjectProvider.notifier).state = AppSubject.math;
    }
    context.go(_routeOf(i));
  }

  void _onCenterTap() {
    context.go(AppRoutes.studyHub);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: NotchedBottomBar(
        currentIndex: _index,
        onTap: _switch,
        items: _tabs,
        onCenterTap: _onCenterTap,
      ),
    );
  }
}
