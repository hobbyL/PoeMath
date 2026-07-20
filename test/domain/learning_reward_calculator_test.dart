import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/domain/learning_reward_calculator.dart';

void main() {
  group('LearningRewardCalculator', () {
    test('诗词测试、普通口算和挑战使用统一正确率档位', () {
      for (final type in [
        LearningActivityType.poemQuiz,
        LearningActivityType.mathPractice,
        LearningActivityType.mathChallenge,
      ]) {
        expect(_stars(type, 10, 10), 3);
        expect(_stars(type, 10, 9), 2);
        expect(_stars(type, 10, 7), 1);
        expect(_stars(type, 10, 6), 0);
      }
    });

    test('背诵按整次活动质量结算为最多三颗星', () {
      expect(_stars(LearningActivityType.poemRecitation, 12, 12), 3);
      expect(_stars(LearningActivityType.poemRecitation, 12, 8), 2);
      expect(_stars(LearningActivityType.poemRecitation, 12, 7), 1);
      expect(_stars(LearningActivityType.poemRecitation, 12, 0), 0);
    });

    test('错题重练、跟读和手动打卡明确不发放星星', () {
      for (final type in [
        LearningActivityType.mistakeReview,
        LearningActivityType.readAlong,
        LearningActivityType.manualCheckIn,
      ]) {
        expect(_stars(type, 1, 1), 0);
      }
    });

    test('拒绝非法题数和成功数', () {
      expect(
        () => _stars(LearningActivityType.poemQuiz, -1, 0),
        throwsRangeError,
      );
      expect(
        () => _stars(LearningActivityType.poemQuiz, 2, 3),
        throwsRangeError,
      );
    });
  });
}

int _stars(LearningActivityType type, int total, int successful) {
  return LearningRewardCalculator.calculateStars(
    activityType: type,
    totalItems: total,
    successfulItems: successful,
  );
}
