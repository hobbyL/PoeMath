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

  /// 版本历史（最近若干版）。拉取失败为空列表 —— 附加信息不影响主链路。
  List<AppVersionHistoryEntry> _history = const [];

  /// 「查看全部」展开态：默认只显示最近若干条，避免历史长时淹没主内容。
  bool _historyExpanded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkForUpdates());
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final entries = await widget.updateClient.fetchHistory();
    if (!mounted) return;
    setState(() => _history = entries);
  }

  @override
  void dispose() {
    _downloadCancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 本页不用 AppBar：顶部只放一个「检查更新」标题，占掉整条高度却不
      // 承载交互。改为内容顶格 + 返回按钮浮动左上角（见下方 Positioned）。
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedPageBody(
              // 顶部与首页一致：返回按钮是浮动层、不占流，故顶部只需
              // md —— 与首页「今日待打卡」卡到状态栏的距离相同。
              padding: const EdgeInsets.all(SpacingTokens.lg).copyWith(
                top: SpacingTokens.md,
              ),
              children: [
                _buildStatusCard(context),
                if ((_latest?.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  _buildNotesCard(context),
                ],
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  _buildHistoryCard(context),
                ],
              ],
            ),

            // 返回按钮浮动固定在左上角（原 AppBar 的自动返回）。
            Positioned(
              top: SpacingTokens.xs,
              left: SpacingTokens.xs,
              child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
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
        // 整卡内容水平居中：图标、标题、说明、操作按钮的中轴对齐，
        // 比原先「图标 + 左对齐文字」更聚焦 —— 这个卡片在任意时刻只有
        // 一个状态，居中后视线落点唯一。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(_phaseIcon, color: _phaseColor(theme)),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _phaseTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (_phase == _UpdatePhase.downloading) ...[
            const SizedBox(height: SpacingTokens.md),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              _downloadProgressText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: SpacingTokens.lg),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            alignment: WrapAlignment.center,
            children: _buildActions(),
          ),
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
          // 标题带版本区间（如「更新内容 V0.0.10 → V0.0.11」）。
          //
          // 原先版本号单独占一张「版本信息」卡（当前/最新/包大小/通道），
          // 信息重复且占据首屏。这里只保留最必要的一段：用户在「更新内容」
          // 标题处就能看到从哪个版本变到哪个版本。
          Text(
            _notesTitle,
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

  // ---------- 版本历史卡片 ----------

  /// 折叠态显示的条数；超出时给「查看全部」。
  static const int _historyCollapsedCount = 3;

  Widget _buildHistoryCard(BuildContext context) {
    final theme = Theme.of(context);
    final total = _history.length;
    final collapsed = total > _historyCollapsedCount;
    final shown = !collapsed || _historyExpanded
        ? _history
        : _history.take(_historyCollapsedCount).toList();

    return ColoredCard(
      color: theme.colorScheme.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '版本历史',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          for (final (index, entry) in shown.indexed) ...[
            if (index > 0) const SizedBox(height: SpacingTokens.md),
            _buildHistoryEntry(context, entry),
          ],
          // 收起态另有内容时才给展开入口，避免多一个点了没变化的按钮。
          if (collapsed) ...[
            const SizedBox(height: SpacingTokens.sm),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () =>
                    setState(() => _historyExpanded = !_historyExpanded),
                child: Text(
                  _historyExpanded ? '收起' : '查看全部 $total 个版本',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryEntry(
    BuildContext context,
    AppVersionHistoryEntry entry,
  ) {
    final theme = Theme.of(context);
    final notes = entry.notes.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'V${entry.versionName}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
            // 当前安装的版本标出来，用户能一眼定位「我在哪」。
            if (entry.versionName == _current?.versionName)
              Padding(
                padding: const EdgeInsets.only(right: SpacingTokens.xs),
                child: Text(
                  '当前版本',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text(
            notes,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ] else ...[
          const SizedBox(height: SpacingTokens.xs),
          Text(
            '本版无面向用户的变更。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
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
        _message = friendlyUpdateError(error, fallback: '检查更新失败，请稍后重试。');
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
      final compatibilityError = apkCompatibilityError(
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

      // 签名闸门：ready → installing 的前置新增步骤。既有 SHA256 校验与
      // apkCompatibilityError 的顺序不动，此处只加一道独立信任锚的比对。
      // 原生 installApk 内部会再比对一次（通道可直接调用，故此处不是安全边界）。
      setState(() {
        _phase = _UpdatePhase.installing;
        _message = '正在校验安装包签名。';
      });
      final signatureError = await _verifyApkSignature(file.path, token);
      if (signatureError != null) {
        if (!mounted || token != _requestToken) return;
        setState(() {
          _phase = _UpdatePhase.error;
          _message = signatureError;
        });
        return;
      }
      if (!mounted || token != _requestToken) return;

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
        _message = friendlyUpdateError(error, fallback: '打开安装器失败，请稍后重试。');
      });
    }
  }

  /// 比对已安装应用与待装 APK 的签名指纹；返回 null 表示通过。
  Future<String?> _verifyApkSignature(String path, int token) async {
    try {
      final installed =
          await widget.updateInstaller.getInstalledSignatureSha256();
      if (!mounted || token != _requestToken) return null;
      final incoming = await widget.updateInstaller.inspectApkSignature(path);
      if (!mounted || token != _requestToken) return null;
      return apkSignatureError(
        installed: installed,
        incoming: incoming ?? const <String>[],
      );
    } on UpdateInstallException catch (error) {
      return error.message;
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
        _message = friendlyUpdateError(error, fallback: '无法打开安装权限设置。');
      });
    }
  }

  void _cancelDownload() {
    _downloadCancelToken?.cancel();
  }

  // ---------- 辅助方法 ----------

  /// 更新内容卡标题：带版本区间（如「更新内容 V0.0.10 → V0.0.11」）。
  ///
  /// 任一版本号缺失时退回纯「更新内容」——不显示「V → V」这种半截文案。
  String get _notesTitle {
    final from = _current?.versionName;
    final to = _latest?.versionName;
    if (from == null || from.isEmpty || to == null || to.isEmpty) {
      return '更新内容';
    }
    return '更新内容 V$from → V$to';
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
