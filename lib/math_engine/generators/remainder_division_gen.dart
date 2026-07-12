// lib/math_engine/generators/remainder_division_gen.dart
//
// 有余数除法生成器（2 年级下）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 有余数除法生成器。
class RemainderDivisionGen extends BaseGenerator {
  RemainderDivisionGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final divisor = randomInt(2, 9);
    final quotient = randomInt(1, 9);
    final remainder = randomInt(1, divisor - 1);
    final dividend = divisor * quotient + remainder;

    final operands = [
      NumberValue.fromInt(dividend),
      NumberValue.fromInt(divisor),
    ];
    final operators = [Operator.divide];
    final difficulty = scoreDifficulty(operands, operators);

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(quotient),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: difficulty,
      resultForm: ResultForm.withRemainder,
      remainder: remainder,
    );
  }
}
