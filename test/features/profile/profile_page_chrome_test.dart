// test/features/profile/profile_page_chrome_test.dart
//
// 「我的」页顶部结构：无 AppBar、无「我的」大标题，设置入口是悬浮在
// 右上角、不随内容滚动的按钮。
//
// 背景：该页原先用 `AppBar(title: Text('我的')) + actions[设置]`。顶部这条
// 导航栏只放一个标题、不承载任何交互，却占掉一整条高度；作为 4 个 Tab
// 之一也不需要返回按钮，因此整条去掉，设置改悬浮。
//
// ── 写法约束（沿用 hive_key_recovery_notice_test 里踩出来的两条）──────
//
// ① 必须 override `dayKeyProvider` 为静态值：`ProfilePage` 经
//    `userStatsProvider` / `streakProvider` 依赖它，而 `DayKeyNotifier.build`
//    会起一个 30 秒 `Timer.periodic`，让 tearDown 的 `HiveBoxes.close()` 挂到
//    超时（用例体已跑完却报挂起）。
// ② 必须用 `pump(Duration)` 推进 fake clock：body 是 `AnimatedPageBody`，
//    每个子项排了 `Future.delayed` 入场动画，只 pump 一帧会留下 pending
//    timer 被判失败。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/features/profile/profile_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [staticDayKeyOverride()],
      child: const MaterialApp(home: ProfilePage()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('顶部无 AppBar，「我的」不再作为标题显示', (tester) async {
    await _pump(tester);

    expect(find.byType(AppBar), findsNothing);
    // 本页正文里没有「我的」字样，因此整棵树上都不该出现。
    expect(find.text('我的'), findsNothing);
  });

  testWidgets('设置按钮悬浮右上角且不随内容滚动', (tester) async {
    await _pump(tester);

    final settingsButton = find.widgetWithIcon(IconButton, Icons.settings_rounded);
    expect(settingsButton, findsOneWidget);

    final before = tester.getTopRight(settingsButton);

    // 滚动到底：按钮在同一屏幕位置不动（不是 ListView 的一项）。
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump(const Duration(seconds: 1));

    expect(settingsButton, findsOneWidget);
    expect(tester.getTopRight(settingsButton), before);
  });

  testWidgets('设置按钮点击导航到设置页', (tester) async {
    // 真实挂一个只含设置路由的 router，断言 push 的目标路径，
    // 而不是断言 `AppRoutes.settings` 常量等于自己。
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ProfilePage()),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) => const Scaffold(body: Text('设置页占位')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [staticDayKeyOverride()],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.settings_rounded),
    );
    await tester.pumpAndSettle();

    final matched = find.text('设置页占位').evaluate().isNotEmpty;
    // ignore: avoid_print
    print('>>> 占位页可见=$matched path=${router.routerDelegate.currentConfiguration.uri}');
    expect(find.text('设置页占位'), findsOneWidget);
  });
}
