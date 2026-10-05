// lib/core/services/update/update_check_controller.dart
//
// 层级：core/services/update
// 职责：启动/前台恢复时的自动更新检测编排 — 五重守卫链 + 静默失败。
//       由 MainShell State 持有，生命周期约等于进程期；所有异常均静默
//       记录（AppLogger），永不向调用方抛出。

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/core/utils/logger.dart';

/// 检测到可用新版本时的回调：携带远端更新信息与当前安装版本
/// （MainShell 在回调中弹窗并调用 markDialogShown）。
typedef UpdateAvailableCallback =
    void Function(AppUpdateInfo update, AppVersionInfo current);

/// 自动更新检测控制器。
class UpdateCheckController {
  UpdateCheckController({
    required bool updateCheckConfigured,
    required this.client,
    required this.installer,
    required this.onAvailable,
    this.recheckInterval = const Duration(hours: 1),
    DateTime Function()? now,
  })  : _updateCheckConfigured = updateCheckConfigured,
        _now = now ?? DateTime.now;

  final bool _updateCheckConfigured;
  final UpdateClient client;
  final AndroidUpdateInstaller installer;
  final UpdateAvailableCallback onAvailable;

  /// 前台恢复重新检测的最小间隔。
  final Duration recheckInterval;
  final DateTime Function() _now;

  bool _checking = false;
  bool _dialogActive = false;
  bool _dismissedByUser = false;
  DateTime? _lastCheckAt;

  /// 是否启用自动检测（已配置更新地址且平台支持）。
  bool get enabled => _updateCheckConfigured && installer.isSupported;

  /// 更新弹窗是否正在显示。
  bool get hasActiveDialog => _dialogActive;

  /// 用户是否已取消：本进程内永不再自动弹出更新提醒。
  bool get dismissedByUser => _dismissedByUser;

  /// 满足全部守卫时执行一次静默检测；发现新版本时回调 [onAvailable]。
  ///
  /// 守卫链顺序固定（任一命中即同步短路，零副作用）：
  /// 1. !enabled（非 Android 或未配置 URL）
  /// 2. _checking（检测进行中，防重入）
  /// 3. hasActiveDialog（弹窗显示中）
  /// 4. dismissedByUser（用户已取消，本进程抑制）
  /// 5. 距上次检测不足 [recheckInterval]
  Future<void> maybeCheck() async {
    if (!enabled) return;
    if (_checking) return;
    if (_dialogActive) return;
    if (_dismissedByUser) return;
    final lastCheckAt = _lastCheckAt;
    if (lastCheckAt != null &&
        _now().difference(lastCheckAt) < recheckInterval) {
      return;
    }

    // 先记时间再发请求：失败也计入间隔，避免失败后每次 resumed 都打网络。
    _lastCheckAt = _now();
    _checking = true;
    try {
      final current = await installer.getCurrentVersion();
      final latest = await client.fetchLatest();
      if (!latest.isNewerThan(current)) {
        // isNewerThan 已含包名一致判断；包名不一致视为配置错误，静默记录。
        if (latest.packageName != current.packageName) {
          AppLogger.w(
            '更新包名不一致：latest=${latest.packageName} '
            'current=${current.packageName}',
            tag: 'UpdateCheck',
          );
        }
        return;
      }
      onAvailable(latest, current);
    } catch (error) {
      // 自动检测的任何异常都不打扰用户，仅记录日志。
      AppLogger.w('自动检查更新失败：$error', tag: 'UpdateCheck');
    } finally {
      _checking = false;
    }
  }

  /// 标记更新弹窗已显示（由 MainShell 在 onAvailable 回调中同步调用，
  /// 保证守卫生效先于弹窗动画）。
  void markDialogShown() => _dialogActive = true;

  /// 标记更新弹窗已关闭（仅清 [hasActiveDialog]，允许下次 resumed 再检测）。
  void markDialogClosed() => _dialogActive = false;

  /// 标记用户已取消：本次进程内永不再自动弹出更新提醒。
  void markDismissedByUser() {
    _dismissedByUser = true;
    _dialogActive = false;
  }
}
