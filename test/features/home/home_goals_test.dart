import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/domain/daily_goal_activity.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/home/providers/today_plan_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final poem in [true, false]) {
    testWidgets('已完成练习清单仍显示真实打卡差额，进入${poem ? '诗词' : '口算'}', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomePage()),
          GoRoute(
            path: AppRoutes.poemTab,
            builder: (_, __) => const Scaffold(body: Text('诗词学习入口')),
          ),
          GoRoute(
            path: AppRoutes.mathTab,
            builder: (_, __) => const Scaffold(body: Text('数学学习入口')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staticDayKeyOverride(),
            dailyPoemGoalProvider.overrideWithValue(2),
            dailyMathGoalProvider.overrideWithValue(10),
            todayPoemCountProvider.overrideWithValue(1),
            todayMathCountProvider.overrideWithValue(5),
            todayPlanProvider.overrideWith(
              (ref) async => const TodayPlan(
                dateKey: '2026-11-04',
                profileId: 'default',
                grade: 1,
                semester: '上',
                tasks: [
                  TodayPlanTask(
                    kind: TodayTaskKind.newPoem,
                    targetId: 'old',
                    title: '已完成内容',
                    baseline: 0,
                    completed: true,
                  ),
                ],
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('今日练习清单 1/1'), findsOneWidget);
      expect(find.text('还差 1 首 · 去学诗词'), findsOneWidget);
      expect(find.text('还差 5 题 · 去练口算'), findsOneWidget);
      expect(find.text('今日学习目标 · 完成后可打卡'), findsOneWidget);
      final target = find.text(poem ? '还差 1 首 · 去学诗词' : '还差 5 题 · 去练口算');
      if (poem) {
        await tester.tap(find.text('去学诗词'));
        await tester.pumpAndSettle();
        expect(find.text('诗词学习入口'), findsOneWidget);
      } else {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.text('数学学习入口'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }

  for (final scenario in [
    (
      activity: DailyGoalActivity.textbookWriting,
      title: '写一写 0/1 次',
      action: '去写一写',
      section: 'textbook',
    ),
    (
      activity: DailyGoalActivity.pictureStoryExpression,
      title: '看图表达 0/1 次',
      action: '去看图表达',
      section: 'expression',
    ),
  ]) {
    testWidgets('${scenario.activity.label}目标进入对应语文分区', (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomePage()),
          GoRoute(
            path: AppRoutes.chineseTab,
            builder: (_, state) => Scaffold(
              body: Text('语文分区 ${state.uri.queryParameters['section']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staticDayKeyOverride(),
            dailyGoalTypesProvider.overrideWithValue({scenario.activity}),
            todayLearningActivityCountsProvider.overrideWithValue(
              const TodayLearningActivityCounts(),
            ),
            todayPlanProvider.overrideWith(
              (ref) async => const TodayPlan(
                dateKey: '2026-11-04',
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
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(scenario.title), findsOneWidget);
      await tester.ensureVisible(find.text(scenario.action));
      await tester.tap(find.text(scenario.action));
      await tester.pumpAndSettle();
      expect(find.text('语文分区 ${scenario.section}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }
}
