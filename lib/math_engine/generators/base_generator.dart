// lib/math_engine/generators/base_generator.dart
//
// 题目生成器基类。

import 'dart:math';

import '../models/grade_config.dart';
import '../models/math_problem.dart';
import '../models/number_value.dart';

/// 题目生成器基类。所有年级的具体生成器继承此类。
abstract class BaseGenerator {
  final GradeConfig config;
  final Random _random;

  BaseGenerator(this.config, {Random? random})
      : _random = random ?? Random();

  /// 生成一道题目。子类必须实现。
  MathProblem generate();

  /// 生成一道指定模式的题目。
  MathProblem generateWithMode(ProblemMode mode) => generate();

  // ============ 工具方法 ============

  /// 在 [min, max] 范围内生成随机整数。
  int randomInt(int min, int max) {
    if (min >= max) return min;
    return min + _random.nextInt(max - min + 1);
  }

  /// 在 [min, max] 范围内生成随机小数（指定小数位数）。
  double randomDecimal(double min, double max, int decimalPlaces) {
    final factor = pow(10, decimalPlaces).toInt();
    final minInt = (min * factor).ceil();
    final maxInt = (max * factor).floor();
    if (minInt >= maxInt) return min;
    final value = minInt + _random.nextInt(maxInt - minInt + 1);
    return value / factor;
  }

  /// 从列表中随机选择一个元素。
  T randomChoice<T>(List<T> items) {
    return items[_random.nextInt(items.length)];
  }

  /// 从 Set 中随机选择一个元素。
  T randomChoiceFromSet<T>(Set<T> items) {
    return randomChoice(items.toList());
  }

  /// 生成 findMissing 模式题目。
  MathProblem toFindMissing(MathProblem problem) {
    if (problem.operands.length < 2) return problem;
    final missingIndex = _random.nextInt(problem.operands.length);
    final missingValue = problem.operands[missingIndex];
    return MathProblem(
      operands: problem.operands,
      operators: problem.operators,
      result: missingValue,
      mode: ProblemMode.findMissing,
      grade: problem.grade,
      difficulty: problem.difficulty,
      resultForm: problem.resultForm,
      missingIndex: missingIndex,
    );
  }

  /// 生成 compare 模式题目。
  MathProblem toCompare(MathProblem problem) {
    final result = problem.result;
    final offset = randomInt(-3, 3);
    final targetValue = NumberValue.fromInt(result.asInteger + offset);
    final CompareRelation relation;
    if (offset > 0) {
      relation = CompareRelation.lessThan;
    } else if (offset < 0) {
      relation = CompareRelation.greaterThan;
    } else {
      relation = CompareRelation.equal;
    }
    return MathProblem(
      operands: problem.operands,
      operators: problem.operators,
      result: result,
      mode: ProblemMode.compare,
      grade: problem.grade,
      difficulty: problem.difficulty,
      resultForm: problem.resultForm,
      compareRelation: relation,
      compareTarget: targetValue,
    );
  }

  /// 评估难度分。
  int scoreDifficulty(List<NumberValue> operands, List<Operator> operators) {
    var score = 1;
    for (final op in operands) {
      final digits = op.asInteger.abs().toString().length;
      if (digits >= 4) {
        score += 2;
      } else if (digits >= 2) {
        score++;
      }
    }
    if (operators.contains(Operator.multiply) ||
        operators.contains(Operator.divide)) {
      score++;
    }
    if (operators.length > 1) score++;
    return score.clamp(1, 5);
  }
}
