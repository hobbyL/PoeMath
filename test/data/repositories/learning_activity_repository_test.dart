import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late LearningActivityRepository repository;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repository = LearningActivityRepository();
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  test('相同活动并发重放只写入一次', () async {
    final completedAt = DateTime(2026, 7, 20, 12);
    final results = await Future.wait([
      _recordMath(repository, id: 'math:1', completedAt: completedAt),
      _recordMath(repository, id: 'math:1', completedAt: completedAt),
    ]);

    expect(results.where((written) => written), hasLength(1));
    expect(HiveBoxes.learningActivities, hasLength(1));
  });

  test('同一 ID 被不同内容复用时拒绝覆盖历史', () async {
    final completedAt = DateTime(2026, 7, 20, 12);
    await _recordMath(repository, id: 'math:1', completedAt: completedAt);

    expect(
      () => repository.record(
        id: 'math:1',
        activityType: LearningActivityType.mathPractice,
        totalItems: 10,
        successfulItems: 8,
        starsEarned: 1,
        durationSeconds: 61,
        completedAt: completedAt,
      ),
      throwsStateError,
    );
    expect(repository.getById('math:1')!.durationSeconds, 60);
  });

  test('按当前 profile 隔离并按完成时间倒序查询', () async {
    final day = DateTime(2026, 7, 20);
    await _recordMath(
      repository,
      id: 'math:early',
      completedAt: day.add(const Duration(hours: 8)),
    );
    await _recordMath(
      repository,
      id: 'math:late',
      completedAt: day.add(const Duration(hours: 20)),
    );
    await HiveBoxes.learningActivities.put(
      'kid2_math:other',
      LearningActivity(
        id: 'math:other',
        profileId: 'kid2',
        activityType: LearningActivityType.mathPractice.name,
        totalItems: 1,
        successfulItems: 1,
        starsEarned: 3,
        durationSeconds: 10,
        completedAt: day.add(const Duration(hours: 12)),
      ),
    );

    expect(
      repository
          .completedBetween(day, day.add(const Duration(days: 1)))
          .map((activity) => activity.id),
      ['math:late', 'math:early'],
    );
  });

  test('校验计数、星星、时长和诗词活动 ID', () async {
    final completedAt = DateTime(2026, 7, 20);

    expect(
      () => repository.record(
        id: 'invalid-count',
        activityType: LearningActivityType.mathPractice,
        totalItems: 1,
        successfulItems: 2,
        starsEarned: 0,
        durationSeconds: 1,
        completedAt: completedAt,
      ),
      throwsRangeError,
    );
    expect(
      () => repository.record(
        id: 'invalid-stars',
        activityType: LearningActivityType.mathPractice,
        totalItems: 1,
        successfulItems: 1,
        starsEarned: 4,
        durationSeconds: 1,
        completedAt: completedAt,
      ),
      throwsRangeError,
    );
    expect(
      () => repository.record(
        id: 'missing-poem',
        activityType: LearningActivityType.poemQuiz,
        totalItems: 1,
        successfulItems: 1,
        starsEarned: 3,
        durationSeconds: 1,
        completedAt: completedAt,
      ),
      throwsArgumentError,
    );
  });
}

Future<bool> _recordMath(
  LearningActivityRepository repository, {
  required String id,
  required DateTime completedAt,
}) {
  return repository.record(
    id: id,
    activityType: LearningActivityType.mathPractice,
    totalItems: 10,
    successfulItems: 8,
    starsEarned: 1,
    durationSeconds: 60,
    completedAt: completedAt,
  );
}
