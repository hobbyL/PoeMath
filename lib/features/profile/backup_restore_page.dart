// lib/features/profile/backup_restore_page.dart
//
// 层级：features/profile
// 职责：备份与恢复子页面 — 导出备份文件或从备份恢复数据。
//       备份加密口令的设置入口；凭据以口令加密随备份携带。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/widgets/backup_passphrase_dialog.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({
    super.key,
    this.notificationService,
  });

  final NotificationService? notificationService;

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  /// 备份加密口令是否已设置；`null` 表示尚未从安全存储加载完成。
  bool? _hasPassphrase;

  @override
  void initState() {
    super.initState();
    _loadPassphraseState();
  }

  Future<void> _loadPassphraseState() async {
    final passphrase =
        await ref.read(secureCredentialStoreProvider).readBackupPassphrase();
    if (mounted) {
      setState(() => _hasPassphrase = passphrase != null);
    }
  }

  Future<void> _configurePassphrase() async {
    final hasExisting = _hasPassphrase ?? false;
    final result = await showBackupPassphraseSetupDialog(
      context,
      hasExisting: hasExisting,
    );
    if (result == null) return;

    final secureStore = ref.read(secureCredentialStoreProvider);
    if (result.isEmpty) {
      await secureStore.deleteBackupPassphrase();
    } else {
      await secureStore.saveBackupPassphrase(result);
    }
    await _loadPassphraseState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.isEmpty ? '备份加密口令已清除' : '备份加密口令已保存 ✓'),
      ),
    );
  }

  Future<String?> _readExportPassphrase() {
    return ref.read(secureCredentialStoreProvider).readBackupPassphrase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
            Text(
              '数据安全',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              '定期备份学习数据，防止意外丢失',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 两个并排卡片
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.upload_file_rounded,
                    title: '导出备份',
                    subtitle: '保存或分享备份',
                    color: theme.colorScheme.primary,
                    onTap: () => _exportBackup(context, ref),
                  ),
                ),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.download_rounded,
                    title: '从备份恢复',
                    subtitle: '选择备份文件',
                    color: theme.colorScheme.secondary,
                    onTap: () => _importBackup(context, ref),
                  ),
                ),
              ],
            ),

            const SizedBox(height: SpacingTokens.lg),
            // 备份加密口令
            AppTile(
              icon: Icons.password_rounded,
              iconColor: theme.colorScheme.primary,
              title: '备份加密口令',
              subtitle: switch (_hasPassphrase) {
                true => '已设置，凭据将加密随备份携带',
                false => '未设置，备份不包含凭据',
                null => '用于加密备份中的腾讯云 AK/SK 与 TTS Key',
              },
              onTap: _configurePassphrase,
            ),

            const SizedBox(height: SpacingTokens.lg),
            // 提示信息
            ColoredCard(
              color: theme.semantic.caution,
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: theme.semantic.caution,
                    size: 20,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: Text(
                      '备份包含所有学习进度、打卡记录和设置。'
                      '诗词、公式等静态数据由应用内置，不参与备份。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final scaffold = ScaffoldMessenger.of(context);

    // 弹出底部选择：保存到设备 or 分享
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('保存到设备'),
              subtitle: const Text('选择本地目录保存备份文件'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('分享'),
              subtitle: const Text('通过其他应用发送备份文件'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    try {
      final backup = ref.read(backupServiceProvider);
      final passphrase = await _readExportPassphrase();

      if (action == 'save') {
        final json = await backup.exportToJson(passphrase: passphrase);
        final timestamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
        final path = await FilePicker.saveFile(
          dialogTitle: '保存备份文件',
          fileName: 'poemath_backup_$timestamp.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(json)),
        );
        if (path == null) return; // 用户取消
        scaffold.showSnackBar(
          SnackBar(
            content: Text(
              passphrase == null ? '备份已保存 ✓（未设置口令，不含凭据）' : '备份已保存 ✓',
            ),
          ),
        );
      } else {
        final filePath = await backup.exportToFile(passphrase: passphrase);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(filePath)]),
        );
      }
    } on Exception catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('备份失败: $e')),
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final scaffold = ScaffoldMessenger.of(context);
    final notifications =
        widget.notificationService ?? NotificationService.instance;

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据恢复'),
        content: const Text(
          '恢复将覆盖当前所有学习数据，此操作不可撤销。\n\n确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final backup = ref.read(backupServiceProvider);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      // 备份含加密凭据时先收口令；留空跳过凭据恢复。
      final fileJson = await File(filePath).readAsString();
      final hasCredentials = BackupService.jsonHasCredentials(fileJson);
      String? passphrase;
      if (hasCredentials) {
        if (!context.mounted) return;
        passphrase = await showBackupPassphraseInputDialog(context);
        if (passphrase == null) return; // 用户取消
      }

      final count = await backup.restoreFromFile(filePath, passphrase: passphrase);
      final notificationsApplied =
          await notifications.reconcileWithStoredSettings();
      if (!context.mounted) return;

      // 刷新所有缓存 Provider，使 UI 立即反映恢复的数据
      invalidateAllHiveProviders(ref.invalidate);

      final credentialMessage = !hasCredentials
          ? ''
          : passphrase!.isNotEmpty
              ? '，凭据已恢复'
              : '，凭据未恢复（未输入口令）';
      final notificationMessage = notificationsApplied ? '' : '，但通知设置未完全应用';
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            '恢复成功，共恢复 $count 条记录$credentialMessage$notificationMessage',
          ),
        ),
      );
    } on FormatException catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: ${e.message}')),
      );
    } on BackupRestoreException catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: ${e.message}')),
      );
    } on Exception catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredCard(
      color: color,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
