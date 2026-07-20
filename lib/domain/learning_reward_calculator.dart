// lib/domain/learning_reward_calculator.dart
//
// 学习活动奖励规则。所有正式学习活动统一从这里计算 0-3 颗星。

enum LearningActivityType {
  poemRecitation,
  poemQuiz,
  mathPractice,
  mathChallenge,
  mistakeReview,
  readAlong,
  manualCheckIn,
}

class LearningRewardCalculator {
  const LearningRewardCalculator._();

  static int calculateStars({
    required LearningActivityType activityType,
    required int totalItems,
    required int successfulItems,
  }) {
    if (totalItems < 0) {
      throw RangeError.range(totalItems, 0, null, 'totalItems');
    }
    if (successfulItems < 0 || successfulItems > totalItems) {
      throw RangeError.range(
        successfulItems,
        0,
        totalItems,
        'successfulItems',
      );
    }

    return switch (activityType) {
      LearningActivityType.poemRecitation =>
        _calculateRecitationStars(totalItems, successfulItems),
      LearningActivityType.poemQuiz ||
      LearningActivityType.mathPractice ||
      LearningActivityType.mathChallenge =>
        _calculateAccuracyStars(totalItems, successfulItems),
      LearningActivityType.mistakeReview ||
      LearningActivityType.readAlong ||
      LearningActivityType.manualCheckIn =>
        0,
    };
  }

  static int _calculateAccuracyStars(int totalItems, int successfulItems) {
    if (totalItems == 0) return 0;

    final accuracy = successfulItems / totalItems;
    if (accuracy >= 1.0) return 3;
    if (accuracy >= 0.9) return 2;
    if (accuracy >= 0.7) return 1;
    return 0;
  }

  static int _calculateRecitationStars(int totalItems, int qualityPoints) {
    if (totalItems == 0 || qualityPoints == 0) return 0;
    if (qualityPoints == totalItems) return 3;
    if (qualityPoints * 3 >= totalItems * 2) return 2;
    return 1;
  }
}
