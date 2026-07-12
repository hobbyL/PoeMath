// lib/math_engine/generators/simple_equation_gen.dart
//
// 简易方程生成器（5-6 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 简易方程生成器（本质上是 findMissing 模式的变体）。
class SimpleEquationGen extends BaseGenerator {
  SimpleEquationGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final op = randomChoiceFromSet(config.allowedOperators);

    switch (op) {
      case Operator.add:
        return _generateAddEquation();
      case Operator.subtract:
        return _generateSubEquation();
      case Operator.multiply:
        return _generateMulEquation();
      case Operator.divide:
        return _generateDivEquation();
    }
  }

  /// x + a = b
  MathProblem _generateAddEquation() {
    final b = randomInt(10, 100);
    final a = randomInt(1, b - 1);
    final x = b - a;

    return _buildEquation(
      operands: [NumberValue.fromInt(x), NumberValue.fromInt(a)],
      operator: Operator.add,
      result: NumberValue.fromInt(b),
      answer: NumberValue.fromInt(x),
      missingIndex: 0,
    );
  }

  /// x - a = b
  MathProblem _generateSubEquation() {
    final x = randomInt(10, 100);
    final a = randomInt(1, x - 1);
    final b = x - a;

    return _buildEquation(
      operands: [NumberValue.fromInt(x), NumberValue.fromInt(a)],
      operator: Operator.subtract,
      result: NumberValue.fromInt(b),
      answer: NumberValue.fromInt(x),
      missingIndex: 0,
    );
  }

  /// a × x = b
  MathProblem _generateMulEquation() {
    final a = randomInt(2, 12);
    final x = randomInt(2, 20);
    final b = a * x;

    return _buildEquation(
      operands: [NumberValue.fromInt(a), NumberValue.fromInt(x)],
      operator: Operator.multiply,
      result: NumberValue.fromInt(b),
      answer: NumberValue.fromInt(x),
      missingIndex: 1,
    );
  }

  /// a ÷ x = b
  MathProblem _generateDivEquation() {
    final x = randomInt(2, 12);
    final b = randomInt(2, 20);
    final a = x * b;

    return _buildEquation(
      operands: [NumberValue.fromInt(a), NumberValue.fromInt(x)],
      operator: Operator.divide,
      result: NumberValue.fromInt(b),
      answer: NumberValue.fromInt(x),
      missingIndex: 1,
    );
  }

  MathProblem _buildEquation({
    required List<NumberValue> operands,
    required Operator operator,
    required NumberValue result,
    required NumberValue answer,
    required int missingIndex,
  }) {
    return MathProblem(
      operands: operands,
      operators: [operator],
      result: answer,
      mode: ProblemMode.findMissing,
      grade: config.grade,
      difficulty: 3,
      missingIndex: missingIndex,
    );
  }
}
