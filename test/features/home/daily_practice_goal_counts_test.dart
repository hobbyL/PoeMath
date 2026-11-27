import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/domain/daily_goal_activity.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/home/providers/today_plan_providers.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  final today = DateTime(2026, 11, 27, 12);

  ProviderContainer containerFor(String day) {
    final container = ProviderContainer(overrides: [staticDayKeyOverride(day)]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> poem(
    String id,
    DateTime completedAt, {
    String poemId = 'poem',
    LearningActivityType type = LearningActivityType.poemRecitation,
  }) async {
    await PoemProgressRepository().recordStudy(
      poemId,
      activityId: id,
      completedAt: completedAt,
    );
    await LearningActivityRepository().record(
      id: id,
      activityType: type,
      totalItems: 1,
      successfulItems: 1,
      starsEarned: 0,
      durationSeconds: 60,
      completedAt: completedAt,
      poemId: poemId,
    );
  }

  Future<PictureStoryPracticeRecord> picture(
    String id,
    DateTime completedAt, {
    String promptId = 'prompt',
    int version = 1,
    String status = 'completed',
  }) async {
    final record = PictureStoryPracticeRecord(
      id: id,
      profileId: ProfileScope.currentId,
      promptId: promptId,
      promptVersion: version,
      startedAt: completedAt.subtract(const Duration(minutes: 2)),
      completedAt: completedAt,
      status: status,
      segmentsJson: '[]',
      answerText: '小猫在看书。',
      totalDurationSeconds: 120,
    );
    await HiveBoxes.pictureStoryPractice.put(
      ProfileScope.key('picture_story:$id'),
      record,
    );
    return record;
  }

  test('诗词不同模式与旧别名共用限制，真实练习仍全部保存', () async {
    await HiveBoxes.learningActivities.put(
      ProfileScope.key('legacy-alias'),
      LearningActivity(
        id: 'legacy-alias',
        profileId: ProfileScope.currentId,
        activityType: LearningActivityType.poemRecitation.name,
        totalItems: 1,
        successfulItems: 1,
        starsEarned: 0,
        durationSeconds: 60,
        completedAt: DateTime(2026, 11, 26),
        poemId: 'poem_exp_661',
      ),
    );
    await poem(
      'quiz',
      today,
      poemId: 'poem_core_004',
      type: LearningActivityType.poemQuiz,
    );
    await poem(
      'dictation',
      today,
      poemId: 'poem_core_004',
      type: LearningActivityType.poemDictation,
    );
    await poem(
      'read-along',
      today,
      poemId: 'new',
      type: LearningActivityType.readAlong,
    );
    await poem('recitation', today, poemId: 'new');
    await poem('future', DateTime(2026, 11, 28), poemId: 'future');

    final container = containerFor('2026-11-27');
    expect(container.read(todayPoemCountProvider), 1);
    expect(LearningActivityRepository().forPoem('poem_core_004'), hasLength(3));
    expect(PoemProgressRepository().get('poem_core_004')!.studyCount, 2);
    expect(PoemProgressRepository().get('new')!.studyCount, 2);
  });

  test('两类练习每天重复，第六天恢复且再次限制四天', () async {
    for (var offset = 0; offset <= 6; offset++) {
      final date = DateTime(2026, 11, 27 + offset);
      await poem('poem-$offset', date);
      await picture('picture-$offset', date);
    }
    for (final (day, expected) in [
      ('2026-11-27', 1),
      ('2026-11-28', 0),
      ('2026-12-01', 0),
      ('2026-12-02', 1),
      ('2026-12-03', 0),
    ]) {
      final container = containerFor(day);
      expect(container.read(todayPoemCountProvider), expected, reason: day);
      expect(
        container
            .read(todayLearningActivityCountsProvider)
            .pictureStoryExpression,
        expected,
        reason: day,
      );
    }
    expect(PoemProgressRepository().get('poem')!.studyCount, 7);
    expect(HiveBoxes.pictureStoryPractice, hasLength(7));
  });

  test('看图按题目去重，换版本不能多计；活动漏写仍恢复，报表保留实际次数', () async {
    await picture('yesterday', DateTime(2026, 11, 26));
    await picture('version-2', today, version: 2);
    await picture('repeat', today, version: 2);
    await picture('new-a', today, promptId: 'new');
    await picture('new-b', today, promptId: 'new');
    await picture('draft', today, promptId: 'draft', status: 'draft');
    await picture('future', DateTime(2026, 11, 28), promptId: 'future');
    final container = containerFor('2026-11-27');
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      1,
    );
    expect(
      buildDailyStats(days: 1, now: today).single.pictureStoryExpressionCount,
      4,
    );
    expect(HiveBoxes.learningActivities, isEmpty);
  });

  test('重讲不移动首次计入日，缺完成时间和缺题目身份的活动不计入', () async {
    final record = await picture('retold', DateTime(2026, 11, 22));
    final original = record.currentTake;
    record.retellingStateJson = jsonEncode(
      PictureStoryRetellingState(
        archived: [original],
        currentId: 'retold:second',
        currentStartedAt: today,
        currentCompletedAt: today,
      ).toJson(),
    );
    await record.save();
    final unknown = await picture('unknown-time', today, promptId: 'unknown');
    unknown.completedAt = null;
    await unknown.save();
    await LearningActivityRepository().record(
      id: 'picture-story:missing-record',
      activityType: LearningActivityType.pictureStoryExpression,
      totalItems: 1,
      successfulItems: 1,
      starsEarned: 0,
      durationSeconds: 60,
      completedAt: today,
    );
    final container = containerFor('2026-11-27');
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      0,
    );
    expect(
      containerFor('2026-11-22')
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      1,
    );
  });

  test('只有旧诗词进度时使用已知首末日期，读取不改写存储', () async {
    final repo = PoemProgressRepository();
    for (final (id, first) in [
      ('recent', DateTime(2026, 11, 26)),
      ('eligible', DateTime(2026, 11, 22)),
      ('unknown-first', null),
    ]) {
      await repo.save(
        PoemProgress(
          poemId: id,
          profileId: ProfileScope.currentId,
          firstStudiedAt: first,
          lastStudiedAt: today,
          studyCount: 2,
        ),
      );
    }
    final container = containerFor('2026-11-27');
    expect(container.read(todayPoemCountProvider), 2);
    expect(repo.get('recent')!.studyCount, 2);
    expect(repo.get('recent')!.lastStudiedAt, today);
    expect(HiveBoxes.learningActivities, isEmpty);
  });

  test('完成写入、档案切换与恢复后的失效会更新两类目标', () async {
    final container = containerFor('2026-11-27');
    final poemUpdates = <int>[];
    final pictureUpdates = <int>[];
    final poemSub = container.listen(
      todayPoemCountProvider,
      (_, value) => poemUpdates.add(value),
      fireImmediately: true,
    );
    final pictureSub = container.listen(
      todayLearningActivityCountsProvider,
      (_, value) => pictureUpdates.add(value.pictureStoryExpression),
      fireImmediately: true,
    );
    addTearDown(poemSub.close);
    addTearDown(pictureSub.close);
    await Future<void>.delayed(Duration.zero);
    await poem('first', today);
    await picture('first', today);
    await Future<void>.delayed(Duration.zero);
    expect(poemUpdates.last, 1);
    expect(pictureUpdates.last, 1);

    ProfileScope.switchTo('other-child');
    await Future<void>.delayed(Duration.zero);
    expect(poemUpdates.last, 0);
    expect(pictureUpdates.last, 0);
    await poem('other-yesterday', DateTime(2026, 11, 26));
    await poem('other-today', today);
    await picture('other-yesterday', DateTime(2026, 11, 26));
    await picture('other-today', today);
    await Future<void>.delayed(Duration.zero);
    expect(poemUpdates.last, 0);
    expect(pictureUpdates.last, 0);

    ProfileScope.reset();
    await Future<void>.delayed(Duration.zero);
    expect(poemUpdates.last, 1);
    expect(pictureUpdates.last, 1);
    await HiveBoxes.learningActivities.clear();
    await HiveBoxes.poemProgress.clear();
    await HiveBoxes.pictureStoryPractice.clear();
    invalidateAllHiveProviders(container.invalidate);
    expect(container.read(todayPoemCountProvider), 0);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      0,
    );
  });

  testWidgets('跨日后两类目标重算，不沿用前一天的计数', (tester) async {
    await tester.runAsync(() async {
      await poem('first', today);
      await poem('next-day', DateTime(2026, 11, 28));
      await picture('first', today);
      await picture('next-day', DateTime(2026, 11, 28));
    });
    final container = containerFor('2026-11-27');
    expect(container.read(todayPoemCountProvider), 1);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      1,
    );
    container.read(dayKeyProvider.notifier).state = '2026-11-28';
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(todayPoemCountProvider), 0);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      0,
    );
  });

  for (final goal in [
    DailyGoalActivity.poem,
    DailyGoalActivity.pictureStoryExpression,
  ]) {
    testWidgets('${goal.label}近期重复不满足打卡条件，但仍可进入自由练习', (tester) async {
      await tester.runAsync(() async {
        await poem('yesterday', DateTime(2026, 11, 26));
        await poem('today', today);
        await picture('yesterday', DateTime(2026, 11, 26));
        await picture('today', today);
      });
      final isPoem = goal == DailyGoalActivity.poem;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomePage()),
          GoRoute(
            path: isPoem ? AppRoutes.poemTab : AppRoutes.chineseTab,
            builder: (_, __) => const Scaffold(body: Text('自由练习入口')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staticDayKeyOverride('2026-11-27'),
            dailyGoalTypesProvider.overrideWithValue({goal}),
            dailyPoemGoalProvider.overrideWithValue(1),
            todayPlanProvider.overrideWith(
              (ref) async => const TodayPlan(
                dateKey: '2026-11-27',
                profileId: 'default',
                grade: 1,
                semester: '上',
                tasks: [],
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // 待打卡页头持续播放提醒动效，等待有限帧而不是等待所有动画停止。
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(isPoem ? '诗词 0/1 首' : '看图表达 0/1 次'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '打卡'), findsNothing);
      expect(find.textContaining('5 天内只计入一天的目标'), findsOneWidget);
      final action = find.widgetWithText(
        FilledButton,
        isPoem ? '去学诗词' : '去看图表达',
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('自由练习入口'), findsOneWidget);
      expect(HiveBoxes.checkIns, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }

  test('认字、写字与英语保持按活动计数', () async {
    final repo = LearningActivityRepository();
    for (final type in [
      LearningActivityType.textbookRecognition,
      LearningActivityType.textbookWriting,
      LearningActivityType.englishPractice,
      LearningActivityType.englishSpeaking,
    ]) {
      for (var i = 0; i < 2; i++) {
        await repo.record(
          id: '${type.name}:$i',
          activityType: type,
          totalItems: 1,
          successfulItems: 1,
          starsEarned: 0,
          durationSeconds: 60,
          completedAt: today,
        );
      }
    }
    final counts = containerFor('2026-11-27')
        .read(todayLearningActivityCountsProvider);
    expect(counts.textbookRecognition, 2);
    expect(counts.textbookWriting, 2);
    expect(counts.english, 4);
  });
}
