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
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/features/assistant/widgets/draggable_assistant_bubble.dart';
import 'package:poemath/features/shell/update_dialog.dart';

/// controller 构造工厂：MainShell 传入自己的 onAvailable 包装后构造，
/// 保证注入路径与生产路径同构（抑制分支等 MainShell 链路可被测试覆盖）。
typedef UpdateCheckControllerFactory =
    UpdateCheckController Function(UpdateAvailableCallback onAvailable);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child, this.updateControllerFactory});

  final Widget child;

  /// 自动更新检测控制器工厂（测试注入 seam；生产不传，走真实依赖）。
  final UpdateCheckControllerFactory? updateControllerFactory;

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
    final controller = _buildController();
    _updateController = controller;
    // 首帧后触发冷启动静默检测，不阻塞首屏渲染。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(controller.maybeCheck()),
    );
    _wireNotificationTap();
  }

  @override
  void dispose() {
    // 撤销通知点击回调注册，避免 service 持有已 dispose State 的闭包
    // （identical 防止清掉测试中后续 shell 注册的新回调）。
    if (identical(
      NotificationService.instance.onNotificationTap,
      _onNotificationTap,
    )) {
      NotificationService.instance.onNotificationTap = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_updateController?.maybeCheck());
    }
  }

  /// 统一构造：工厂（测试注入）或真实依赖，onAvailable 一律挂 MainShell
  /// 的弹窗-抑制包装，保证两条路径同构。
  UpdateCheckController _buildController() {
    final factory =
        widget.updateControllerFactory ?? _realControllerFactory;
    late final UpdateCheckController controller;
    controller = factory(
      (update, current) =>
          unawaited(_onUpdateAvailable(controller, update, current)),
    );
    return controller;
  }

  UpdateCheckController _realControllerFactory(UpdateAvailableCallback onAvailable) {
    return UpdateCheckController(
      updateCheckConfigured: AppConfig.hasUpdateCheckUrl,
      client: UpdateClient(updateUrl: AppConfig.updateCheckUrl),
      installer: AndroidUpdateInstaller(),
      onAvailable: onAvailable,
    );
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

  /// R8 通知点击跳转接线：注册前台点击回调 + 首帧后消费冷启动 payload。
  ///
  /// NotificationService 保持纯 Dart（不 import GoRouter），跳转经
  /// 回调注入；service 若尚未初始化完成，[consumePendingLaunchPayload]
  /// 内部会等待初始化后再返回。
  void _wireNotificationTap() {
    NotificationService.instance.onNotificationTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_consumeNotificationLaunchPayload()),
    );
  }

  /// 已知通知 payload（每日提醒/周报）跳转复习页。
  void _onNotificationTap(String payload) {
    if (!mounted) return;
    if (payload == NotificationService.payloadDailyReminder ||
        payload == NotificationService.payloadWeeklyReport) {
      ref.read(appRouterProvider).push(AppRoutes.poemReview);
    }
  }

  Future<void> _consumeNotificationLaunchPayload() async {
    final payload =
        await NotificationService.instance.consumePendingLaunchPayload();
    if (payload == null || !mounted) return;
    _onNotificationTap(payload);
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
      body: Stack(
        children: <Widget>[
          widget.child,
          const DraggableAssistantBubble(),
        ],
      ),
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
