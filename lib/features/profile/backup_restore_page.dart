// lib/features/profile/backup_restore_page.dart
//
// 层级：features/profile
// 职责：备份与恢复子页面 — 导出备份文件或从备份恢复数据。

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

class BackupRestorePage extends ConsumerWidget {
  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              // 提示信息
              ColoredCard(
                color: ColorTokens.poemGold,
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: ColorTokens.poemGold,
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

      if (action == 'save') {
        final json = backup.exportToJson();
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
          const SnackBar(content: Text('备份已保存 ✓')),
        );
      } else {
        final filePath = await backup.exportToFile();
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

    if (confirmed != true) return;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final backup = ref.read(backupServiceProvider);
      final count = await backup.restoreFromFile(filePath);

      // 刷新所有缓存 Provider，使 UI 立即反映恢复的数据
      invalidateAllHiveProviders(ref.invalidate);
      ref.invalidate(settingsRepositoryProvider);

      scaffold.showSnackBar(
        SnackBar(content: Text('恢复成功，共恢复 $count 条记录')),
      );
    } on FormatException catch (e) {
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
