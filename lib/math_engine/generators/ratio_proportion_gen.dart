// lib/math_engine/generators/ratio_proportion_gen.dart
//
// 比例生成器（6 年级下）。
//
// 题面以 displayText 输出 'a : b = c : ?' 专题形态（a:b 为最简整数比）；
// 内部结构保持 [c] × [b/a] 的通用乘法形式（c × b/a = d，与比例语义等价）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 比例生成器（a : b = c : ?）。
class RatioProportionGen extends BaseGenerator {
  RatioProportionGen(super.config, {super.random});

  @override
  MathProblem generate() {
    // 最简整数比：gcd(a, b) == 1（重试保证）
    var a = 3;
    var b = 4;
    var simplified = false;
    for (var attempt = 0; attempt < 200; attempt++) {
      final ca = randomInt(1, 12);
      final cb = randomInt(1, 12);
      if (_gcd(ca, cb) == 1) {
        a = ca;
        b = cb;
        simplified = true;
        break;
      }
    }
    if (!simplified) {
      // 保底：3 : 4 互质
      a = 3;
      b = 4;
    }

    // multiplier 上限保证 c、d ≤ maxOperand（过约束校验）
    final maxSide = a > b ? a : b;
    final divisorCap = config.maxOperand ~/ maxSide;
    final maxMultiplier = (divisorCap < 9 ? divisorCap : 9).clamp(2, 9);
    final multiplier = randomInt(2, maxMultiplier);

    final c = a * multiplier;
    final d = b * multiplier;

    return MathProblem(
      operands: [NumberValue.fromInt(c), NumberValue.fromFraction(b, a)],
      operators: [Operator.multiply],
      result: NumberValue.fromInt(d),
      mode: ProblemMode.findResult,
      grade: config.grade,
      difficulty: 3,
      displayText: '$a : $b = $c : ?',
    );
  }

  static int _gcd(int x, int y) {
    while (y != 0) {
      final t = x % y;
      x = y;
      y = t;
    }
    return x;
  }
}
