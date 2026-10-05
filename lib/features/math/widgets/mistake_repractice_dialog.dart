// lib/features/math/widgets/mistake_repractice_dialog.dart
//
// 错题重练对话框：展示原题、接受输入、判定正误。
// 使用 NumberKeypad 输入，特殊键按正确答案形态自适应
// （余数 … / 分数 / / 负号 - / 小数 .），保证余数、分数、负数、
// 小数答案均可通过键盘键入。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';

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
  String _answer = '';
  bool? _isCorrect;

  // ============ 特殊键自适应（correctAnswer 是错题入库时的答案快照） ============

  bool get _showEllipsis => widget.correctAnswer.contains('…');

  bool get _showSlash => widget.correctAnswer.contains('/');

  /// 小数点仅在非余数、非分数形态下出现（'…' 与 '/' 互斥优先）
  bool get _showDecimal =>
      !_showEllipsis && !_showSlash && widget.correctAnswer.contains('.');

  /// 负号：负整数与负分数（如 -5/6）均以 '-' 开头
  bool get _showNegative => widget.correctAnswer.startsWith('-');

  void _onNumberTap(String key) {
    if (!NumberKeypad.canAppend(_answer, key)) return;
    setState(() => _answer += key);
  }

  void _onBackspace() {
    if (_answer.isEmpty) return;
    setState(() => _answer = _answer.substring(0, _answer.length - 1));
  }

  void _submit() {
    if (_answer.isEmpty || _isCorrect != null) return;
    setState(() {
      // 键盘输出为 ASCII '-'；归一只为防御历史 Unicode 负号（U+2212）
      final answer = _answer.replaceAll('−', '-');
      _isCorrect = answer == widget.correctAnswer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('再练一次'),
      // 内嵌键盘后内容高度接近 AlertDialog 上限，小屏 / 大字体下可能超出，
      // 用 SingleChildScrollView 兜底（正常尺寸直接完整展示，不滚动）。
      content: SingleChildScrollView(
        child: Column(
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
              // 答案显示（通过键盘输入）
              ColoredCard(
                color: theme.colorScheme.primary,
                width: double.infinity,
                child: Column(
                  children: [
                    Text(
                      _answer.isEmpty ? '输入答案' : _answer,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TypographyTokens.fsTitle,
                        fontWeight: FontWeight.bold,
                        color: _answer.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (_answer.isEmpty && _showEllipsis)
                      Padding(
                        padding: const EdgeInsets.only(top: SpacingTokens.xs),
                        child: Text(
                          '例如：3…2',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              // 数字键盘（特殊键按正确答案形态自适应）
              NumberKeypad(
                onNumberTap: _onNumberTap,
                onBackspace: _onBackspace,
                onSubmit: _submit,
                submitEnabled: _answer.isNotEmpty,
                showEllipsis: _showEllipsis,
                showSlash: _showSlash,
                showDecimal: _showDecimal,
                showNegative: _showNegative,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_isCorrect != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_isCorrect),
            child: const Text('关闭'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
      ],
    );
  }
}
