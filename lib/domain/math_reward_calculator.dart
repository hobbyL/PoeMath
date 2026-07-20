// lib/domain/math_reward_calculator.dart
//
// 口算完成奖励规则。普通练习与限时挑战共用同一计算入口。

class MathRewardCalculator {
  const MathRewardCalculator._();

  static int calculateStars({
    required int totalProblems,
    required int correctCount,
  }) {
    if (totalProblems < 0) {
      throw RangeError.range(totalProblems, 0, null, 'totalProblems');
    }
    if (correctCount < 0 || correctCount > totalProblems) {
      throw RangeError.range(
        correctCount,
        0,
        totalProblems,
        'correctCount',
      );
    }
    if (totalProblems == 0) return 0;

    final accuracy = correctCount / totalProblems;
    if (accuracy >= 1.0) return 3;
    if (accuracy >= 0.9) return 2;
    if (accuracy >= 0.7) return 1;
    return 0;
  }
}
