// lib/features/profile/widgets/llm_endpoint_confirm_dialog.dart
//
// 层级：features/profile/widgets
// 职责：恢复备份前的 LLM 服务地址变更确认框（P1 补偿控制）。
//       备份中的 llm_providers 含 baseUrl，恢复后 AI 请求会发往该地址；
//       若地址与本机不同，必须先让用户知情确认，避免恶意备份把真实
//       API Key 导向攻击者服务器。
//
// 只展示 host（不含完整 URL）：降低无谓的信息暴露，也避免长串撑爆弹框。

import 'package:flutter/material.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 展示服务地址变更并请用户确认。
///
/// 返回约定：`true` = 用户确认继续恢复；`false` / `null` = 取消
/// （调用方须中止恢复，保证数据零变更）。
Future<bool?> showLlmEndpointConfirmDialog(
  BuildContext context,
  LlmEndpointChangeSet changes,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _LlmEndpointConfirmDialog(changes: changes),
  );
}

class _LlmEndpointConfirmDialog extends StatelessWidget {
  const _LlmEndpointConfirmDialog({required this.changes});

  final LlmEndpointChangeSet changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('⚠️ 检测到服务地址变更'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              changes.added.isEmpty
                  ? '该备份包含不同的 AI 服务地址，恢复后请求将发送至新地址：'
                  : '该备份包含以下 AI 服务地址，恢复后请求将发送至这些地址：',
              style: theme.textTheme.bodyMedium,
            ),
            if (changes.added.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _SectionLabel(text: '新增', color: theme.colorScheme.primary),
              const SizedBox(height: SpacingTokens.sm),
              for (final host in changes.added)
                _HostRow(text: host, color: theme.colorScheme.onSurface),
            ],
            if (changes.changed.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _SectionLabel(text: '变更', color: theme.colorScheme.error),
              const SizedBox(height: SpacingTokens.sm),
              for (final change in changes.changed)
                _ChangeRow(change: change, theme: theme),
            ],
            const SizedBox(height: SpacingTokens.lg),
            Text(
              '仅在你信任该备份来源时继续。若地址非你所配置，请取消。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
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
          child: const Text('我信任，继续恢复'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
    );
  }
}

/// 新增项：单行显示 host。
class _HostRow extends StatelessWidget {
  const _HostRow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Text(
        '· $text',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      ),
    );
  }
}

/// 变更项：`配置名：旧 host → 新 host`，新 host 用错误色强调。
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.theme});

  final LlmEndpointChange change;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '· ${change.label}：',
              style: theme.textTheme.bodyMedium,
            ),
            TextSpan(
              text: change.from,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
              ),
            ),
            TextSpan(
              text: ' → ',
              style: theme.textTheme.bodyMedium,
            ),
            TextSpan(
              text: change.to,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
