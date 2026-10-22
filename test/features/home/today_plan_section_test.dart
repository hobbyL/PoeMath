import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
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

  for (final scale in [1.0, 1.7]) {
    testWidgets('今日任务卡片保持高度、独立调整计划；字号 $scale', (tester) async {
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
            builder: (context, _) => Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const TodayPlanSection(),
                    AppTile(
                      key: const ValueKey('baseline'),
                      icon: Icons.menu_book_outlined,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: '标准任务卡片',
                      subtitle: '开始这一项',
                    ),
                  ],
                ),
              ),
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
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今日任务 0/1'), findsOneWidget);
      expect(find.textContaining('年级'), findsNothing);
      expect(find.textContaining('每天首次生成后固定'), findsNothing);
      final taskCard = find.ancestor(
        of: find.text('新学 · 静夜思'),
        matching: find.byType(ColoredCard),
      );
      final arrow = find.descendant(
        of: taskCard,
        matching: find.byIcon(Icons.chevron_right),
      );
      final adjust = find.widgetWithText(TextButton, '调整计划');
      final cardRect = tester.getRect(taskCard);
      final arrowRect = tester.getRect(arrow);
      final adjustRect = tester.getRect(adjust);
      expect(arrowRect.top, tester.getTopLeft(find.text('新学 · 静夜思')).dy);
      expect(arrowRect.left, greaterThan(cardRect.center.dx));
      expect(adjustRect.top, closeTo(arrowRect.bottom, 1));
      expect(cardRect.contains(adjustRect.topLeft), isTrue);
      expect(cardRect.contains(adjustRect.bottomRight), isTrue);
      if (scale == 1) {
        expect(
          cardRect.height,
          tester.getSize(find.byKey(const ValueKey('baseline'))).height,
          reason: '调整计划移入卡内后不能撑高正常字号的任务卡片',
        );
      }
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
      expect(launched, 1, reason: '调整计划不能误触任务导航');
      await tester.tap(find.byTooltip('增加复习'));
      await tester.pumpAndSettle();
      final up = find.widgetWithText(TextButton, '上移').last;
      await tester.ensureVisible(up);
      await tester.tap(up);
      await tester.pumpAndSettle();
      // 已移除「保存计划」按钮：调整即生效，关闭 sheet 时统一落盘。
      expect(find.text('保存计划'), findsNothing);
      // 关闭 sheet 触发落盘。用 `Navigator.maybePop` 走 PopScope 的
      // onPopInvokedWithResult（与系统返回/手势关闭同一条路径），但不像
      // `handlePopRoute()` 那样依赖全局路由栈 —— 后者在并发测试下会被
      // 其他用例的路由状态干扰。
      await tester.runAsync(() async {
        final navigator = Navigator.of(
          tester.element(find.text('调整每日计划')),
        );
        await navigator.maybePop();
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
  }

  for (final state in ['已完成', '内容失效', '无任务']) {
    testWidgets('今日任务$state时仅保留一个可用的调整入口', (tester) async {
      final plan = TodayPlan(
        dateKey: '2026-10-16',
        profileId: 'default',
        grade: 2,
        semester: '上',
        tasks: state == '无任务'
            ? []
            : [
                TodayPlanTask(
                  kind: TodayTaskKind.newPoem,
                  targetId: 'missing-first',
                  title: '第一项',
                  baseline: 0,
                  completed: state == '已完成',
                ),
                const TodayPlanTask(
                  kind: TodayTaskKind.newPoem,
                  targetId: 'missing-second',
                  title: '第二项',
                  baseline: 0,
                ),
              ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [todayPlanProvider.overrideWith((ref) async => plan)],
          child: const MaterialApp(
            home: Scaffold(body: TodayPlanSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final adjust = find.widgetWithText(TextButton, '调整计划');
      expect(adjust, findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      if (state != '无任务') {
        expect(
          find.ancestor(of: adjust, matching: find.byType(ColoredCard)),
          findsOneWidget,
        );
      }
      await tester.runAsync(() async {
        await tester.tap(adjust);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('调整每日计划'), findsOneWidget);
      await tester.runAsync(() async {
        await Navigator.of(tester.element(find.text('调整每日计划'))).maybePop();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await drainHiveWritesForTesting(tester);
    });
  }

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
    // 记录 provider 被读取的次数：`_open` 收尾会 `invalidate` 它，
    // 失效后的重读可作为「`_open` 整条异步链已跑完」的观测点。
    var planReads = 0;
    final container = ProviderContainer(
      overrides: [
        todayPlanProvider.overrideWith((ref) async {
          planReads++;
          return plan;
        }),
      ],
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
    // `_open` 在结算之后还要跑 `checkAchievements`（Hive 写入），最后
    // `ref.invalidate(todayPlanProvider)` 收尾。不等它跑完，这段续体可能
    // 在 tearDown 关闭 Hive 之后才恢复 —— CI 上因此报
    // 「Box has already been closed」，并对已销毁的 Scaffold 弹 SnackBar。
    // provider 失效后的重读就是「整条链已到收尾」的观测点。
    final readsBefore = planReads;
    for (var i = 0; i < 100 && planReads == readsBefore; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      planReads,
      greaterThan(readsBefore),
      reason: '_open 未走到收尾的 invalidate',
    );
    // 首次掌握会解锁成就，`_open` 随即弹出自动关闭的庆祝弹窗
    // （内部是 1.5s 的 `Future.delayed`）。推过去，否则测试结束时
    // 会留下 pending timer。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(ReviewRepository().completedReviewCount('poem'), 1);
    expect(ReviewRepository().get('poem')?.isCompleted, isTrue);
    expect(
      PoemProgressRepository().get('poem')?.status,
      LearningStatus.mastered,
    );
    expect(PoemProgressRepository().get('poem')?.firstMasteredAt, isNotNull);
    await drainHiveWritesForTesting(tester);
    expect(UserStatsRepository().get().poemsMastered, 1);
    expect(tester.takeException(), isNull);
  });
}
