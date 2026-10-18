// lib/features/profile/cloud_sync_page.dart
//
// 层级：features/profile
// 职责：云端同步子页面 — 管理 WebDAV 配置，上传/下载备份数据。

import 'package:flutter/material.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/features/profile/widgets/backup_import_flow.dart';
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/webdav_config_page.dart';
import 'package:poemath/features/profile/widgets/credential_export_failed_dialog.dart';
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
      fadeSlideRoute(
        builder: (_) => const ParentAccessBoundary(child: WebDavConfigPage()),
      ),
    );
    if (result == true && mounted) {
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
        builder: (_) =>
            ParentAccessBoundary(child: WebDavConfigPage(existing: fullConfig)),
      ),
    );
    if (result == true && mounted) {
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

    if (confirmed != true || !mounted) return;

    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.deleteWebDavConfig(config.id);
    ref.invalidate(settingsRepositoryProvider);
    if (_selectedId == config.id) {
      _selectedId = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _upload() async {
    if (_uploading || _downloading) return;
    final config = _getSelectedConfig();
    if (config == null) return;

    setState(() => _uploading = true);
    final scaffold = ScaffoldMessenger.of(context);

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final backup = ref.read(backupServiceProvider);
    final webdav = ref.read(webDavServiceProvider);
    final history = ref.read(backupHistoryProvider);
    final credentialStore = ref.read(secureCredentialStoreProvider);

    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final fullConfig =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      final passphrase = await credentialStore.readBackupPassphrase();
      var degraded = false;
      String json;
      try {
        json = await backup.exportToJson(passphrase: passphrase);
      } on BackupCredentialExportException {
        if (!mounted) return;
        final proceed = await showCredentialExportFailedDialog(context);
        if (proceed != true) {
          scaffold
              .showSnackBar(const SnackBar(content: Text('已取消上传（未修改云端备份）')));
          return;
        }
        json = await backup.exportToJson();
        degraded = true;
      }

      // 冲突检测（上传方向）：本机导出时刻晚于本机上次同步 → 云端也在本机
      // 上次同步之后被其他设备写过。先拉一份云端读它的 exportedAt，两种
      // 情况都要拦：云端更新（本机覆盖会让对方数据消失）与云端也更旧但
      // 不可比对（老备份无 exportedAt，只能按「无从判断」处理，不拦）。
      final conflict = await _detectUploadConflict(webdav, fullConfig);
      if (conflict == SyncConflictDecision.cancelled) {
        if (!mounted) return;
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('已取消上传（云端备份未变更）')),
        );
        return;
      }

      if (!mounted || !await ensureParentAccess(context)) return;
      await webdav.upload(fullConfig, json);
      // 上传成功才推进时间线：失败时留旧值，下次仍会正确判定冲突。
      await settingsRepo.setLastSyncedAt(_exportedAtOf(json) ?? DateTime.now());
      try {
        await history.markExternalBackup();
      } on Object catch (error) {
        AppLogger.e('云端备份成功，提醒日期保存失败', tag: 'Backup', error: error);
      }
      if (!mounted) return;
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            degraded
                ? '上传成功 ✓（不含密钥）'
                : passphrase == null
                    ? '上传成功 ✓（未设置备份加密口令，本次备份不含凭据）'
                    : '上传成功 ✓',
          ),
        ),
      );
    } on WebDavException catch (e) {
      if (!mounted) return;
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('上传失败: ${e.message}')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      // `on Object` 兜在具体类型之后：`settingsRepo.setLastSyncedAt` 写
      // `HiveBoxes`，失败抛 `HiveError extends Error`，`on Exception` 接不住。
      // 有 `finally` 复位 `_uploading` 不会卡死，但漏捕会让上传按钮点了
      // 既无成功也无失败反馈（异常直抛框架）。
      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('上传失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download({String? versionId}) async {
    if (_uploading || _downloading) return;
    final config = _getSelectedConfig();
    if (config == null) return;
    setState(() => _downloading = true);
    final settings = ref.read(settingsRepositoryProvider);
    final webdav = ref.read(webDavServiceProvider);
    final history = ref.read(backupHistoryProvider);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final full = await settings.loadWebDavConfigWithCredentials(config);
      final json = versionId == null
          ? await webdav.download(full)
          : await webdav.downloadVersion(full, versionId);
      if (!mounted) return;
      final remote = BackupService.exportedAt(json);
      final local = settings.lastSyncedAt;
      if (versionId == null &&
          remote != null &&
          local != null &&
          remote.isAfter(local)) {
        final proceed = await showSyncConflictDialog(
          context,
          direction: SyncConflictDirection.download,
          remoteExportedAt: remote,
          localSyncedAt: local,
        );
        if (proceed != true || !mounted) return;
      }
      final result = await previewAndRestoreBackup(
        context,
        ref,
        json,
        notifications: widget.notificationService,
        source: versionId == null ? 'WebDAV 最新备份' : 'WebDAV 历史版本',
      );
      if (result == null) return;
      if (remote != null) await settings.setLastSyncedAt(remote);
      try {
        await history.markExternalBackup();
      } on Object catch (error) {
        AppLogger.e('恢复成功，提醒日期保存失败', tag: 'Backup', error: error);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '恢复成功，共 ${result.count} 条记录${result.notificationsApplied ? '' : '，通知设置未完全应用'}',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载或恢复失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _versions() async {
    if (_uploading || _downloading) return;
    final config = _getSelectedConfig();
    if (config == null) return;
    setState(() => _downloading = true);
    final settings = ref.read(settingsRepositoryProvider);
    final webdav = ref.read(webDavServiceProvider);
    String? selected;
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final full = await settings.loadWebDavConfigWithCredentials(config);
      final versions = await webdav.listVersions(full);
      if (!mounted) return;
      selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .6,
            child: versions.isEmpty
                ? const Center(child: Text('暂无历史版本，请先上传一次新备份'))
                : ListView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: [
                      Text(
                        '选择云端历史版本',
                        style: Theme.of(sheet).textTheme.titleMedium,
                      ),
                      for (final version in versions)
                        AppTile(
                          icon: Icons.history,
                          iconColor: Theme.of(sheet).colorScheme.primary,
                          title: version.createdAt
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                          subtitle: '下载后预览确认，不会立即覆盖',
                          onTap: () => Navigator.pop(sheet, version.id),
                        ),
                    ],
                  ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('读取历史失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
    if (selected != null && mounted) await _download(versionId: selected);
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
  /// 判定依据：**云端**备份的顶层 `exportedAt` 与本机记录的 `lastSyncedAt`
  /// 比较。`lastSyncedAt` 之后云端若有写入，必定来自其他设备（本机没有在
  /// 那之后同步过），本机此刻上传会覆盖掉那些数据。
  ///
  /// 不叠加「本机是否有新改动」：备份的 `exportedAt` 记的是导出时刻而非数据
  /// 变更时刻，拿它判断本机改动恒为真，属于伪条件。详见方法体内的说明。
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

    // 云端时间线无法判定（老版本备份没有 exportedAt、或被别的内容顶掉）：
    // 不据此判定冲突，避免换机首次恢复/上传被无谓拦截。
    final remoteExportedAt = BackupService.exportedAt(remoteJson);
    if (remoteExportedAt == null) {
      return SyncConflictDecision.proceed;
    }

    // 云端在本机上次同步之后被别的设备写过 —— 本机那边没有这些新数据，
    // 上传会把它覆盖掉，用户必须知情。
    //
    // 这里**只**看云端是否推进，不叠加本机侧条件。原因：备份顶层的
    // `exportedAt` 是「导出动作发生的时刻」（`BackupService.exportToJson`
    // 写的是 `DateTime.now()`），不是「数据最后变更时刻」。因此
    // `localExportedAt.isAfter(lastSyncedAt)` 对本机本次导出恒为真，拿它
    // 当「本机也有新进展」的证据是伪条件 —— 会让提示伪装成双向冲突，却
    // 过滤不掉任何情况。真正的「本机是否有改动」需要另设数据变更时间戳，
    // 当前设计不提供，故不做该判断。
    if (!remoteExportedAt.isAfter(lastSyncedAt)) {
      return SyncConflictDecision.proceed;
    }

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
    final detailed = settingsRepo.webDavConfigsDetailed;
    final configs = detailed.configs;
    final skipped = detailed.skipped;
    final busy = _uploading || _downloading;

    return Scaffold(
      floatingActionButton: _selectedId == null
          ? null
          : FloatingActionButton.small(
              tooltip: '云端历史版本',
              onPressed: busy ? null : _versions,
              child: const Icon(Icons.history),
            ),
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
        child: Column(
          children: [
            // 有配置因校验不合法被跳过时提示一次（见 decodeListDetailed）。
            // 整串 JSON 损坏属于存储项损坏而非「有 N 条不合法」，skipped 记 0，
            // 此处自然不提示，按空列表处理即可。
            if (skipped > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.md,
                  SpacingTokens.md,
                  SpacingTokens.md,
                  0,
                ),
                child: ColoredCard(
                  color: theme.semantic.caution,
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: theme.semantic.caution,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Text(
                          '有 $skipped 条配置因不合法被忽略',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
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
                                onTap: () =>
                                    setState(() => _selectedId = config.id),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            config.name,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(
                                            height: SpacingTokens.xs,
                                          ),
                                          Text(
                                            config.url,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
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
                                        : const Icon(
                                            Icons.cloud_upload_outlined,),
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
        // 中性白属语义明确用法：`light = true` 表示本指示器置于主色
        // （primary）实底之上，需要用与底恒定对比的白，而非随主题派生的
        // 令牌色。另一分支已显式用 primary，此处与之对称。
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
