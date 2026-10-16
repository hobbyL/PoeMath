import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/data/repositories/today_plan_repository.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/providers/today_plan_providers.dart';
import 'package:poemath/features/home/today_plan_section.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_practice_score.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  testWidgets('今日任务直达练习，计划数量与顺序可调整；窄屏大字号可用', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.poems.put(
        'poem',
        Poem(
          id: 'poem',
          title: '静夜思',
          author: '李白',
          dynasty: '唐',
          content: '床前明月光',
          pinyin: '',
          layer: 'core',
          grade: 4,
          semester: '下',
        ),
      );
    });
    const plan = TodayPlan(
      dateKey: '2026-10-16',
      profileId: 'default',
      grade: 4,
      semester: '下',
      tasks: [
        TodayPlanTask(
          kind: TodayTaskKind.newPoem,
          targetId: 'poem',
          title: '静夜思',
          baseline: 0,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [todayPlanProvider.overrideWith((ref) async => plan)],
    );
    addTearDown(container.dispose);
    var launched = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: TodayPlanSection()),
          ),
        ),
        GoRoute(
          path: AppRoutes.poemReciteOf('poem'),
          builder: (context, _) {
            launched++;
            return Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: const Text('返回任务'),
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日任务 0/1'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('新学 · 静夜思'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(launched, 1);
    await tester.tap(find.text('返回任务'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('调整计划'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('调整每日计划'), findsOneWidget);
    await tester.tap(find.byTooltip('增加复习'));
    await tester.pumpAndSettle();
    final up = find.widgetWithText(TextButton, '上移').last;
    await tester.ensureVisible(up);
    await tester.tap(up);
    await tester.pumpAndSettle();
    // 已移除「保存计划」按钮：调整即生效，关闭 sheet 时统一落盘。
    expect(find.text('保存计划'), findsNothing);
    // 用系统返回关闭 sheet —— 走 PopScope 的落盘路径（同时覆盖手势关闭）。
    await tester.runAsync(() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    final config = TodayPlanRepository().config;
    expect(config.reviewCount, 3);
    expect(
      config.order,
      [TodayTaskKind.review, TodayTaskKind.newPoem, TodayTaskKind.mistake],
    );
    expect(find.text('今日任务 0/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('今日复习直接完成第五轮，同步真实复习事件、掌握日期与统计', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.poems.put(
        'poem',
        Poem(
          id: 'poem',
          title: '静夜思',
          author: '李白',
          dynasty: '唐',
          content: '床前明月光',
          pinyin: '',
          layer: 'core',
          grade: 4,
          semester: '下',
        ),
      );
      await PoemProgressRepository().save(
        PoemProgress(
          poemId: 'poem',
          profileId: 'default',
          status: LearningStatus.reviewing,
          studyCount: 1,
        ),
      );
      await ReviewRepository().save(
        ReviewSchedule(
          poemId: 'poem',
          profileId: 'default',
          currentRound: 4,
          nextReviewDate: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
    });
    const plan = TodayPlan(
      dateKey: '2026-10-16',
      profileId: 'default',
      grade: 4,
      semester: '下',
      tasks: [
        TodayPlanTask(
          kind: TodayTaskKind.review,
          targetId: 'poem',
          title: '静夜思',
          baseline: 0,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [todayPlanProvider.overrideWith((ref) async => plan)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: TodayPlanSection()),
          ),
        ),
        GoRoute(
          path: AppRoutes.poemQuizOf('poem'),
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () {
                container.read(lastPracticeScoreProvider.notifier).state = 1;
                context.pop(PoemPracticeResult.quizPassed);
              },
              child: const Text('提交通过'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('复习 · 静夜思'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final settled = HiveBoxes.userStats.watch().first;
      await tester.tap(find.text('提交通过'));
      await settled;
    });
    await tester.pumpAndSettle();
    expect(ReviewRepository().completedReviewCount('poem'), 1);
    expect(ReviewRepository().get('poem')?.isCompleted, isTrue);
    expect(
      PoemProgressRepository().get('poem')?.status,
      LearningStatus.mastered,
    );
    expect(PoemProgressRepository().get('poem')?.firstMasteredAt, isNotNull);
    expect(UserStatsRepository().get().poemsMastered, 1);
    expect(tester.takeException(), isNull);
  });
}
