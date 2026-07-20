import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('LearningActivity 完整字段可通过 Hive 往返', () async {
    final completedAt = DateTime(2026, 7, 20, 12, 30);
    final activity = LearningActivity(
      id: 'poem_quiz:poem_1:1',
      profileId: 'default',
      activityType: LearningActivityType.poemQuiz.name,
      totalItems: 5,
      successfulItems: 4,
      poemId: 'poem_1',
      starsEarned: 1,
      durationSeconds: 80,
      completedAt: completedAt,
    );

    await HiveBoxes.learningActivities.put('default_${activity.id}', activity);
    final restored = HiveBoxes.learningActivities.get('default_${activity.id}');

    expect(restored, isNotNull);
    expect(restored!.id, activity.id);
    expect(restored.type, LearningActivityType.poemQuiz);
    expect(restored.totalItems, 5);
    expect(restored.successfulItems, 4);
    expect(restored.poemId, 'poem_1');
    expect(restored.starsEarned, 1);
    expect(restored.durationSeconds, 80);
    expect(restored.completedAt, completedAt);
  });
}
