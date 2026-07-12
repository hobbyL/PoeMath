// lib/math_engine/generators/law_of_operation_gen.dart
//
// 运算律生成器（4 年级）：交换律、结合律、分配律。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 运算律练习生成器。
class LawOfOperationGen extends BaseGenerator {
  LawOfOperationGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final law = randomInt(0, 2);
    switch (law) {
      case 0:
        return _distributiveLaw();
      case 1:
        return _associativeLaw();
      default:
        return _commutativeLaw();
    }
  }

  /// 乘法分配律：(a + b) × c = ?
  MathProblem _distributiveLaw() {
    final a = randomInt(10, 99);
    final b = randomInt(10, 99);
    final c = randomInt(2, 9);
    final result = (a + b) * c;

    if (result > config.maxResult) return _distributiveLaw();

    final operands = [
      NumberValue.fromInt(a),
      NumberValue.fromInt(b),
      NumberValue.fromInt(c),
    ];
    final operators = [Operator.add, Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.withBrackets,
      grade: config.grade,
      difficulty: 3,
      bracketRange: (0, 2),
    );
  }

  /// 乘法结合律：a × b × c = ?
  MathProblem _associativeLaw() {
    final a = randomInt(2, 25);
    final b = randomInt(2, 9);
    final c = randomInt(2, 9);
    final result = a * b * c;

    if (result > config.maxResult) return _associativeLaw();

    final operands = [
      NumberValue.fromInt(a),
      NumberValue.fromInt(b),
      NumberValue.fromInt(c),
    ];
    final operators = [Operator.multiply, Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.chain,
      grade: config.grade,
      difficulty: 3,
    );
  }

  /// 加法交换律：a + b = b + a（验证形式）
  MathProblem _commutativeLaw() {
    final a = randomInt(10, 999);
    final b = randomInt(10, 999);
    final result = a + b;

    if (result > config.maxResult) return _commutativeLaw();

    final operands = [NumberValue.fromInt(a), NumberValue.fromInt(b)];
    final operators = [Operator.add];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: 2,
    );
  }
}
