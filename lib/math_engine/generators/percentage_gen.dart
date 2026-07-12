// lib/math_engine/generators/percentage_gen.dart
//
// 百分数生成器（6 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 百分数生成器。
class PercentageGen extends BaseGenerator {
  PercentageGen(super.config, {super.random});

  @override
  MathProblem generate() {
    // 生成 a × p% = ? 或 a ÷ p% = ? 形式
    final useDiv = randomInt(0, 1) == 0;

    if (useDiv) {
      return _generatePercentDiv();
    }
    return _generatePercentMul();
  }

  MathProblem _generatePercentMul() {
    final percent = randomInt(5, 95);
    final base = randomInt(10, 1000);
    final result = base * percent ~/ 100;

    if (result <= 0 || base * percent % 100 != 0) return _generatePercentMul();

    final operands = [
      NumberValue.fromInt(base),
      NumberValue.fromFraction(percent, 100),
    ];
    final operators = [Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: 3,
    );
  }

  MathProblem _generatePercentDiv() {
    final percent = randomChoice([10, 20, 25, 50, 75]);
    final result = randomInt(10, 200);
    final base = result * 100 ~/ percent;

    final operands = [
      NumberValue.fromInt(base),
      NumberValue.fromFraction(percent, 100),
    ];
    final operators = [Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: 3,
    );
  }
}
