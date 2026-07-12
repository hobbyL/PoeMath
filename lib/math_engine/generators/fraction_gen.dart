// lib/math_engine/generators/fraction_gen.dart
//
// 分数运算生成器（5-6 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 分数运算生成器。
class FractionGen extends BaseGenerator {
  FractionGen(super.config, {super.random});

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
    final maxDen = config.maxDenominator.clamp(2, 20);
    final d1 = randomInt(2, maxDen);
    final d2 = randomInt(2, maxDen);
    final n1 = randomInt(1, d1 - 1);
    final n2 = randomInt(1, d2 - 1);

    final a = NumberValue.fromFraction(n1, d1);
    final b = NumberValue.fromFraction(n2, d2);
    final result = a + b;

    // 确保结果合理（不超过一定范围）
    if (result.asDouble > config.maxResult) return _generateAdd();

    final operands = [a, b];
    final operators = [Operator.add];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: result,
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: _fractionDifficulty(d1, d2),
      resultForm: ResultForm.fraction,
    );
  }

  MathProblem _generateSub() {
    final maxDen = config.maxDenominator.clamp(2, 20);
    final d1 = randomInt(2, maxDen);
    final d2 = randomInt(2, maxDen);
    final n1 = randomInt(1, d1 - 1);
    final n2 = randomInt(1, d2 - 1);

    var a = NumberValue.fromFraction(n1, d1);
    var b = NumberValue.fromFraction(n2, d2);

    // 确保 a >= b
    if (a < b) {
      final temp = a;
      a = b;
      b = temp;
    }

    final result = a - b;

    final operands = [a, b];
    final operators = [Operator.subtract];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: result,
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: _fractionDifficulty(d1, d2),
      resultForm: ResultForm.fraction,
    );
  }

  MathProblem _generateMul() {
    final maxDen = config.maxDenominator.clamp(2, 12);
    final d1 = randomInt(2, maxDen);
    final d2 = randomInt(2, maxDen);
    final n1 = randomInt(1, d1);
    final n2 = randomInt(1, d2);

    final a = NumberValue.fromFraction(n1, d1);
    final b = NumberValue.fromFraction(n2, d2);
    final result = a * b;

    final operands = [a, b];
    final operators = [Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: result,
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: (_fractionDifficulty(d1, d2) + 1).clamp(1, 5),
      resultForm: ResultForm.fraction,
    );
  }

  MathProblem _generateDiv() {
    final maxDen = config.maxDenominator.clamp(2, 12);
    final d1 = randomInt(2, maxDen);
    final d2 = randomInt(2, maxDen);
    final n1 = randomInt(1, d1);
    final n2 = randomInt(1, d2);

    if (n2 == 0) return _generateDiv();

    final a = NumberValue.fromFraction(n1, d1);
    final b = NumberValue.fromFraction(n2, d2);
    final result = a / b;

    final operands = [a, b];
    final operators = [Operator.divide];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: result,
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: (_fractionDifficulty(d1, d2) + 1).clamp(1, 5),
      resultForm: ResultForm.fraction,
    );
  }

  int _fractionDifficulty(int d1, int d2) {
    var score = 2;
    if (d1 != d2) score++; // 异分母
    if (d1 > 10 || d2 > 10) score++;
    return score.clamp(1, 5);
  }
}
