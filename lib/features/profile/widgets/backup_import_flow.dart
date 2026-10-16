import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/restore_coordinator.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/providers/backup_protection_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/widgets/backup_passphrase_dialog.dart';
import 'package:poemath/features/profile/widgets/llm_endpoint_confirm_dialog.dart';

/// 只读校验/预览阶段结束前不写入任何学习数据或历史快照。
Future<RestoreResult?> previewAndRestoreBackup(
    BuildContext context, WidgetRef ref, String json,
    {NotificationService? notifications, String source = '备份文件',}) async {
  final backup = ref.read(backupServiceProvider);
  final coordinator = ref.read(restoreCoordinatorProvider(notifications));
  final preview = backup.inspectJson(json);
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
            title: const Text('备份预览'),
            content: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialog).height * .65,),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('来源：$source'),
                      Text(
                          '备份日期：${preview.exportedAt?.toLocal().toString().split('.').first ?? '旧备份未记录'}',),
                      const SizedBox(height: SpacingTokens.sm),
                      for (final entry in preview.counts.entries)
                        Text('${entry.key}：${entry.value}'),
                      const SizedBox(height: SpacingTokens.sm),
                      Text(preview.hasCredentials
                          ? '包含独立加密凭据，可输入口令恢复或留空跳过。'
                          : '不含安全凭据。',),
                      if (preview.endpointChanges case final changes?) ...[
                        Text(changes.isEmpty
                            ? '服务地址：无新增或变更'
                            : '服务地址变更（下一步需再次确认）：',),
                        for (final host in changes.added) Text('新增：$host'),
                        for (final change in changes.changed)
                          Text('${change.label}：${change.from} → ${change.to}'),
                        for (final host in changes.removed) Text('移除：$host'),
                      ],
                      const SizedBox(height: SpacingTokens.md),
                      const Text('确认后将先保存不含凭据的本地保护快照，再覆盖学习数据。旧备份未包含的助手聊天会保留。'),
                    ],),),),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('取消'),),
              FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('确认覆盖'),),
            ],
          ),);
  if (confirmed != true || !context.mounted) return null;
  if (!await ensureParentAccess(context) || !context.mounted) return null;
  String? passphrase;
  if (preview.hasCredentials) {
    passphrase = await showBackupPassphraseInputDialog(context);
    if (passphrase == null || !context.mounted) return null;
  }
  final changes = preview.endpointChanges;
  if (changes != null && !changes.isEmpty) {
    final trusted = await showLlmEndpointConfirmDialog(context, changes);
    if (trusted != true || !context.mounted) return null;
  }
  return coordinator.restore(preview, passphrase: passphrase);
}
