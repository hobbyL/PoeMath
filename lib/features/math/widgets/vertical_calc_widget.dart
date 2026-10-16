// lib/features/math/widgets/vertical_calc_widget.dart
//
// 竖式计算展示 Widget：以竖式格式显示加减乘法题目。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 竖式计算展示 Widget。
///
/// 将两操作数的加减乘法以竖式格式显示：
/// ```
///     38
///   + 45
///   ────
///     ?
/// ```
class VerticalCalcWidget extends StatelessWidget {
  const VerticalCalcWidget({
    super.key,
    required this.problem,
    this.showAnswer = false,
  });

  final MathProblem problem;

  /// 是否显示答案（答题后设为 true）。
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operands = problem.operands;
    final operator = problem.operators.first;

    if (operands.length < 2) {
      return Text(
        problem.problemText,
        style: TypographyTokens.mathProblemStyle(
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    // 使用 toString() 保留小数和符号，显示实际数值
    var aStr = operands[0].toString();
    var bStr = operands[1].toString();
    var resultStr = problem.result.toString();
    // 小数加减按小数点对齐，补零保持位值；乘法仍按末位对齐。
    if (operator == Operator.add || operator == Operator.subtract) {
      final values = [aStr, bStr, resultStr];
      final places = values
          .map((s) => s.contains('.') ? s.split('.').last.length : 0)
          .reduce((a, b) => a > b ? a : b);
      if (places > 0) {
        String align(String value) {
          final parts = value.split('.');
          return '${parts.first}.${(parts.length > 1 ? parts.last : '').padRight(places, '0')}';
        }

        aStr = align(aStr);
        bStr = align(bStr);
        resultStr = align(resultStr);
      }
    }

    // 确定最大字符宽度，用于右对齐
    final maxDigits = [aStr.length, bStr.length, resultStr.length]
        .reduce((a, b) => a > b ? a : b);

    // 字符宽度（等宽字体）
    const digitStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 36,
      fontWeight: FontWeight.bold,
      height: 1.4,
    );

    final primaryColor = theme.colorScheme.primary;
    final lineColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：第一个操作数（右对齐）
          Text(
            aStr.padLeft(maxDigits),
            style: digitStyle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),

          // 第二行：运算符 + 第二个操作数
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                operator.symbol,
                style: digitStyle.copyWith(color: primaryColor),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                bStr.padLeft(maxDigits),
                style: digitStyle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),

          // 横线
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
            child: Container(
              height: 2,
              color: lineColor,
            ),
          ),

          // 结果行
          Text(
            showAnswer ? resultStr.padLeft(maxDigits) : '?'.padLeft(maxDigits),
            style: digitStyle.copyWith(
              color: showAnswer ? theme.semantic.success : primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
