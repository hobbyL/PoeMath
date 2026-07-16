// lib/features/math/widgets/mistake_repractice_dialog.dart
//
// 错题重练对话框：展示原题、接受输入、判定正误。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

/// 错题重练对话框。
///
/// 返回 `true` 表示答对了，`false` 答错了，`null` 取消。
class MistakeRepracticeDialog extends StatefulWidget {
  const MistakeRepracticeDialog({
    super.key,
    required this.problemText,
    required this.correctAnswer,
  });

  final String problemText;
  final String correctAnswer;

  @override
  State<MistakeRepracticeDialog> createState() =>
      _MistakeRepracticeDialogState();
}

class _MistakeRepracticeDialogState extends State<MistakeRepracticeDialog> {
  final _controller = TextEditingController();
  bool? _isCorrect;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _controller.text.trim();
    if (answer.isEmpty) return;
    setState(() {
      _isCorrect = answer == widget.correctAnswer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('再练一次'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 题目
          Text(
            widget.problemText,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 判定结果
          if (_isCorrect != null) ...[
            ColoredCard(
              color: _isCorrect!
                  ? theme.semantic.success
                  : theme.colorScheme.error,
              backgroundOpacity: 0.15,
              width: double.infinity,
              child: Column(
                children: [
                  Icon(
                    _isCorrect!
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: _isCorrect!
                        ? theme.semantic.success
                        : theme.colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    _isCorrect! ? '回答正确！' : '还是答错了',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _isCorrect!
                          ? theme.semantic.success
                          : theme.colorScheme.error,
                    ),
                  ),
                  if (!_isCorrect!) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      '正确答案：${widget.correctAnswer}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // 输入框
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TypographyTokens.fsTitle,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: '输入答案',
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(SpacingTokens.radiusMedium),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        if (_isCorrect != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_isCorrect),
            child: const Text('关闭'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('确定'),
          ),
        ],
      ],
    );
  }
}
