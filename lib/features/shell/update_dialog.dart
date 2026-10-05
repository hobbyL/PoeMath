// lib/features/shell/update_dialog.dart
//
// 层级：features/shell
// 职责：启动自动检测发现新版本后的应用内升级弹窗 — AlertDialog 内嵌
//       下载/校验/安装状态机（available → downloading → verifying →
//       ready → installing，含 permissionRequired / error 分支）。
//
// 与 UpdatePage 的关系：共享 apkCompatibilityError / friendlyUpdateError
// 纯函数，下载校验安装链语义一致；UI 独立实现（弹窗内聚，无「重新检查」态）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

/// 弹窗关闭返回值语义（MainShell 据此调 markDismissedByUser / markDialogClosed）：
/// - false：用户从未开始下载就取消/关闭 → 本进程不再自动提醒；
/// - true：曾进入 downloading 及之后任何状态关闭/完成 → 下次 resumed 可再提醒。
Future<bool?> showUpdateDialog({
  required BuildContext context,
  required AppUpdateInfo update,
  required AppVersionInfo current,
  required UpdateClient client,
  required AndroidUpdateInstaller installer,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _UpdateDialog(
      update: update,
      current: current,
      client: client,
      installer: installer,
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.update,
    required this.current,
    required this.client,
    required this.installer,
  });

  final AppUpdateInfo update;
  final AppVersionInfo current;
  final UpdateClient client;
  final AndroidUpdateInstaller installer;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateDialogPhase {
  available,
  downloading,
  verifying,
  ready,
  permissionRequired,
  installing,
  error,
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdateDialogPhase _phase = _UpdateDialogPhase.available;
  File? _downloadedApk;
  UpdateDownloadCancelToken? _downloadCancelToken;
  int _downloadReceived = 0;
  int? _downloadTotal;
  int _requestToken = 0;
  bool _everStartedDownload = false;
  String _message = '';

  @override
  void dispose() {
    // 弹窗销毁时仍在下载则取消，防止泄漏（半成品文件由 UpdateClient 清理契约删除）。
    _downloadCancelToken?.cancel();
    super.dispose();
  }

  /// 可关闭态：available / error / ready（back 键与按钮均可关闭）；
  /// downloading / verifying / installing 必须通过「取消下载」显式取消或等待完成。
  bool get _canDismiss =>
      _phase == _UpdateDialogPhase.available ||
      _phase == _UpdateDialogPhase.error ||
      _phase == _UpdateDialogPhase.ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // 拦截所有 pop 以携带确定的返回值（含系统返回键），不可关闭态静默忽略。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_canDismiss) return;
        Navigator.of(context).pop(_everStartedDownload);
      },
      child: AlertDialog(
        title: Text(_phaseTitle),
        content: _buildContent(context),
        actions: _buildActions(theme),
      ),
    );
  }

  // ---------- 正文 ----------

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = _downloadTotal != null && _downloadTotal! > 0
        ? (_downloadReceived / _downloadTotal!).clamp(0.0, 1.0).toDouble()
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_phase == _UpdateDialogPhase.available) ...[
          _buildVersionCard(theme),
          if (widget.update.notes.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.sm),
            _buildNotesCard(theme),
          ],
        ],
        if (_message.isNotEmpty) ...[
          if (_phase == _UpdateDialogPhase.available)
            const SizedBox(height: SpacingTokens.sm),
          Text(
            _message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _phase == _UpdateDialogPhase.error
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
        if (_phase == _UpdateDialogPhase.downloading) ...[
          const SizedBox(height: SpacingTokens.md),
          LinearProgressIndicator(value: progressValue),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            _downloadProgressText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_phase == _UpdateDialogPhase.verifying ||
            _phase == _UpdateDialogPhase.installing) ...[
          const SizedBox(height: SpacingTokens.md),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Widget _buildVersionCard(ThemeData theme) {
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: '当前版本',
            value: 'v${widget.current.versionName}',
          ),
          _InfoRow(
            label: '最新版本',
            value: 'v${widget.update.versionName}',
          ),
          _InfoRow(
            label: '安装包大小',
            value: _formatBytes(widget.update.apkSize),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(ThemeData theme) {
    return ColoredCard(
      color: theme.colorScheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '更新内容',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            widget.update.notes,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 操作按钮 ----------

  List<Widget> _buildActions(ThemeData theme) {
    switch (_phase) {
      case _UpdateDialogPhase.available:
        return [
          TextButton(onPressed: _close, child: const Text('取消')),
          FilledButton.icon(
            onPressed: () => unawaited(_downloadUpdate()),
            icon: const Icon(Icons.download),
            label: const Text('下载更新'),
          ),
        ];
      case _UpdateDialogPhase.downloading:
        return [
          OutlinedButton.icon(
            onPressed: _cancelDownload,
            icon: const Icon(Icons.close),
            label: const Text('取消下载'),
          ),
        ];
      case _UpdateDialogPhase.verifying:
      case _UpdateDialogPhase.installing:
        return [
          FilledButton.icon(
            onPressed: null,
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text(_phase == _UpdateDialogPhase.verifying ? '校验中' : '打开中'),
          ),
        ];
      case _UpdateDialogPhase.ready:
        return [
          TextButton(onPressed: _close, child: const Text('关闭')),
          FilledButton.icon(
            onPressed: () => unawaited(_installUpdate()),
            icon: const Icon(Icons.install_mobile),
            label: const Text('立即安装'),
          ),
        ];
      case _UpdateDialogPhase.permissionRequired:
        return [
          TextButton(
            onPressed: () => unawaited(_installUpdate()),
            child: const Text('继续安装'),
          ),
          FilledButton.icon(
            onPressed: () => unawaited(_openInstallPermissionSettings()),
            icon: const Icon(Icons.settings),
            label: const Text('打开权限设置'),
          ),
        ];
      case _UpdateDialogPhase.error:
        return [
          TextButton(onPressed: _close, child: const Text('取消')),
          FilledButton.icon(
            onPressed: () => unawaited(_downloadUpdate()),
            icon: const Icon(Icons.refresh),
            label: const Text('重试下载'),
          ),
        ];
    }
  }

  // ---------- 业务逻辑（链路对齐 UpdatePage，token 守卫防 stale 回调） ----------

  Future<void> _downloadUpdate() async {
    final token = ++_requestToken;
    final cancelToken = UpdateDownloadCancelToken();
    _downloadCancelToken = cancelToken;
    _everStartedDownload = true;
    setState(() {
      _phase = _UpdateDialogPhase.downloading;
      _message = '';
      _downloadedApk = null;
      _downloadReceived = 0;
      _downloadTotal = widget.update.apkSize > 0 ? widget.update.apkSize : null;
    });

    try {
      final file = await widget.client.downloadApk(
        widget.update,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!mounted || token != _requestToken) return;
          setState(() {
            _downloadReceived = received;
            _downloadTotal = total;
          });
        },
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _phase = _UpdateDialogPhase.verifying;
        _message = '正在校验安装包。';
      });

      final digest = await widget.client.sha256Of(file);
      if (!mounted || token != _requestToken) return;
      if (digest.toLowerCase() != widget.update.apkSha256.toLowerCase()) {
        throw const UpdateException('安装包校验失败，已阻止安装。');
      }

      final apkInfo = await widget.installer.inspectApk(file.path);
      if (!mounted || token != _requestToken) return;
      final compatibilityError = apkCompatibilityError(
        latest: widget.update,
        current: widget.current,
        apk: apkInfo,
      );
      if (compatibilityError != null) throw UpdateException(compatibilityError);

      setState(() {
        _phase = _UpdateDialogPhase.ready;
        _downloadedApk = file;
        _message = '安装包已下载并校验完成。';
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      if (error is UpdateCancelledException) {
        setState(() {
          _phase = _UpdateDialogPhase.available;
          _message = '下载已取消。';
        });
      } else {
        setState(() {
          _phase = _UpdateDialogPhase.error;
          _message = friendlyUpdateError(error, fallback: '下载更新失败，请稍后重试。');
        });
      }
    } finally {
      if (mounted && token == _requestToken) _downloadCancelToken = null;
    }
  }

  Future<void> _installUpdate() async {
    final file = _downloadedApk;
    if (file == null) return;
    final token = ++_requestToken;

    try {
      final canInstall = await widget.installer.canRequestPackageInstalls();
      if (!mounted || token != _requestToken) return;
      if (!canInstall) {
        setState(() {
          _phase = _UpdateDialogPhase.permissionRequired;
          _message = 'Android 需要允许本应用安装未知来源应用后，才能继续安装更新。';
        });
        return;
      }

      setState(() {
        _phase = _UpdateDialogPhase.installing;
        _message = '正在打开系统安装器。';
      });
      await widget.installer.installApk(file.path);
      if (!mounted || token != _requestToken) return;
      // 系统安装器接管后弹窗不自动关闭（用户装完系统会杀进程重启）。
      setState(() {
        _phase = _UpdateDialogPhase.ready;
        _message = '已打开系统安装器，请按系统提示完成安装。';
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _message = friendlyUpdateError(error, fallback: '打开安装器失败，请稍后重试。');
      });
    }
  }

  Future<void> _openInstallPermissionSettings() async {
    try {
      await widget.installer.openInstallPermissionSettings();
      if (!mounted) return;
      setState(() {
        _message = '请在系统设置中允许本应用安装未知来源应用，返回后继续安装。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _message = friendlyUpdateError(error, fallback: '无法打开安装权限设置。');
      });
    }
  }

  void _cancelDownload() => _downloadCancelToken?.cancel();

  void _close() => Navigator.of(context).pop(_everStartedDownload);

  // ---------- 辅助方法 ----------

  String get _phaseTitle => switch (_phase) {
        _UpdateDialogPhase.available => '发现新版本',
        _UpdateDialogPhase.downloading => '正在下载',
        _UpdateDialogPhase.verifying => '正在校验',
        _UpdateDialogPhase.ready => '可以安装',
        _UpdateDialogPhase.permissionRequired => '需要安装权限',
        _UpdateDialogPhase.installing => '正在安装',
        _UpdateDialogPhase.error => '更新失败',
      };

  String get _downloadProgressText {
    final total = _downloadTotal;
    if (total == null || total <= 0) {
      return '已下载 ${_formatBytes(_downloadReceived)}';
    }
    return '已下载 ${_formatBytes(_downloadReceived)} / ${_formatBytes(total)}';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '未知';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

// ---------- 版本信息行（与 UpdatePage 同构的简单布局行） ----------

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
