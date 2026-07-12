// lib/math_engine/generators/multiplication_table_gen.dart
//
// 乘法口诀生成器（2 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 乘法口诀生成器（1-9 × 1-9，含对应除法）。
class MultiplicationTableGen extends BaseGenerator {
  MultiplicationTableGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final useDiv = config.allowedOperators.contains(Operator.divide) &&
        randomInt(0, 1) == 0;

    if (useDiv) {
      return _generateDivision();
    }
    return _generateMultiplication();
  }

  MathProblem _generateMultiplication() {
    final a = randomInt(1, config.maxMultiplier.clamp(1, 9));
    final b = randomInt(1, 9);
    final result = a * b;

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
        randomInt(0, 2) == 0) {
      return toFindMissing(problem);
    }
    return problem;
  }

  MathProblem _generateDivision() {
    final b = randomInt(1, 9);
    final quotient = randomInt(1, 9);
    final a = b * quotient; // 确保整除

    final operands = [NumberValue.fromInt(a), NumberValue.fromInt(b)];
    final operators = [Operator.divide];
    final difficulty = scoreDifficulty(operands, operators);

    final problem = MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(quotient),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: difficulty,
    );

    if (config.allowedModes.contains(ProblemMode.findMissing) &&
        randomInt(0, 2) == 0) {
      return toFindMissing(problem);
    }
    return problem;
  }
}
