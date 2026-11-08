// lib/features/shell/main_shell.dart
//
// 层级：features/shell
// 职责：应用主体的 4-Tab Shell（首页 / 语文 / 口算 / 我的）+
//       启动/前台恢复自动检测更新的挂载点（WidgetsBindingObserver）。
// 依赖：go_router / Riverpod / AppRoutes / UpdateCheckController。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/config/app_config.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/features/assistant/assistant_enabled_provider.dart';
import 'package:poemath/features/assistant/widgets/draggable_assistant_bubble.dart';
import 'package:poemath/features/shell/update_dialog.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

/// controller 构造工厂：MainShell 传入自己的 onAvailable 包装后构造，
/// 保证注入路径与生产路径同构（抑制分支等 MainShell 链路可被测试覆盖）。
typedef UpdateCheckControllerFactory = UpdateCheckController Function(
  UpdateAvailableCallback onAvailable,
);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.child,
    this.updateControllerFactory,
    this.notifications,
  });

  final Widget child;

  /// 自动更新检测控制器工厂（测试注入 seam；生产不传，走真实依赖）。
  final UpdateCheckControllerFactory? updateControllerFactory;
  final NotificationService? notifications;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  /// 4 个 tab 对应的目标路由。
  static const List<String> _routes = [
    AppRoutes.home,
    AppRoutes.chineseTab,
    AppRoutes.mathTab,
    AppRoutes.profile,
  ];

  static const _destinations = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: '首页'),
    (
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      label: '语文',
    ),
    (
      icon: Icons.calculate_outlined,
      selectedIcon: Icons.calculate_rounded,
      label: '口算',
    ),
    (
      icon: Icons.person_outlined,
      selectedIcon: Icons.person_rounded,
      label: '我的',
    ),
  ];

  UpdateCheckController? _updateController;
  late final NotificationService _notifications =
      widget.notifications ?? NotificationService.instance;

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
    unawaited(_maybeSnapshot());
    unawaited(_restoreTextbookDownloads());
  }

  @override
  void dispose() {
    // 撤销通知点击回调注册，避免 service 持有已 dispose State 的闭包
    // （identical 防止清掉测试中后续 shell 注册的新回调）。
    if (identical(_notifications.onNotificationTap, _onNotificationTap)) {
      _notifications.onNotificationTap = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_updateController?.maybeCheck());
      unawaited(_maybeSnapshot());
      unawaited(_restoreTextbookDownloads());
    }
  }

  Future<void> _restoreTextbookDownloads() async {
    try {
      if (ref.read(textbookDownloadRepositoryProvider).pendingIds().isEmpty) {
        return;
      }
      final downloads = ref.read(textbookDownloadsProvider.notifier);
      final catalog = await ref.read(textbookCatalogProvider.future);
      if (!mounted) return;
      await downloads.restorePending(catalog);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材下载恢复失败，下次返回应用时重试',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _maybeSnapshot() async {
    try {
      await ref.read(backupHistoryProvider).maybeCreateDaily();
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '每日快照暂未完成，下次回到应用将重试',
        tag: 'Backup',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 统一构造：工厂（测试注入）或真实依赖，onAvailable 一律挂 MainShell
  /// 的弹窗-抑制包装，保证两条路径同构。
  UpdateCheckController _buildController() {
    final factory = widget.updateControllerFactory ?? _realControllerFactory;
    late final UpdateCheckController controller;
    controller = factory(
      (update, current) =>
          unawaited(_onUpdateAvailable(controller, update, current)),
    );
    return controller;
  }

  UpdateCheckController _realControllerFactory(
    UpdateAvailableCallback onAvailable,
  ) {
    return UpdateCheckController(
      updateCheckConfigured: AppConfig.hasUpdateCheckUrl,
      client: UpdateClient(updateUrl: AppConfig.updateCheckUrl),
      installer: AndroidUpdateInstaller(),
      onAvailable: onAvailable,
    );
  }

  /// 展示「有新版本」弹窗。
  ///
  /// 本方法经 `unawaited(...)` 从 `UpdateCheckController.onAvailable` 触发
  /// （该回调是同步 `void`，`unawaited` 的 Future 不会回流到 controller 的
  /// try-catch）。因此这里必须自己兜住异常：一旦 `showUpdateDialog` 抛错
  /// 且无人接，`markDialogShown()` 已被调用而弹窗从未展示，`hasActiveDialog`
  /// 会**永久**卡在 true —— 之后所有更新检查都被这个守卫静默吞掉，
  /// 用户再也不会收到升级提示，且线上无从察觉。捕获后补一次
  /// `markDialogClosed()` 把状态放回可用，是这里的关键。
  Future<void> _onUpdateAvailable(
    UpdateCheckController controller,
    AppUpdateInfo update,
    AppVersionInfo current,
  ) async {
    if (!mounted) return;
    // 先同步标记弹窗显示，保证守卫（hasActiveDialog）先于弹窗动画生效。
    controller.markDialogShown();
    try {
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
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '更新弹窗展示失败',
        tag: 'MainShell',
        error: error,
        stackTrace: stackTrace,
      );
      // 复位守卫：否则 hasActiveDialog 永久为 true，后续更新检查全部被吞。
      controller.markDialogClosed();
    }
  }

  /// R8 通知点击跳转接线：注册前台点击回调 + 首帧后消费冷启动 payload。
  ///
  /// NotificationService 保持纯 Dart（不 import GoRouter），跳转经
  /// 回调注入；service 若尚未初始化完成，[consumePendingLaunchPayload]
  /// 内部会等待初始化后再返回。
  void _wireNotificationTap() {
    _notifications.onNotificationTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_consumeNotificationLaunchPayload()),
    );
  }

  /// 实时与冷启动通知共用落点，周报进入报告、每日提醒进入复习。
  void _onNotificationTap(String payload) {
    if (!mounted) return;
    final route = switch (payload) {
      NotificationService.payloadDailyReminder => AppRoutes.poemReview,
      NotificationService.payloadWeeklyReport => AppRoutes.weeklyReport,
      _ => null,
    };
    if (route != null) ref.read(appRouterProvider).push(route);
  }

  Future<void> _consumeNotificationLaunchPayload() async {
    final payload = await _notifications.consumePendingLaunchPayload();
    if (payload == null || !mounted) return;
    _onNotificationTap(payload);
  }

  /// 根据当前路由推导 tab index。
  int _indexFromRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == AppRoutes.chineseTab || location == AppRoutes.poemTab) {
      return 1;
    }
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
    final assistantEnabled = ref.watch(assistantEnabledProvider);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          widget.child,
          if (assistantEnabled) const DraggableAssistantBubble(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: SpacingTokens.xl * 2,
        selectedIndex: currentIndex,
        onDestinationSelected: _switch,
        destinations: [
          for (var i = 0; i < _destinations.length; i++)
            _NavigationTab(
              key: ValueKey('navigation-tab-${_destinations[i].label}'),
              selected: i == currentIndex,
              label: _destinations[i].label,
              icon: _destinations[i].icon,
              selectedIcon: _destinations[i].selectedIcon,
              onTap: () => _switch(i),
            ),
        ],
      ),
    );
  }
}

/// 原生 NavigationBar 管理选中语义，胶囊按钮统一包裹横排图标与文字。
class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    super.key,
    required this.selected,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final states = <WidgetState>{if (selected) WidgetState.selected};
    final labelStyle =
        theme.navigationBarTheme.labelTextStyle?.resolve(states) ??
        theme.textTheme.labelMedium!.copyWith(
          color: selected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SpacingTokens.xxl * 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
          // 沿用 Material NavigationDestination 的标签缩放上限。
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: labelStyle.color,
                    backgroundColor: selected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    textStyle: labelStyle,
                    iconSize: SpacingTokens.lg,
                    minimumSize: const Size(0, SpacingTokens.minTapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.xs,
                      vertical: SpacingTokens.sm,
                    ),
                    shape: const StadiumBorder(),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    animationDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(selected ? selectedIcon : icon),
                      const SizedBox(width: SpacingTokens.xs),
                      Text(label),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
