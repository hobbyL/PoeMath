// lib/features/profile/update_page.dart
//
// 层级：features/profile
// 职责：应用内检查更新页面 — 状态机驱动的检查、下载、校验、安装流程。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/core/services/update/update_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({
    required this.updateClient,
    required this.updateInstaller,
    super.key,
  });

  final UpdateClient updateClient;
  final AndroidUpdateInstaller updateInstaller;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  _UpdatePhase _phase = _UpdatePhase.checking;
  AppVersionInfo? _current;
  AppUpdateInfo? _latest;
  File? _downloadedApk;
  UpdateDownloadCancelToken? _downloadCancelToken;
  int _downloadReceived = 0;
  int? _downloadTotal;
  int _requestToken = 0;
  String _message = '正在检查最新版本。';

  @override
  void initState() {
    super.initState();
    unawaited(_checkForUpdates());
  }

  @override
  void dispose() {
    _downloadCancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          children: [
            _buildStatusCard(context),
            if (_current != null || _latest != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              _buildVersionCard(context),
            ],
            if ((_latest?.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.sm),
              _buildNotesCard(context),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- 状态卡片 ----------

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = _downloadTotal != null && _downloadTotal! > 0
        ? (_downloadReceived / _downloadTotal!).clamp(0.0, 1.0).toDouble()
        : null;

    return ColoredCard(
      color: _phaseColor(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_phaseIcon, color: _phaseColor(theme)),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _phaseTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      _message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_phase == _UpdatePhase.downloading) ...[
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
          const SizedBox(height: SpacingTokens.lg),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            children: _buildActions(),
          ),
        ],
      ),
    );
  }

  // ---------- 版本信息卡片 ----------

  Widget _buildVersionCard(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    final latest = _latest;

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '版本信息',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          if (current != null)
            _InfoRow(
              label: '当前版本',
              value: '${current.versionName}+${current.versionCode}',
            ),
          if (latest != null) ...[
            _InfoRow(
              label: '最新版本',
              value: '${latest.versionName}+${latest.versionCode}',
            ),
            _InfoRow(label: '安装包大小', value: _formatBytes(latest.apkSize)),
            if (latest.channel.isNotEmpty)
              _InfoRow(label: '发布通道', value: latest.channel),
          ],
        ],
      ),
    );
  }

  // ---------- 更新说明卡片 ----------

  Widget _buildNotesCard(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredCard(
      color: theme.colorScheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '更新内容',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _latest!.notes,
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

  List<Widget> _buildActions() {
    switch (_phase) {
      case _UpdatePhase.checking:
      case _UpdatePhase.verifying:
      case _UpdatePhase.installing:
        return [
          FilledButton.icon(
            onPressed: null,
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text(_busyButtonText),
          ),
        ];
      case _UpdatePhase.downloading:
        return [
          OutlinedButton.icon(
            onPressed: _cancelDownload,
            icon: const Icon(Icons.close),
            label: const Text('取消下载'),
          ),
        ];
      case _UpdatePhase.available:
        return [
          FilledButton.icon(
            onPressed: () => unawaited(_downloadUpdate()),
            icon: const Icon(Icons.download),
            label: const Text('下载更新'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(_checkForUpdates()),
            icon: const Icon(Icons.refresh),
            label: const Text('重新检查'),
          ),
        ];
      case _UpdatePhase.ready:
        return [
          FilledButton.icon(
            onPressed: () => unawaited(_installUpdate()),
            icon: const Icon(Icons.install_mobile),
            label: const Text('立即安装'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(_downloadUpdate()),
            icon: const Icon(Icons.download),
            label: const Text('重新下载'),
          ),
        ];
      case _UpdatePhase.permissionRequired:
        return [
          FilledButton.icon(
            onPressed: () => unawaited(_openInstallPermissionSettings()),
            icon: const Icon(Icons.settings),
            label: const Text('打开权限设置'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(_installUpdate()),
            icon: const Icon(Icons.install_mobile),
            label: const Text('继续安装'),
          ),
        ];
      case _UpdatePhase.noUpdate:
      case _UpdatePhase.error:
        return [
          FilledButton.icon(
            onPressed: () => unawaited(_checkForUpdates()),
            icon: const Icon(Icons.refresh),
            label: const Text('重新检查'),
          ),
        ];
    }
  }

  // ---------- 业务逻辑 ----------

  Future<void> _checkForUpdates() async {
    _downloadCancelToken?.cancel();
    final token = ++_requestToken;
    setState(() {
      _phase = _UpdatePhase.checking;
      _message = '正在检查最新版本。';
      _downloadedApk = null;
      _downloadReceived = 0;
      _downloadTotal = null;
    });

    try {
      final current = await widget.updateInstaller.getCurrentVersion();
      final latest = await widget.updateClient.fetchLatest();
      if (!mounted || token != _requestToken) return;

      if (latest.packageName != current.packageName) {
        setState(() {
          _current = current;
          _latest = latest;
          _phase = _UpdatePhase.error;
          _message =
              '更新包名 ${latest.packageName} 与当前应用 ${current.packageName} 不一致。';
        });
        return;
      }

      setState(() {
        _current = current;
        _latest = latest;
        if (latest.versionCode > current.versionCode) {
          _phase = _UpdatePhase.available;
          _message = '发现新版本 ${latest.versionName}+${latest.versionCode}。';
        } else {
          _phase = _UpdatePhase.noUpdate;
          _message = '当前已经是最新版本。';
        }
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _message = _friendlyError(error, fallback: '检查更新失败，请稍后重试。');
      });
    }
  }

  Future<void> _downloadUpdate() async {
    final latest = _latest;
    final current = _current;
    if (latest == null || current == null) return;

    final token = ++_requestToken;
    final cancelToken = UpdateDownloadCancelToken();
    _downloadCancelToken = cancelToken;
    setState(() {
      _phase = _UpdatePhase.downloading;
      _message = '正在下载安装包。';
      _downloadedApk = null;
      _downloadReceived = 0;
      _downloadTotal = latest.apkSize > 0 ? latest.apkSize : null;
    });

    try {
      final file = await widget.updateClient.downloadApk(
        latest,
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
        _phase = _UpdatePhase.verifying;
        _message = '正在校验安装包。';
      });

      final digest = await widget.updateClient.sha256Of(file);
      if (!mounted || token != _requestToken) return;
      if (digest.toLowerCase() != latest.apkSha256.toLowerCase()) {
        throw const UpdateException('安装包校验失败，已阻止安装。');
      }

      final apkInfo = await widget.updateInstaller.inspectApk(file.path);
      if (!mounted || token != _requestToken) return;
      final compatibilityError = _apkCompatibilityError(
        latest: latest,
        current: current,
        apk: apkInfo,
      );
      if (compatibilityError != null) throw UpdateException(compatibilityError);

      setState(() {
        _phase = _UpdatePhase.ready;
        _downloadedApk = file;
        _message = '安装包已下载并校验完成。';
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      if (error is UpdateCancelledException) {
        setState(() {
          _phase = _UpdatePhase.available;
          _message = '下载已取消。';
        });
      } else {
        setState(() {
          _phase = _UpdatePhase.error;
          _message = _friendlyError(error, fallback: '下载更新失败，请稍后重试。');
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
      final canInstall =
          await widget.updateInstaller.canRequestPackageInstalls();
      if (!mounted || token != _requestToken) return;
      if (!canInstall) {
        setState(() {
          _phase = _UpdatePhase.permissionRequired;
          _message = 'Android 需要允许本应用安装未知来源应用后，才能继续安装更新。';
        });
        return;
      }

      setState(() {
        _phase = _UpdatePhase.installing;
        _message = '正在打开系统安装器。';
      });
      await widget.updateInstaller.installApk(file.path);
      if (!mounted || token != _requestToken) return;
      setState(() {
        _phase = _UpdatePhase.ready;
        _message = '已打开系统安装器，请按系统提示完成安装。';
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _message = _friendlyError(error, fallback: '打开安装器失败，请稍后重试。');
      });
    }
  }

  Future<void> _openInstallPermissionSettings() async {
    try {
      await widget.updateInstaller.openInstallPermissionSettings();
      if (!mounted) return;
      setState(() {
        _message = '请在系统设置中允许本应用安装未知来源应用，返回后继续安装。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _message = _friendlyError(error, fallback: '无法打开安装权限设置。');
      });
    }
  }

  void _cancelDownload() {
    _downloadCancelToken?.cancel();
  }

  // ---------- 辅助方法 ----------

  String? _apkCompatibilityError({
    required AppUpdateInfo latest,
    required AppVersionInfo current,
    required AppVersionInfo? apk,
  }) {
    if (apk == null) return '无法读取安装包信息，已阻止安装。';
    if (apk.packageName != current.packageName) {
      return '安装包名 ${apk.packageName} 与当前应用 ${current.packageName} 不一致。';
    }
    if (apk.packageName != latest.packageName) {
      return '安装包名 ${apk.packageName} 与更新信息 ${latest.packageName} 不一致。';
    }
    if (apk.versionCode != latest.versionCode) {
      return '安装包版本号 ${apk.versionCode} 与更新信息 ${latest.versionCode} 不一致。';
    }
    if (apk.versionCode <= current.versionCode) {
      return '安装包版本不高于当前版本，已阻止安装。';
    }
    return null;
  }

  String _friendlyError(Object error, {required String fallback}) {
    if (error is UpdateConfigurationException) return '当前安装包未配置更新检查地址。';
    if (error is UpdateException) {
      if (error.statusCode == 404) return '更新信息不存在，请确认发布配置。';
      if (error.statusCode == 429) return '请求过于频繁，请稍后重试。';
      if ((error.statusCode ?? 0) >= 500) return '更新服务暂时不可用，请稍后重试。';
      if (error.message.isNotEmpty) return error.message;
    }
    if (error is UpdateInstallException) return error.message;
    return fallback;
  }

  String get _phaseTitle => switch (_phase) {
        _UpdatePhase.checking => '正在检查',
        _UpdatePhase.noUpdate => '已是最新',
        _UpdatePhase.available => '发现更新',
        _UpdatePhase.downloading => '正在下载',
        _UpdatePhase.verifying => '正在校验',
        _UpdatePhase.ready => '可以安装',
        _UpdatePhase.permissionRequired => '需要安装权限',
        _UpdatePhase.installing => '正在安装',
        _UpdatePhase.error => '更新失败',
      };

  IconData get _phaseIcon => switch (_phase) {
        _UpdatePhase.checking ||
        _UpdatePhase.downloading ||
        _UpdatePhase.verifying ||
        _UpdatePhase.installing =>
          Icons.sync,
        _UpdatePhase.noUpdate => Icons.verified,
        _UpdatePhase.available => Icons.system_update_alt,
        _UpdatePhase.ready => Icons.check_circle,
        _UpdatePhase.permissionRequired => Icons.security,
        _UpdatePhase.error => Icons.error_outline,
      };

  Color _phaseColor(ThemeData theme) => switch (_phase) {
        _UpdatePhase.error => theme.colorScheme.error,
        _UpdatePhase.noUpdate || _UpdatePhase.ready => theme.semantic.success,
        _ => theme.colorScheme.primary,
      };

  String get _busyButtonText => switch (_phase) {
        _UpdatePhase.checking => '检查中',
        _UpdatePhase.verifying => '校验中',
        _UpdatePhase.installing => '打开中',
        _ => '处理中',
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

// ---------- 版本信息行 ----------

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

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

// ---------- 更新阶段枚举 ----------

enum _UpdatePhase {
  checking,
  noUpdate,
  available,
  downloading,
  verifying,
  ready,
  permissionRequired,
  installing,
  error,
}
