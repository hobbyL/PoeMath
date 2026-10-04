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
    final maxOp = config.maxOperand.round().clamp(10, 999999);
    final maxMul = config.maxMultiplier.clamp(2, maxOp);
    final maxA = maxMul.clamp(10, maxOp);
    final a = randomInt(10, maxA);
    // 3年级上：多位数×一位数，3年级下：两位数×两位数
    final maxBRaw = config.semester == '上' ? 9 : 99;
    final maxB = maxBRaw.clamp(1, maxMul).clamp(1, maxOp);
    final b = randomInt(2, maxB);
    final result = a * b;

    if (result > config.maxResult) return generate();
    if (a > config.maxOperand || b > config.maxOperand) return generate();

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
    final maxOp = config.maxOperand.round().clamp(10, 999999);
    // 被除数有效上限：同时受 maxDividend 与 maxOperand（操作数上限）约束
    final dividendCap = config.maxDividend < maxOp ? config.maxDividend : maxOp;
    // 除数超过被除数上限一半时商恒为 1（x ÷ x = 1 退化题），
    // 将除数上限压到被除数上限的一半，保证商可达 ≥ 2。
    final divisorRawCap = config.semester == '上' ? 9 : 99;
    final divisorHalfCap = dividendCap ~/ 2;
    final maxDivisor =
        (divisorRawCap < divisorHalfCap ? divisorRawCap : divisorHalfCap)
            .clamp(2, maxOp);
    final b = randomInt(2, maxDivisor);
    final maxQuotient = (dividendCap / b).floor().clamp(1, 999);
    if (maxQuotient < 2) return _generateMultiplication();
    // 商从 2 起，避免 x ÷ x = 1 的退化题
    final quotient = randomInt(2, maxQuotient);
    final a = b * quotient;

    if (a > dividendCap || a > config.maxOperand || b > config.maxOperand) {
      return _generateMultiplication();
    }

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
