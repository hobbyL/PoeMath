// lib/math_engine/generators/ratio_proportion_gen.dart
//
// 比例生成器（6 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 比例生成器（a : b = c : ?）。
class RatioProportionGen extends BaseGenerator {
  RatioProportionGen(super.config, {super.random});

  @override
  MathProblem generate() {
    // 简化比：a : b，然后放大为 c : d
    final a = randomInt(1, 12);
    final b = randomInt(1, 12);
    final multiplier = randomInt(2, 10);

    final c = a * multiplier;
    final d = b * multiplier;

    // 求 d（已知 a, b, c）
    // a : b = c : ?   →  ? = b × c / a
    final operands = [
      NumberValue.fromInt(c),
      NumberValue.fromFraction(b, a),
    ];
    final operators = [Operator.multiply];

    return MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(d),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: 3,
    );
  }
}
