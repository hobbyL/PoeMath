import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/day_key_override.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  final day = DateTime(2026, 11, 26);
  PictureStoryPracticeRecord completed(String id, {String? profileId}) =>
      PictureStoryPracticeRecord(
        id: id,
        profileId: profileId ?? ProfileScope.currentId,
        promptId: 'prompt',
        promptVersion: 1,
        startedAt: day,
        completedAt: day.add(const Duration(minutes: 2)),
        status: 'completed',
        segmentsJson: '[]',
        answerText: '小猫在看书。',
        totalDurationSeconds: 120,
      );

  Future<void> save(PictureStoryPracticeRecord record) => HiveBoxes
      .pictureStoryPractice
      .put(ProfileScope.key('picture_story:${record.id}'), record);

  test('完成记录已保存而活动写入缺失：首页与周报补齐且不改写存储', () async {
    final container = ProviderContainer(
      overrides: [staticDayKeyOverride('2026-11-26')],
    );
    addTearDown(container.dispose);
    final updates = <int>[];
    final sub = container.listen(
      todayLearningActivityCountsProvider,
      (_, value) => updates.add(value.pictureStoryExpression),
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    await save(completed('missing-event'));
    await Future<void>.delayed(Duration.zero);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      1,
    );
    expect(updates.last, 1);
    final report = buildDailyStats(days: 1, now: day).single;
    expect(report.pictureStoryExpressionCount, 1);
    expect(report.pictureStoryExpressionDurationSeconds, 120);
    expect(report.durationSeconds, 120);
    expect(HiveBoxes.learningActivities, isEmpty);
    expect(
      LearningActivityRepository().getAll().single.completedAt,
      day.add(const Duration(minutes: 2)),
    );
  });

  test('补齐只接受已知完成时间，重讲沿用首遍时长，已有事件优先且不重复', () async {
    final record = completed('retold');
    final original = record.currentTake;
    record.retellingStateJson = jsonEncode(
      PictureStoryRetellingState(
        archived: [original],
        currentId: 'retold:second',
        currentStartedAt: day.add(const Duration(days: 1)),
        currentCompletedAt: day.add(const Duration(days: 1, minutes: 5)),
      ).toJson(),
    );
    record.totalDurationSeconds = 300;
    await save(record);
    await save(completed('draft')..status = 'draft');
    await save(completed('unknown-time')..completedAt = null);
    await save(completed('other', profileId: 'another-profile'));
    await save(completed('broken')..retellingStateJson = '{broken');
    final boxName = HiveBoxes.pictureStoryPractice.name;
    await HiveBoxes.pictureStoryPractice.close();
    HiveBoxes.pictureStoryPractice =
        await Hive.openBox<PictureStoryPracticeRecord>(boxName);
    final repository = LearningActivityRepository();
    var activity = repository.getAll().single;
    expect(activity.id, 'picture-story:retold');
    expect(activity.durationSeconds, 120);
    expect(activity.completedAt, original.completedAt);
    await repository.record(
      id: activity.id,
      activityType: LearningActivityType.pictureStoryExpression,
      totalItems: 1,
      successfulItems: 1,
      starsEarned: 0,
      durationSeconds: 90,
      completedAt: activity.completedAt,
    );
    activity = repository.getAll().single;
    expect(activity.durationSeconds, 90);
    expect(
      buildDailyStats(days: 1, now: day).single.pictureStoryExpressionCount,
      1,
    );
    expect(
      buildDailyStats(
        days: 1,
        now: day.add(const Duration(days: 1)),
      ).single.pictureStoryExpressionCount,
      0,
    );
    expect(HiveBoxes.learningActivities, hasLength(1));
  });
}
