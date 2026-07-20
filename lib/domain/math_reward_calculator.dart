// lib/domain/math_reward_calculator.dart
//
// 口算完成奖励规则。保留兼容入口，实际规则由学习活动奖励策略统一管理。

import 'package:poemath/domain/learning_reward_calculator.dart';

class MathRewardCalculator {
  const MathRewardCalculator._();

  static int calculateStars({
    required int totalProblems,
    required int correctCount,
  }) {
    return LearningRewardCalculator.calculateStars(
      activityType: LearningActivityType.mathPractice,
      totalItems: totalProblems,
      successfulItems: correctCount,
    );
  }
}
