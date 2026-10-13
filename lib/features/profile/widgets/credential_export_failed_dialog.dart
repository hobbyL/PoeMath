// lib/features/profile/widgets/credential_export_failed_dialog.dart
//
// 层级：features/profile/widgets
// 职责：备份导出口令已填、但安全存储读取失败时的降级选择框。
//
// 背景：`_exportCredentials` 早期把读取失败静默降级为「不含凭据的备份」，
// 用户以为备份完整，换机恢复后才发现 API Key、语音凭据全丢了。现在由本框
// 明确告知失败原因，并让用户自己决定是否接受一份不含密钥的备份。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 询问用户如何处理凭据导出失败。
///
/// 返回约定：`true` = 仍然导出（不含密钥）；`false` / `null` = 取消导出。
Future<bool?> showCredentialExportFailedDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _CredentialExportFailedDialog(),
  );
}

class _CredentialExportFailedDialog extends StatelessWidget {
  const _CredentialExportFailedDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('密钥读取失败'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '无法从系统的安全存储中读取 API Key 等凭据，'
              '常见原因是系统密钥库被重置、应用数据被清理，'
              '或当前设备不支持安全存储。',
            ),
            const SizedBox(height: SpacingTokens.md),
            Text(
              '仍然导出的话，这份备份不包含任何密钥；'
              '在新设备恢复后需要重新填写。其他学习数据不受影响。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('仍然导出（不含密钥）'),
        ),
      ],
    );
  }
}
