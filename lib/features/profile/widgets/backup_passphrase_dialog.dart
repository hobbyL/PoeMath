// lib/features/profile/widgets/backup_passphrase_dialog.dart
//
// 层级：features/profile/widgets
// 职责：备份加密口令的输入（恢复/下载用）与设置（两遍确认）对话框。
// 口令本身只经手安全存储，对话框不做任何持久化。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 恢复备份时的口令输入对话框（可留空跳过凭据）。
///
/// 返回约定：`null` = 用户取消；`''` = 留空跳过凭据恢复；非空 = 口令。
Future<String?> showBackupPassphraseInputDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PassphraseInputDialog(),
  );
}

/// 设置 / 修改 / 清除备份加密口令。
///
/// 返回约定：`null` = 用户取消；`''` = 清除口令；非空 = 新口令。
/// [hasExisting] 为 `true` 时提供「清除口令」入口。
Future<String?> showBackupPassphraseSetupDialog(
  BuildContext context, {
  required bool hasExisting,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PassphraseSetupDialog(hasExisting: hasExisting),
  );
}

class _PassphraseInputDialog extends StatefulWidget {
  const _PassphraseInputDialog();

  @override
  State<_PassphraseInputDialog> createState() => _PassphraseInputDialogState();
}

class _PassphraseInputDialogState extends State<_PassphraseInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入备份加密口令'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '备份加密口令',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '该备份包含加密的凭据\n'
              '（腾讯云 AK/SK、TTS API Key、LLM API Key）。\n'
              'TTS/大模型服务地址等配置不随备份同步，'
              '新设备需重新填写。\n'
              '留空将跳过凭据恢复，其余数据正常恢复。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('恢复'),
        ),
      ],
    );
  }
}

class _PassphraseSetupDialog extends StatefulWidget {
  const _PassphraseSetupDialog({required this.hasExisting});

  final bool hasExisting;

  @override
  State<_PassphraseSetupDialog> createState() => _PassphraseSetupDialogState();
}

class _PassphraseSetupDialogState extends State<_PassphraseSetupDialog> {
  final _firstController = TextEditingController();
  final _secondController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _firstController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  void _submit() {
    final first = _firstController.text;
    final second = _secondController.text;
    if (first.isEmpty) {
      setState(() => _errorText = '口令不能为空（如需清除请点「清除口令」）');
      return;
    }
    if (first != second) {
      setState(() => _errorText = '两次输入不一致');
      return;
    }
    Navigator.pop(context, first);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除口令'),
        content: const Text('清除后导出的备份将不再包含凭据，确定继续吗？'),
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
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context, '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.hasExisting ? '修改备份加密口令' : '设置备份加密口令'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _firstController,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '口令',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            TextField(
              controller: _secondController,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '再次输入确认',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '口令用于加密备份中的腾讯云 AK/SK、'
              'TTS API Key 与 LLM API Key。\n'
              'TTS/大模型服务地址等配置不随备份同步，'
              '新设备需重新填写。\n'
              '忘记口令 = 凭据无法恢复，重新填写即可。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hasExisting)
          TextButton(
            onPressed: _confirmClear,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除口令'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
