// lib/math_engine/validators/constraint_checker.dart
//
// 约束校验器：检查生成的题目是否满足约束条件。

import '../models/grade_config.dart';
import '../models/math_problem.dart';
import '../models/math_skill.dart';
import '../models/number_value.dart';
import 'expression_evaluator.dart';

/// 约束校验器。
class ConstraintChecker {
  const ConstraintChecker._();

  /// 检查题目是否满足所有约束。返回 null 表示通过，否则返回原因。
  static String? check(MathProblem problem, GradeConfig config) {
    // 1. 结果非负（除非允许负数）
    if (!config.allowNegative && problem.result.isNegative) {
      return '结果为负数';
    }
    final target = problem.compareTarget;
    if (target != null &&
        ((!config.allowNegative && target.isNegative) ||
            target.asDouble.abs() > config.maxResult)) {
      return '比较目标超出学期范围';
    }

    // 2. 结果不超范围
    if (problem.result.asDouble.abs() > config.maxResult) {
      return '结果超出范围 (${config.maxResult})';
    }

    // 3. 除法整除性（非余数模式时）
    if (problem.resultForm != ResultForm.withRemainder) {
      for (var i = 0; i < problem.operators.length; i++) {
        if (problem.operators[i] == Operator.divide) {
          // 用精确 double 判零：分数除数（如 3/4）经 asInteger 会截断为 0，
          // 被误报「除数为零」，导致六上分数除法题全部被拒。
          final divisor = problem.operands[i + 1].asDouble;
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

    // 6. 模式白名单：生成器产出的模式必须在本学期允许列表内
    if (!config.allowedModes.contains(problem.mode)) {
      return '题目模式未被允许 (${problem.mode.name})';
    }

    // 7. 所有模式共享表达式语义，转换后也不能绕过核验。
    if (problem.resultForm != ResultForm.withRemainder) {
      final evaluated = ExpressionEvaluator.evaluate(
        problem.operands,
        problem.operators,
        bracketRange: problem.bracketRange,
      );
      final expected = problem.mode == ProblemMode.findMissing
          ? problem.expressionResult
          : problem.result;
      if (evaluated == null ||
          expected == null ||
          evaluated != expected.asFraction) {
        return problem.bracketRange != null ? '括号题答案与显示语义不一致' : '题目答案与显示语义不一致';
      }
      if (!config.allowFraction &&
          !config.allowDecimal &&
          problem.operands.every((o) => o.isInteger) &&
          !evaluated.isInteger) {
        return problem.bracketRange != null ? '括号题答案与显示语义不一致' : '题目答案与显示语义不一致';
      }
      if (problem.mode == ProblemMode.findMissing) {
        final index = problem.missingIndex;
        if (index == null ||
            index < 0 ||
            index >= problem.operands.length ||
            problem.operands[index] != problem.result) {
          return '未知项答案不一致';
        }
        // 单个未知数只出现一次时，四则表达式是一次分式函数。
        // 非常数函数在有效定义域内一一对应；另一个有效值仍得到同值即为退化常数题。
        for (final replacement in [1, 2, 3]) {
          final value = NumberValue.fromInt(replacement);
          if (value == problem.result) continue;
          final operands = List<NumberValue>.of(problem.operands)
            ..[index] = value;
          final alternative = ExpressionEvaluator.evaluate(
            operands,
            problem.operators,
            bracketRange: problem.bracketRange,
          );
          if (alternative == evaluated) return '未知项不唯一';
        }
      }
      if (problem.mode == ProblemMode.compare) {
        if (target == null) return '缺少比较目标';
        final relation = problem.result > target
            ? CompareRelation.greaterThan
            : problem.result < target
                ? CompareRelation.lessThan
                : CompareRelation.equal;
        if (problem.compareRelation != relation) return '比较关系与表达式不一致';
      }
    }

    return null;
  }
}

/// 难度评估器。
class DifficultyScorer {
  const DifficultyScorer._();

  /// 同一知识点内挑题用的细分分数；不改变历史题目保存的 1–5 评分。
  /// 数位、进退位和推理模式增加计算量，0/1 捷径降低计算量。
  static int selectionScore(MathProblem problem) {
    var score = 0;
    for (final value in problem.operands) {
      score += value.asInteger.abs().toString().length * 2;
      if (!value.isInteger) {
        score += 3 + value.asFraction.denominator.toString().length;
      }
      if (value.asDouble == 0) score -= 12;
    }
    if (MathSkill.hasRegrouping(problem)) score += 8;
    final denominators = problem.operands
        .where((value) => !value.isInteger)
        .map((value) => value.asFraction.denominator)
        .toSet();
    if (denominators.length > 1) score += 4;
    score += (problem.operators.length - 1) * 5;
    if (problem.bracketRange != null) score += 3;
    if (problem.mode == ProblemMode.findMissing ||
        problem.mode == ProblemMode.compare) {
      score += 2;
    }
    if (problem.operators.length == 1) {
      final a = problem.operands[0];
      final b = problem.operands[1];
      final op = problem.operators.single;
      final value = problem.expressionResult ?? problem.result;
      if ((op == Operator.multiply &&
              (a.asDouble.abs() == 1 || b.asDouble.abs() == 1)) ||
          (op == Operator.divide &&
              (b.asDouble.abs() == 1 || value.asDouble.abs() == 1)) ||
          (op == Operator.subtract && a == b)) {
        score -= 16;
      }
      if (op == Operator.multiply &&
          a.asDouble.abs() >= 6 &&
          b.asDouble.abs() >= 6) {
        score += 4;
      }
      if (op == Operator.divide &&
          b.asDouble.abs() >= 6 &&
          value.asDouble.abs() >= 6) {
        score += 4;
      }
    }
    return score;
  }

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
