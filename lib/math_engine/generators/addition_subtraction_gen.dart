// lib/math_engine/generators/addition_subtraction_gen.dart
//
// 加减法生成器（1-2 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 加减法生成器。
class AdditionSubtractionGen extends BaseGenerator {
  AdditionSubtractionGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final op = randomChoiceFromSet(
      config.allowedOperators
          .intersection({Operator.add, Operator.subtract}),
    );

    // 操作数必须落在 [minOperand, maxOperand]；结果不超过 maxResult。
    // 不能用 maxResult 当操作数上界（如 5 年级上 maxResult=100000、maxOperand=1000）。
    final minOp = config.minOperand.round().clamp(0, 1000000);
    final maxOp = config.maxOperand.round().clamp(minOp, 1000000);
    final maxRes = config.maxResult.round().clamp(0, 100000000);

    final int a;
    final int b;
    final int result;

    if (op == Operator.add) {
      a = randomInt(minOp, maxOp);
      final maxB = (maxRes - a).clamp(minOp, maxOp);
      if (maxB < minOp) return generate();
      b = randomInt(minOp, maxB);
      result = a + b;
    } else {
      // 减法：被减数 a ∈ [minOp, maxOp]，减数 b ∈ [minOp, a] 且 ≤ maxOp
      a = randomInt(minOp, maxOp);
      if (a < minOp) return generate();
      final maxB = a < maxOp ? a : maxOp;
      if (maxB < minOp) {
        // 允许 b=0 的退路（一年级上 min 可为 0）
        b = minOp;
      } else {
        b = randomInt(minOp, maxB);
      }
      result = a - b;
    }

    // 进退位检查
    if (!config.allowCarry && op == Operator.add && _hasCarry(a, b)) {
      return generate(); // 重新生成
    }
    if (!config.allowBorrow && op == Operator.subtract && _hasBorrow(a, b)) {
      return generate();
    }

    final operands = [NumberValue.fromInt(a), NumberValue.fromInt(b)];
    final operators = [op];
    final difficulty = scoreDifficulty(operands, operators);

    final problem = MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: difficulty,
    );

    // 随机选择模式
    if (config.allowedModes.contains(ProblemMode.findMissing) &&
        randomInt(0, 2) == 0) {
      return toFindMissing(problem);
    }
    if (config.allowedModes.contains(ProblemMode.compare) &&
        randomInt(0, 3) == 0) {
      return toCompare(problem);
    }
    if (config.allowedModes.contains(ProblemMode.vertical) &&
        randomInt(0, 3) == 0) {
      return toVertical(problem);
    }

    return problem;
  }

  /// 判断加法是否有进位。
  bool _hasCarry(int a, int b) {
    while (a > 0 || b > 0) {
      if ((a % 10) + (b % 10) >= 10) return true;
      a ~/= 10;
      b ~/= 10;
    }
    return false;
  }

  /// 判断减法是否有退位。
  bool _hasBorrow(int a, int b) {
    while (a > 0 || b > 0) {
      if ((a % 10) < (b % 10)) return true;
      a ~/= 10;
      b ~/= 10;
    }
    return false;
  }
}
