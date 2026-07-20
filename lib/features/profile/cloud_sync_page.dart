// lib/features/profile/cloud_sync_page.dart
//
// 层级：features/profile
// 职责：云端同步子页面 — 管理 WebDAV 配置，上传/下载备份数据。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/webdav_config_page.dart';

class CloudSyncPage extends ConsumerStatefulWidget {
  const CloudSyncPage({super.key});

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

    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final fullConfig =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      final backup = ref.read(backupServiceProvider);
      final webdav = ref.read(webDavServiceProvider);
      final json = backup.exportToJson();
      await webdav.upload(fullConfig, json);

      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        const SnackBar(content: Text('上传成功 ✓')),
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

    if (confirmed != true) return;

    setState(() => _downloading = true);

    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);

    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final fullConfig =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      final webdav = ref.read(webDavServiceProvider);
      final backup = ref.read(backupServiceProvider);
      final json = await webdav.download(fullConfig);
      final count = await backup.restoreFromJson(json);

      // 刷新所有缓存 Provider，使 UI 立即反映恢复的数据
      invalidateAllHiveProviders(ref.invalidate);

      scaffold.clearSnackBars();
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复成功，共恢复 $count 条记录')),
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
