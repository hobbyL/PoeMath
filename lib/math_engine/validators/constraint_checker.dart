// lib/math_engine/validators/constraint_checker.dart
//
// 约束校验器：检查生成的题目是否满足约束条件。

import '../models/grade_config.dart';
import '../models/math_problem.dart';

/// 约束校验器。
class ConstraintChecker {
  const ConstraintChecker._();

  /// 检查题目是否满足所有约束。返回 null 表示通过，否则返回原因。
  static String? check(MathProblem problem, GradeConfig config) {
    // 1. 结果非负（除非允许负数）
    if (!config.allowNegative && problem.result.isNegative) {
      return '结果为负数';
    }

    // 2. 结果不超范围
    if (problem.result.asDouble.abs() > config.maxResult) {
      return '结果超出范围 (${config.maxResult})';
    }

    // 3. 除法整除性（非余数模式时）
    if (problem.resultForm != ResultForm.withRemainder) {
      for (var i = 0; i < problem.operators.length; i++) {
        if (problem.operators[i] == Operator.divide) {
          final divisor = problem.operands[i + 1].asInteger;
          if (divisor == 0) return '除数为零';
        }
      }
    }

    // 4. 余数 < 除数
    if (problem.resultForm == ResultForm.withRemainder &&
        problem.remainder != null) {
      final divisor = problem.operands[1].asInteger;
      if (problem.remainder! >= divisor) {
        return '余数 (${problem.remainder}) ≥ 除数 ($divisor)';
      }
      if (problem.remainder! < 0) {
        return '余数为负';
      }
    }

    // 5. 操作数范围
    for (final op in problem.operands) {
      if (op.asDouble < config.minOperand || op.asDouble > config.maxOperand) {
        return '操作数超出范围 [${config.minOperand}, ${config.maxOperand}]';
      }
    }

    return null;
  }
}

/// 难度评估器。
class DifficultyScorer {
  const DifficultyScorer._();

  /// 评估题目难度（1-5）。
  static int score(MathProblem problem) {
    var s = 1;

    // 操作数位数
    for (final op in problem.operands) {
      final digits = op.asInteger.abs().toString().length;
      if (digits >= 4) {
        s += 2;
      } else if (digits >= 2) {
        s++;
      }
    }

    // 运算类型
    if (problem.operators.contains(Operator.multiply) ||
        problem.operators.contains(Operator.divide)) {
      s++;
    }

    // 运算步数
    if (problem.operators.length > 1) s++;
    if (problem.operators.length > 2) s++;

    // 分数/小数
    if (problem.resultForm == ResultForm.fraction) s++;
    if (problem.resultForm == ResultForm.decimal) s++;

    // 括号
    if (problem.mode == ProblemMode.withBrackets) s++;

    // findMissing
    if (problem.mode == ProblemMode.findMissing) s++;

    return s.clamp(1, 5);
  }
}
