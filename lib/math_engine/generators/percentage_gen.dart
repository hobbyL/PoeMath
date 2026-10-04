// lib/math_engine/generators/percentage_gen.dart
//
// 百分数生成器（6 年级上）。
//
// 题面以 displayText 输出 'base × percent% = ?' 专题形态；
// 内部结构保持 [base, percent/100] × 的通用乘法形式（判分/讲解不变）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 百分数生成器。
class PercentageGen extends BaseGenerator {
  PercentageGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final percent = randomInt(5, 95);
    final maxBase = config.maxOperand.clamp(10, 100);

    // 循环挑选使 base × percent % 100 == 0 的 base（整除构造保证整数结果）
    var base = 0;
    for (var attempt = 0; attempt < 200; attempt++) {
      final candidate = randomInt(10, maxBase);
      if (candidate * percent % 100 == 0) {
        base = candidate;
        break;
      }
    }
    if (base == 0) {
      // 保底：取 100 的因数百分比，从结果反推 base（必然整除）
      final easyPercent = randomChoice([10, 20, 25, 50]);
      final resultMax = (maxBase * easyPercent ~/ 100).clamp(2, maxBase);
      final result = randomInt(2, resultMax);
      return _build(result * 100 ~/ easyPercent, easyPercent);
    }
    return _build(base, percent);
  }

  MathProblem _build(int base, int percent) {
    final result = base * percent ~/ 100;
    return MathProblem(
      operands: [
        NumberValue.fromInt(base),
        NumberValue.fromFraction(percent, 100),
      ],
      operators: [Operator.multiply],
      result: NumberValue.fromInt(result),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: 3,
      displayText: '$base × $percent% = ?',
    );
  }
}
