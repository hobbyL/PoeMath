// lib/math_engine/validators/expression_evaluator.dart
//
// 显示语义求值器：按题目题面的标准数学语义（先算括号，括号内与
// 括号外均先乘除后加减、同级从左到右）用 Fraction 精确求值。
//
// 供三处复用，消灭各自的私有求值逻辑：
// - MixedOperationGen（生成）
// - ConstraintChecker（校验）
// - StepSolver（讲解）

import '../models/math_problem.dart';
import '../models/number_value.dart';

/// 求值中间步骤：一次二元折叠的表达式与精确结果。
typedef EvaluationStep = ({String expression, Fraction value});

/// 求值轨迹：逐步折叠序列 + 最终值（末步 value 即最终结果）。
class EvaluationTrace {
  const EvaluationTrace({required this.steps, required this.value});

  final List<EvaluationStep> steps;
  final Fraction value;
}

/// 按题目显示语义精确求值。
///
/// - 全程 Fraction 精确运算（无 double、无整数截断）。
/// - 返回 null 表示存在除零，无法求值（不依赖 Fraction./ 的 assert）。
/// - 整数性由调用方按题型判断（整数题要求结果 isInteger）。
class ExpressionEvaluator {
  const ExpressionEvaluator._();

  /// 求值，返回最终精确结果。
  static Fraction? evaluate(
    List<NumberValue> operands,
    List<Operator> operators, {
    (int, int)? bracketRange,
  }) {
    return evaluateWithSteps(
      operands,
      operators,
      bracketRange: bracketRange,
    )?.value;
  }

  /// 求值并返回逐步折叠轨迹（供 StepSolver 讲解复用）。
  ///
  /// 步骤示例（(71 + 10) × 7 × 4）：
  /// 1. '(71 + 10)' → 81
  /// 2. '81 × 7' → 567
  /// 3. '567 × 4' → 2268
  static EvaluationTrace? evaluateWithSteps(
    List<NumberValue> operands,
    List<Operator> operators, {
    (int, int)? bracketRange,
  }) {
    if (operands.length != operators.length + 1) return null;
    if (operands.isEmpty) return null;

    var vals = operands.map((o) => o.asFraction).toList();
    // 每个当前值的显示文本（初始为原始操作数，折叠后为上一步结果）
    var exprs = operands.map((o) => o.toString()).toList();
    var ops = List<Operator>.from(operators);
    final steps = <EvaluationStep>[];

    // 1. 括号内：先乘除（从左到右）、后加减（从左到右）折叠为单值。
    //    括号内同样遵循运算优先级（(71 + 10 × 2) 的语义是 91 而非 162），
    //    步骤表达式以括号包裹，与题面显示一致。
    final br = bracketRange;
    if (br != null) {
      final start = br.$1;
      final end = br.$2;
      if (start < 0 || end > vals.length || end - start < 2) return null;
      final bVals = vals.sublist(start, end);
      final bExprs = exprs.sublist(start, end);
      final bOps = ops.sublist(start, end - 1);

      var i = 0;
      while (i < bOps.length) {
        final op = bOps[i];
        if (op == Operator.multiply || op == Operator.divide) {
          final applied = _apply(bVals[i], bVals[i + 1], op);
          if (applied == null) return null;
          steps.add(
            (
              expression: '(${bExprs[i]} ${op.symbol} ${bExprs[i + 1]})',
              value: applied,
            ),
          );
          bVals[i] = applied;
          bExprs[i] = _format(applied);
          bVals.removeAt(i + 1);
          bExprs.removeAt(i + 1);
          bOps.removeAt(i);
        } else {
          i++;
        }
      }

      while (bOps.isNotEmpty) {
        final op = bOps.first;
        final applied = _apply(bVals[0], bVals[1], op);
        if (applied == null) return null;
        steps.add(
          (
            expression: '(${bExprs[0]} ${op.symbol} ${bExprs[1]})',
            value: applied,
          ),
        );
        bVals[0] = applied;
        bExprs[0] = _format(applied);
        bVals.removeAt(1);
        bExprs.removeAt(1);
        bOps.removeAt(0);
      }

      vals = [...vals.sublist(0, start), bVals[0], ...vals.sublist(end)];
      exprs = [
        ...exprs.sublist(0, start),
        _format(bVals[0]),
        ...exprs.sublist(end),
      ];
      ops = [...ops.sublist(0, start), ...ops.sublist(end - 1)];
    }

    // 2. 括号外：先乘除（从左到右）
    var i = 0;
    while (i < ops.length) {
      final op = ops[i];
      if (op == Operator.multiply || op == Operator.divide) {
        final applied = _apply(vals[i], vals[i + 1], op);
        if (applied == null) return null;
        steps.add(
          (expression: '${exprs[i]} ${op.symbol} ${exprs[i + 1]}', value: applied),
        );
        vals[i] = applied;
        exprs[i] = _format(applied);
        vals.removeAt(i + 1);
        exprs.removeAt(i + 1);
        ops.removeAt(i);
      } else {
        i++;
      }
    }

    // 3. 后加减（从左到右）
    while (ops.isNotEmpty) {
      final op = ops.first;
      final applied = _apply(vals[0], vals[1], op);
      if (applied == null) return null;
      steps.add(
        (expression: '${exprs[0]} ${op.symbol} ${exprs[1]}', value: applied),
      );
      vals[0] = applied;
      exprs[0] = _format(applied);
      vals.removeAt(1);
      exprs.removeAt(1);
      ops.removeAt(0);
    }

    return EvaluationTrace(steps: steps, value: vals.first);
  }

  /// 单次二元运算；除数为零返回 null。
  static Fraction? _apply(Fraction a, Fraction b, Operator op) {
    switch (op) {
      case Operator.add:
        return a + b;
      case Operator.subtract:
        return a - b;
      case Operator.multiply:
        return a * b;
      case Operator.divide:
        if (b.numerator == 0) return null;
        return a / b;
    }
  }

  static String _format(Fraction v) =>
      v.isInteger ? v.asInteger.toString() : v.toImproperString();
}
