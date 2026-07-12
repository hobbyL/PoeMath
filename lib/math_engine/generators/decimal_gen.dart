// lib/math_engine/generators/decimal_gen.dart
//
// 小数运算生成器（4-5 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 小数运算生成器。
class DecimalGen extends BaseGenerator {
  DecimalGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final ops = config.allowedOperators.toList();
    final op = randomChoice(ops);

    switch (op) {
      case Operator.add:
        return _generateAdd();
      case Operator.subtract:
        return _generateSub();
      case Operator.multiply:
        return _generateMul();
      case Operator.divide:
        return _generateDiv();
    }
  }

  MathProblem _generateAdd() {
    final places = randomInt(1, config.maxDecimalPlaces.clamp(1, 3));
    final a = randomDecimal(0.1, config.maxOperand.toDouble(), places);
    final b = randomDecimal(0.1, config.maxOperand.toDouble(), places);
    final result = a + b;

    if (result > config.maxResult) return _generateAdd();

    final operands = [NumberValue.fromDouble(a), NumberValue.fromDouble(b)];
    final operators = [Operator.add];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromDouble(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: scoreDifficulty(operands, operators),
      resultForm: ResultForm.decimal,
    );
  }

  MathProblem _generateSub() {
    final places = randomInt(1, config.maxDecimalPlaces.clamp(1, 3));
    final a = randomDecimal(1, config.maxOperand.toDouble(), places);
    final b = randomDecimal(0.1, a, places);

    final operands = [NumberValue.fromDouble(a), NumberValue.fromDouble(b)];
    final operators = [Operator.subtract];
    final result = a - b;

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromDouble(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: scoreDifficulty(operands, operators),
      resultForm: ResultForm.decimal,
    );
  }

  MathProblem _generateMul() {
    final placesA = randomInt(1, 2);
    final placesB = randomInt(0, 1);
    final a = randomDecimal(0.1, 99.9, placesA);
    final b = placesB == 0
        ? randomInt(2, 9).toDouble()
        : randomDecimal(0.1, 9.9, 1);
    final result = a * b;

    if (result > config.maxResult || result < 0.01) return _generateMul();

    final operands = [NumberValue.fromDouble(a), NumberValue.fromDouble(b)];
    final operators = [Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromDouble(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: (scoreDifficulty(operands, operators) + 1).clamp(1, 5),
      resultForm: ResultForm.decimal,
    );
  }

  MathProblem _generateDiv() {
    // 反向构造：先有商和除数，再算被除数
    final placesQ = randomInt(1, 2);
    final quotient = randomDecimal(0.1, 99.9, placesQ);
    final divisor = randomInt(2, 9).toDouble();
    final dividend = quotient * divisor;

    if (dividend > config.maxDividend || dividend < 0.1) return _generateDiv();

    final operands = [
      NumberValue.fromDouble(dividend),
      NumberValue.fromDouble(divisor),
    ];
    final operators = [Operator.divide];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromDouble(quotient),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: (scoreDifficulty(operands, operators) + 1).clamp(1, 5),
      resultForm: ResultForm.decimal,
    );
  }
}
