// lib/features/profile/cloud_sync_page.dart
//
// 层级：features/profile
// 职责：云端同步子页面 — 管理 WebDAV 配置，上传/下载备份数据。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/webdav_config_page.dart';
import 'package:poemath/features/profile/widgets/backup_passphrase_dialog.dart';
import 'package:poemath/features/profile/widgets/credential_export_failed_dialog.dart';
import 'package:poemath/features/profile/widgets/llm_endpoint_confirm_dialog.dart';
import 'package:poemath/features/profile/widgets/sync_conflict_dialog.dart';

class CloudSyncPage extends ConsumerStatefulWidget {
  const CloudSyncPage({
    super.key,
    this.notificationService,
  });

  final NotificationService? notificationService;

  @override
  ConsumerState<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends ConsumerState<CloudSyncPage> {
  String? _selectedId;
  bool _uploading = false;
  bool _downloading = false;

  Future<void> _addConfig() async {
    final result = await Navigator.push<bool>(
      context,
      fadeSlideRoute(builder: (_) => const WebDavConfigPage()),
    );
    if (result == true) {
      ref.invalidate(settingsRepositoryProvider);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editConfig(WebDavConfig config) async {
    // 从安全存储加载凭据，以便编辑页预填充
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final fullConfig =
        await settingsRepo.loadWebDavConfigWithCredentials(config);

    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      fadeSlideRoute(
        builder: (_) => WebDavConfigPage(existing: fullConfig),
      ),
    );
    if (result == true) {
      ref.invalidate(settingsRepositoryProvider);
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteConfig(WebDavConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除「${config.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.deleteWebDavConfig(config.id);
    ref.invalidate(settingsRepositoryProvider);
    if (_selectedId == config.id) {
      _selectedId = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _upload() async {
    final config = _getSelectedConfig();
    if (config == null) return;

    setState(() => _uploading = true);
    final scaffold = ScaffoldMessenger.of(context);

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final backup = ref.read(backupServiceProvider);
    final webdav = ref.read(webDavServiceProvider);

    try {
      final fullConfig =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      final passphrase =
          await ref.read(secureCredentialStoreProvider).readBackupPassphrase();
      final json = await backup.exportToJson(passphrase: passphrase);

      // 冲突检测（上传方向）：本机导出时刻晚于本机上次同步 → 云端也在本机
      // 上次同步之后被其他设备写过。先拉一份云端读它的 exportedAt，两种
      // 情况都要拦：云端更新（本机覆盖会让对方数据消失）与云端也更旧但
      // 不可比对（老备份无 exportedAt，只能按「无从判断」处理，不拦）。
      final conflict = await _detectUploadConflict(webdav, fullConfig, json);
      if (conflict == SyncConflictDecision.cancelled) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('已取消上传（云端备份未变更）')),
        );
        return;
      }

      await webdav.upload(fullConfig, json);
      // 上传成功才推进时间线：失败时留旧值，下次仍会正确判定冲突。
      await settingsRepo.setLastSyncedAt(_exportedAtOf(json) ?? DateTime.now());

      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            passphrase == null ? '上传成功 ✓（未设置备份加密口令，本次备份不含凭据）' : '上传成功 ✓',
          ),
        ),
      );
    } on BackupCredentialExportException {
      // 口令已设但密钥读不出来：不能静默上传一份缺密钥的备份，
      // 让用户先决定是否接受。
      if (!mounted) return;
      final proceed = await showCredentialExportFailedDialog(context);
      if (proceed != true) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('已取消上传（未修改云端备份）')),
        );
        return;
      }
      // 无口令重导：跳过凭据读取，得到一份不含密钥但其余数据完整的备份。
      final json = await backup.exportToJson();
      final fullConfig =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      await webdav.upload(fullConfig, json);
      await settingsRepo.setLastSyncedAt(_exportedAtOf(json) ?? DateTime.now());
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        const SnackBar(content: Text('上传成功 ✓（不含密钥）')),
      );
    } on WebDavException catch (e) {
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('上传失败: ${e.message}')),
      );
    } on Exception catch (e) {
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('上传失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download() async {
    final config = _getSelectedConfig();
    if (config == null) return;

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端下载'),
        content: const Text(
          '下载将覆盖当前所有学习数据，此操作不可撤销。\n\n确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认下载'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _downloading = true);
    final scaffold = ScaffoldMessenger.of(context);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final webdav = ref.read(webDavServiceProvider);
    final backup = ref.read(backupServiceProvider);
    final notifications =
        widget.notificationService ?? NotificationService.instance;

    try {
      final fullConfig =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      final json = await webdav.download(fullConfig);

      // 备份含加密凭据时先收口令；留空跳过凭据恢复。
      final hasCredentials = BackupService.jsonHasCredentials(json);
      String? passphrase;
      if (hasCredentials) {
        if (!mounted) return;
        passphrase = await showBackupPassphraseInputDialog(context);
        if (passphrase == null) return; // 用户取消
      }

      // 端点变更预检：LLM 配置随备份迁移（含 baseUrl），恢复前让用户确认
      // 地址变更，避免恶意备份把真实 API Key 导向攻击者服务器（P1 闸门）。
      final endpointChanges = BackupService.detectLlmEndpointChanges(json);
      if (endpointChanges != null && !endpointChanges.isEmpty) {
        if (!mounted) return;
        final trusted =
            await showLlmEndpointConfirmDialog(context, endpointChanges);
        if (trusted != true) return; // 用户取消 = 中止恢复，数据零变更
      }

      // 冲突检测（下载方向）：云端 exportedAt 晚于本机上次同步 → 另一台
      // 设备在本机之后写过云端，本机那边没有这些新数据，恢复前必须知情。
      final lastSyncedAt = settingsRepo.lastSyncedAt;
      final remoteExportedAt = BackupService.exportedAt(json);
      if (lastSyncedAt != null &&
          remoteExportedAt != null &&
          remoteExportedAt.isAfter(lastSyncedAt)) {
        if (!mounted) return;
        final proceed = await showSyncConflictDialog(
          context,
          direction: SyncConflictDirection.download,
          remoteExportedAt: remoteExportedAt,
          localSyncedAt: lastSyncedAt,
        );
        if (proceed != true) return; // 用户取消 = 中止恢复，数据零变更
      }

      final count = await backup.restoreFromJson(json, passphrase: passphrase);
      final notificationsApplied =
          await notifications.reconcileWithStoredSettings();
      if (!mounted) return;

      // 恢复成功才推进时间线，与上传方向对称。
      if (remoteExportedAt != null) {
        await settingsRepo.setLastSyncedAt(remoteExportedAt);
      }

      // 刷新所有缓存 Provider，使 UI 立即反映恢复的数据
      invalidateAllHiveProviders(ref.invalidate);

      final credentialMessage = !hasCredentials
          ? ''
          : passphrase!.isNotEmpty
              ? '，凭据已恢复'
              : '，凭据未恢复（未输入口令）';
      final notificationMessage = notificationsApplied ? '' : '，但通知设置未完全应用';
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            '恢复成功，共恢复 $count 条记录$credentialMessage$notificationMessage',
          ),
        ),
      );
    } on WebDavException catch (e) {
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('下载失败: ${e.message}')),
      );
    } on FormatException catch (e) {
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: ${e.message}')),
      );
    } on BackupRestoreException catch (e) {
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: ${e.message}')),
      );
    } on Exception catch (e) {
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('下载失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  WebDavConfig? _getSelectedConfig() {
    if (_selectedId == null) return null;
    final configs = ref.read(settingsRepositoryProvider).webDavConfigs;
    try {
      return configs.firstWhere((c) => c.id == _selectedId);
    } on StateError {
      return null;
    }
  }

  /// 本次导出 JSON 的 `exportedAt`；解析不出来时调用方退化为「现在」。
  DateTime? _exportedAtOf(String json) => BackupService.exportedAt(json);

  /// 上传前冲突判定。
  ///
  /// 返回 [SyncConflictDecision.proceed] 表示可以直接上传，
  /// [SyncConflictDecision.cancelled] 表示用户取消（调用方须中止）。
  ///
  /// 判定依据：本机导出的 `exportedAt` 与**本机记录的 `lastSyncedAt`** 比。
  /// 云端备份只在本机上次同步之后被改过，才可能在本机之后被别的设备写过
  /// （`lastSyncedAt` 之后云端若有写入，必定来自其他设备）。
  ///
  /// 为拿到云端那一侧的时间线，需要先下载一次云端备份 —— 这是本功能的
  /// 已知代价（比对必须有对方的 `exportedAt`），仅比对不恢复，数据零变更。
  ///
  /// 读取失败（首次配置、云端还没有备份、网络异常）一律**放行**：冲突检测
  /// 是防误覆盖的辅助闸门，不能反过来阻断正常上传；真正的上传失败会由
  /// 调用方已有的 `WebDavException` 分支给出明确提示。
  Future<SyncConflictDecision> _detectUploadConflict(
    WebDavService webdav,
    WebDavConfig fullConfig,
    String localJson,
  ) async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final lastSyncedAt = settingsRepo.lastSyncedAt;
    if (lastSyncedAt == null) return SyncConflictDecision.proceed;

    final String remoteJson;
    try {
      remoteJson = await webdav.download(fullConfig);
    } on Object catch (error) {
      AppLogger.w(
        '上传前冲突检测跳过：云端备份不可读（$error）',
        tag: 'CloudSync',
      );
      return SyncConflictDecision.proceed;
    }

    final remoteExportedAt = BackupService.exportedAt(remoteJson);
    final localExportedAt = _exportedAtOf(localJson);
    if (remoteExportedAt == null || localExportedAt == null) {
      return SyncConflictDecision.proceed;
    }

    // 云端在本机上次同步之后被写过，且本机这次导出的内容也晚于上次同步
    // —— 双方各自有新进展，属真冲突。
    final remoteMoved = remoteExportedAt.isAfter(lastSyncedAt);
    final localMoved = localExportedAt.isAfter(lastSyncedAt);
    if (!remoteMoved || !localMoved) return SyncConflictDecision.proceed;

    if (!mounted) return SyncConflictDecision.cancelled;
    final proceed = await showSyncConflictDialog(
      context,
      direction: SyncConflictDirection.upload,
      remoteExportedAt: remoteExportedAt,
      localSyncedAt: lastSyncedAt,
    );
    return proceed == true
        ? SyncConflictDecision.proceed
        : SyncConflictDecision.cancelled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final configs = settingsRepo.webDavConfigs;
    final busy = _uploading || _downloading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端同步'),
        actions: [
          IconButton(
            onPressed: _addConfig,
            icon: const Icon(Icons.add),
            tooltip: '添加配置',
          ),
        ],
      ),
      body: SafeArea(
        child: configs.isEmpty
            ? _buildEmptyState(theme)
            : Column(
                children: [
                  // 配置列表
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      itemCount: configs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: SpacingTokens.sm),
                      itemBuilder: (context, index) {
                        final config = configs[index];
                        final selected = _selectedId == config.id;

                        return ColoredCard(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          backgroundOpacity: selected ? 0.12 : 0.04,
                          onTap: () => setState(() => _selectedId = config.id),
                          child: Row(
                            children: [
                              // 选中标记
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                              const SizedBox(width: SpacingTokens.md),
                              // 配置信息
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      config.name,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: SpacingTokens.xs,
                                    ),
                                    Text(
                                      config.url,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // 操作按钮
                              PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _editConfig(config);
                                  } else if (action == 'delete') {
                                    _deleteConfig(config);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(
                              delay: (80 * index).ms,
                              duration: 300.ms,
                            )
                            .slideX(
                              begin: 0.1,
                              end: 0,
                              delay: (80 * index).ms,
                              duration: 300.ms,
                            );
                      },
                    ),
                  ),

                  // 底部操作按钮（选中配置后显示）
                  if (_selectedId != null)
                    Container(
                      padding: const EdgeInsets.all(SpacingTokens.lg),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : _upload,
                              icon: _uploading
                                  ? const _SmallSpinner()
                                  : const Icon(Icons.cloud_upload_outlined),
                              label: Text(
                                _uploading ? '上传中…' : '上传到云端',
                              ),
                            ),
                          ),
                          const SizedBox(width: SpacingTokens.md),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy ? null : _download,
                              icon: _downloading
                                  ? const _SmallSpinner(light: true)
                                  : const Icon(
                                      Icons.cloud_download_outlined,
                                    ),
                              label: Text(
                                _downloading ? '下载中…' : '从云端下载',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: SpacingTokens.md),
            Text(
              '暂无同步方式',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              '点击右上角 + 添加 WebDAV 配置',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            FilledButton.icon(
              onPressed: _addConfig,
              icon: const Icon(Icons.add),
              label: const Text('添加配置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner({this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: light ? Colors.white : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// 上传前冲突检测的三态结论。
///
/// 独立成枚举而非 `bool?`：三态（继续 / 取消）语义与「无冲突」重合时，
/// `null` 与 `false` 极易混用，而两者后果完全不同（放行 vs 中止上传）。
enum SyncConflictDecision {
  /// 无冲突或无法判定 —— 继续上传。
  proceed,

  /// 检出冲突且用户选择取消 —— 调用方必须中止上传，云端零变更。
  cancelled,
}
