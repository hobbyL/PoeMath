// lib/math_engine/generators/multi_digit_mul_div_gen.dart
//
// 多位数乘除法生成器（3 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 多位数乘除法生成器。
class MultiDigitMulDivGen extends BaseGenerator {
  MultiDigitMulDivGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final useDiv = config.allowedOperators.contains(Operator.divide) &&
        randomInt(0, 1) == 0;
    return useDiv ? _generateDivision() : _generateMultiplication();
  }

  MathProblem _generateMultiplication() {
    final maxA = config.maxMultiplier.clamp(10, 999);
    final a = randomInt(10, maxA);
    // 3年级上：多位数×一位数，3年级下：两位数×两位数
    final maxB = config.semester == '上' ? 9 : 99.clamp(1, config.maxMultiplier);
    final b = randomInt(2, maxB);
    final result = a * b;

    if (result > config.maxResult) return generate();

    final operands = [NumberValue.fromInt(a), NumberValue.fromInt(b)];
    final operators = [Operator.multiply];
    final difficulty = scoreDifficulty(operands, operators);

    final problem = MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: difficulty,
    );

    if (config.allowedModes.contains(ProblemMode.findMissing) &&
        randomInt(0, 3) == 0) {
      return toFindMissing(problem);
    }
    return problem;
  }

  MathProblem _generateDivision() {
    final b = randomInt(2, config.semester == '上' ? 9 : 99);
    final quotient = randomInt(10, (config.maxDividend / b).floor().clamp(10, 999));
    final a = b * quotient;

    if (a > config.maxDividend) return _generateDivision();

    final operands = [NumberValue.fromInt(a), NumberValue.fromInt(b)];
    final operators = [Operator.divide];
    final difficulty = scoreDifficulty(operands, operators);

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(quotient),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: difficulty,
    );
  }
}
