import 'package:poemath/core/services/backup_payload_cipher.dart';
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
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/features/profile/widgets/backup_import_flow.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/widgets/backup_passphrase_dialog.dart';
import 'package:poemath/features/profile/widgets/credential_export_failed_dialog.dart';

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
  bool _busy = false;
  Future<List<BackupSnapshot>>? _history;

  @override
  void initState() {
    super.initState();
    _loadPassphraseState();
    _history = ref.read(backupHistoryProvider).list();
  }

  Future<void> _loadPassphraseState() async {
    final passphrase =
        await ref.read(secureCredentialStoreProvider).readBackupPassphrase();
    if (mounted) {
      setState(() => _hasPassphrase = passphrase != null);
    }
  }

  Future<void> _configurePassphrase() async {
    if (_busy) return;
    setState(() => _busy = true);
    final secureStore = ref.read(secureCredentialStoreProvider);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final result = await showBackupPassphraseSetupDialog(
        context,
        hasExisting: _hasPassphrase ?? false,
      );
      if (result == null || !mounted) return;
      ParentAccessService.instance.assertAllowed();
      if (result.isEmpty) {
        await secureStore.deleteBackupPassphrase();
      } else {
        await secureStore.saveBackupPassphrase(result);
      }
      final passphrase = await secureStore.readBackupPassphrase();
      if (!mounted) return;
      setState(() => _hasPassphrase = passphrase != null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty ? '备份加密口令已清除' : '备份加密口令已保存 ✓'),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('口令保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                true => '已设置，整份备份将加密保存',
                false => '未设置，学习和聊天内容以明文导出',
                null => '用于加密学习记录、聊天内容和凭据',
              },
              onTap: _configurePassphrase,
            ),

            const SizedBox(height: SpacingTokens.lg),
            _historySection(context),
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
    if (_busy) return;
    setState(() => _busy = true);
    final backup = ref.read(backupServiceProvider);
    final store = ref.read(secureCredentialStoreProvider);
    final history = ref.read(backupHistoryProvider);
    try {
      if (!await ensureParentAccess(context) || !context.mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '导出备份',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheet).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.md),
                AppTile(
                  icon: Icons.save_alt_rounded,
                  iconColor: Theme.of(sheet).colorScheme.primary,
                  title: '保存到设备',
                  subtitle: '选择本地目录保存备份文件',
                  onTap: () => Navigator.pop(sheet, 'save'),
                ),
                const SizedBox(height: SpacingTokens.sm),
                AppTile(
                  icon: Icons.share_rounded,
                  iconColor: Theme.of(sheet).colorScheme.primary,
                  title: '分享',
                  subtitle: '通过其他应用发送备份文件',
                  onTap: () => Navigator.pop(sheet, 'share'),
                ),
              ],
            ),
          ),
        ),
      );
      if (action == null || !context.mounted) return;
      final passphrase = await store.readBackupPassphrase();
      if (!context.mounted) return;
      final json = await _exportAcceptingCredentialFailure(backup, passphrase);
      if (json == null || !context.mounted) return;
      ParentAccessService.instance.assertAllowed();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      if (action == 'save') {
        final path = await FilePicker.saveFile(
          dialogTitle: '保存备份文件',
          fileName: 'poemath_backup_$timestamp.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(json)),
        );
        if (path == null) return;
        await history.markExternalBackup();
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/poemath_backup_$timestamp.json');
        try {
          await file.writeAsString(json);
          if (!context.mounted) return;
          ParentAccessService.instance.assertAllowed();
          final result = await SharePlus.instance
              .share(ShareParams(files: [XFile(file.path)]));
          if (result.status == ShareResultStatus.success) {
            await history.markExternalBackup();
          }
        } finally {
          if (await file.exists()) await file.delete();
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备份导出完成')));
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 导出 JSON；凭据读取失败时让用户选「仍然导出（不含密钥）」或取消。
  ///
  /// 返回 `null` 表示用户选择取消。重试时跳过凭据读取，
  /// 保留原口令加密整份学习备份。
  Future<String?> _exportAcceptingCredentialFailure(
    BackupService backup,
    String? passphrase,
  ) async {
    try {
      return await backup.exportToJson(
        passphrase: passphrase,
        encryptPayload: passphrase?.trim().isNotEmpty ?? false,
      );
    } on BackupCredentialExportException {
      if (!mounted) return null;
      final proceed = await showCredentialExportFailedDialog(context);
      if (proceed != true) return null;
      return backup.exportToJson(
        passphrase: passphrase,
        encryptPayload: passphrase?.trim().isNotEmpty ?? false,
        includeCredentials: false,
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await ensureParentAccess(context) || !context.mounted) return;
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty || !context.mounted) return;
      final path = result.files.single.path;
      if (path == null) return;
      final json = await readBackupFile(File(path));
      if (!context.mounted) return;
      await _restoreJson(json, source: '备份文件');
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreJson(String json, {required String source}) async {
    final result = await previewAndRestoreBackup(
      context,
      ref,
      json,
      notifications: widget.notificationService,
      source: source,
    );
    if (!mounted) return;
    setState(() => _history = ref.read(backupHistoryProvider).list());
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '恢复成功，共 ${result.count} 条记录${result.notificationsApplied ? '' : '，通知设置未完全应用'}',
          ),
        ),
      );
    }
  }

  Future<void> _restoreSnapshot(BackupSnapshot snapshot) async {
    if (_busy) return;
    setState(() => _busy = true);
    final history = ref.read(backupHistoryProvider);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final json = await history.read(snapshot.id);
      if (mounted) await _restoreJson(json, source: snapshot.label);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('回退失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeHistoryPreference(Future<void> Function() change) async {
    if (_busy) return;
    setState(() => _busy = true);
    final history = ref.read(backupHistoryProvider);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      await change();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置保存失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _history = history.list();
        });
      }
    }
  }

  Widget _historySection(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.read(backupHistoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTile(
          icon: Icons.history,
          iconColor: theme.colorScheme.primary,
          title: '本地保护历史',
          subtitle: '最多保留 10 份，不含安全凭据；卸载应用会丢失',
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      if (!await ensureParentAccess(context) || !mounted) {
                        return;
                      }
                      await history.create();
                    } on Object catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('快照失败：$error')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() {
                          _busy = false;
                          _history = history.list();
                        });
                      }
                    }
                  },
            child: const Text('立即快照'),
          ),
        ),
        AppTile(
          icon: Icons.schedule,
          iconColor: theme.colorScheme.primary,
          title: '每日本地快照',
          subtitle: '开启后，每天启动或回到应用时保存一次',
          trailing: Switch(
            value: history.dailyEnabled,
            onChanged: _busy
                ? null
                : (value) async {
                    await _changeHistoryPreference(() async {
                      await history.setDailyEnabled(value);
                      await history.maybeCreateDaily();
                    });
                  },
          ),
        ),
        AppTile(
          icon: Icons.notification_important_outlined,
          iconColor: theme.colorScheme.primary,
          title: '外部备份提醒',
          subtitle: '超过 7 天未导出或云端备份时在此提醒',
          trailing: Switch(
            value: history.reminderEnabled,
            onChanged: (value) async {
              await _changeHistoryPreference(
                () => history.setReminderEnabled(value),
              );
            },
          ),
        ),
        FutureBuilder<List<BackupSnapshot>>(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('本地历史暂时无法读取，可稍后重试');
            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(SpacingTokens.md),
                child: Text('暂无保护快照'),
              );
            }
            return Column(
              children: [
                for (final entry in entries)
                  AppTile(
                    icon: Icons.restore,
                    iconColor: theme.colorScheme.primary,
                    title: entry.label,
                    subtitle:
                        entry.createdAt.toLocal().toString().split('.').first,
                    onTap: _busy ? null : () => _restoreSnapshot(entry),
                  ),
              ],
            );
          },
        ),
      ],
    );
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
