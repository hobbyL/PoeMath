// lib/features/shell/main_shell.dart
//
// 层级：features/shell
// 职责：应用主体的 4-Tab Shell（首页 / 诗词 / 口算 / 我的）+
//       启动/前台恢复自动检测更新的挂载点（WidgetsBindingObserver）。
// 依赖：go_router / Riverpod / AppRoutes / UpdateCheckController。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/config/app_config.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/features/shell/update_dialog.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child, this.updateCheckController});

  final Widget child;

  /// 自动更新检测控制器（测试注入 seam；生产不传，走真实依赖）。
  final UpdateCheckController? updateCheckController;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  /// 4 个 tab 对应的目标路由。
  static const List<String> _routes = [
    AppRoutes.home,
    AppRoutes.poemTab,
    AppRoutes.mathTab,
    AppRoutes.profile,
  ];

  UpdateCheckController? _updateController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final controller = widget.updateCheckController ?? _buildRealController();
    _updateController = controller;
    // 首帧后触发冷启动静默检测，不阻塞首屏渲染。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(controller.maybeCheck()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_updateController?.maybeCheck());
    }
  }

  UpdateCheckController _buildRealController() {
    late final UpdateCheckController controller;
    controller = UpdateCheckController(
      updateCheckConfigured: AppConfig.hasUpdateCheckUrl,
      client: UpdateClient(updateUrl: AppConfig.updateCheckUrl),
      installer: AndroidUpdateInstaller(),
      onAvailable: (update, current) =>
          unawaited(_onUpdateAvailable(controller, update, current)),
    );
    return controller;
  }

  Future<void> _onUpdateAvailable(
    UpdateCheckController controller,
    AppUpdateInfo update,
    AppVersionInfo current,
  ) async {
    if (!mounted) return;
    // 先同步标记弹窗显示，保证守卫（hasActiveDialog）先于弹窗动画生效。
    controller.markDialogShown();
    final dismissed = await showUpdateDialog(
      context: context,
      update: update,
      current: current,
      client: controller.client,
      installer: controller.installer,
    );
    // controller 不依赖 context，await 后直接调用安全。
    if (dismissed == false) {
      controller.markDismissedByUser();
    } else {
      controller.markDialogClosed();
    }
  }

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
