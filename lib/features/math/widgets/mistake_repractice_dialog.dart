// lib/features/math/widgets/mistake_repractice_dialog.dart
//
// 错题重练对话框：展示原题、接受输入、判定正误。
// 使用 NumberKeypad 输入，特殊键按正确答案形态自适应
// （余数 … / 分数 / / 负号 - / 小数 .），保证余数、分数、负数、
// 小数答案均可通过键盘键入。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/math_mistake_snapshot.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/widgets/vertical_calc_widget.dart';
import 'package:poemath/features/math/widgets/vertical_process_input.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 所有错题入口共用：过程记录损坏时不降级成仅核对最终答案。
Future<bool?> showMistakeRepractice(
  BuildContext context,
  MathMistake mistake, {
  String title = '再练一次',
  bool barrierDismissible = true,
}) {
  final problem = mistake.originalProblem;
  if (mistake.errorType == VerticalAttempt.errorCategory &&
      (problem == null || !VerticalAttempt.supports(problem))) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本题过程记录不完整，暂时无法回练，请选择同类新题')),
    );
    return Future.value();
  }
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => MistakeRepracticeDialog(
      title: title,
      problemText: mistake.problemText,
      correctAnswer: mistake.correctAnswer,
      problem: problem,
    ),
  );
}

/// 错题重练对话框。
///
/// 返回 `true` 表示答对了，`false` 答错了，`null` 取消。
class MistakeRepracticeDialog extends StatefulWidget {
  const MistakeRepracticeDialog({
    super.key,
    required this.problemText,
    required this.correctAnswer,
    this.problem,
    this.title = '再练一次',
  });

  final String problemText;
  final String correctAnswer;
  final MathProblem? problem;
  final String title;

  @override
  State<MistakeRepracticeDialog> createState() =>
      _MistakeRepracticeDialogState();
}

class _MistakeRepracticeDialogState extends State<MistakeRepracticeDialog> {
  String _answer = '';
  bool? _isCorrect;
  VerticalAttempt _attempt = const VerticalAttempt();
  String _field = 'ones';
  bool get _process =>
      widget.problem != null && VerticalAttempt.supports(widget.problem!);

  // ============ 特殊键自适应（correctAnswer 是错题入库时的答案快照） ============

  bool get _showEllipsis => widget.correctAnswer.contains('…');
  bool get _isCompare =>
      const ['<', '=', '>'].contains(widget.correctAnswer.trim());

  bool get _showSlash => widget.correctAnswer.contains('/');

  /// 小数点仅在非余数、非分数形态下出现（'…' 与 '/' 互斥优先）
  bool get _showDecimal =>
      !_showEllipsis && !_showSlash && widget.correctAnswer.contains('.');

  /// 负号：负整数与负分数（如 -5/6）均以 '-' 开头
  bool get _showNegative => widget.correctAnswer.startsWith('-');

  void _onNumberTap(String key) {
    if (_process) {
      setState(() => _attempt = _attempt.withField(_field, key));
      return;
    }
    if (!NumberKeypad.canAppend(_answer, key)) return;
    setState(() => _answer += key);
  }

  void _onBackspace() {
    if (_process) {
      setState(() => _attempt = _attempt.withField(_field, ''));
      return;
    }
    if (_answer.isEmpty) return;
    setState(() => _answer = _answer.substring(0, _answer.length - 1));
  }

  void _submit() {
    if (_isCorrect != null ||
        (_process ? !_attempt.complete(widget.problem!) : _answer.isEmpty)) {
      return;
    }
    setState(() {
      // 键盘输出为 ASCII '-'；归一只为防御历史 Unicode 负号（U+2212）
      _isCorrect = _process
          ? _attempt.judge(widget.problem!).isCorrect
          : MathEngine.answersEquivalent(_answer, widget.correctAnswer);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      // 内嵌键盘后内容高度接近 AlertDialog 上限，小屏 / 大字体下可能超出，
      // 用 SingleChildScrollView 兜底（正常尺寸直接完整展示，不滚动）。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 题目
            if (widget.problem?.mode == ProblemMode.vertical)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: VerticalCalcWidget(problem: widget.problem!),
              )
            else
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
                      if (_process)
                        for (final step
                            in _attempt.judge(widget.problem!).correctSteps)
                          Text(
                            step.resultHint,
                            style: theme.textTheme.bodyMedium,
                          ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              // 答案显示（通过键盘输入）
              if (_process)
                VerticalProcessInput(
                  problem: widget.problem!,
                  attempt: _attempt,
                  selectedField: _field,
                  onSelect: (field) => setState(() => _field = field),
                )
              else
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
              if (_isCompare)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final symbol in const ['<', '=', '>'])
                      FilledButton(
                        onPressed: () {
                          _answer = symbol;
                          _submit();
                        },
                        child: Text(symbol),
                      ),
                  ],
                )
              else
                NumberKeypad(
                  onNumberTap: _onNumberTap,
                  onBackspace: _onBackspace,
                  onSubmit: _submit,
                  submitEnabled: _process
                      ? _attempt.complete(widget.problem!)
                      : _answer.isNotEmpty,
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
