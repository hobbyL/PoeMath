import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/math_reward_calculator.dart';

void main() {
  group('MathRewardCalculator', () {
    test('没有完成题目时不奖励星星', () {
      expect(
        MathRewardCalculator.calculateStars(
          totalProblems: 0,
          correctCount: 0,
        ),
        0,
      );
    });

    test('正确率低于 70% 时不奖励星星', () {
      expect(
        MathRewardCalculator.calculateStars(
          totalProblems: 10,
          correctCount: 6,
        ),
        0,
      );
    });

    test('70% 和 90% 边界使用包含规则', () {
      expect(
        MathRewardCalculator.calculateStars(
          totalProblems: 10,
          correctCount: 7,
        ),
        1,
      );
      expect(
        MathRewardCalculator.calculateStars(
          totalProblems: 10,
          correctCount: 9,
        ),
        2,
      );
    });

    test('全对奖励 3 星', () {
      expect(
        MathRewardCalculator.calculateStars(
          totalProblems: 10,
          correctCount: 10,
        ),
        3,
      );
    });
  });
}
