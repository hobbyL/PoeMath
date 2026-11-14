// lib/math_engine/generators/negative_number_gen.dart
//
// 正负数运算生成器（6 年级下）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 正负数运算生成器。
class NegativeNumberGen extends BaseGenerator {
  NegativeNumberGen(super.config, {super.random});

  @override
  MathProblem generate() => generateWithRetries(_tryGenerate);

  MathProblem? _tryGenerate() {
    final allowed = config.allowedOperators.intersection({
      Operator.add,
      Operator.subtract,
    });
    if (allowed.isEmpty) throw StateError('负数范围缺少可用加减运算');
    final op = randomChoiceFromSet(allowed);

    final a = randomInt(-20, 20);
    final b = randomInt(-20, 20);

    // 确保至少一个负数
    if (a >= 0 && b >= 0) return null;

    final int result;
    if (op == Operator.add) {
      result = a + b;
    } else {
      result = a - b;
    }

    if (result.abs() > config.maxResult) return null;

    final operands = [NumberValue.fromInt(a), NumberValue.fromInt(b)];
    final operators = [op];

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
