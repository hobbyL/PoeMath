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
// ② 顶部持续流动，使用有界 pump 推进入场动画；仅跳转到静态页面后
//    才使用 pumpAndSettle，避免等待永不停止的顶部动效。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/profile/profile_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 914),
  double textScale = 1,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        staticDayKeyOverride(),
        userStatsProvider.overrideWithValue(
          UserStats(profileId: 'default', level: 7, totalStars: 12345),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.resolve(
          subject: AppSubject.poem,
          brightness: brightness,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 32),
            viewPadding: const EdgeInsets.only(top: 32),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: PageAnimationScope(enabled: false, child: child!),
        ),
        home: const ProfilePage(),
      ),
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
    await _pump(tester, size: const Size(411, 400));

    final settingsButton = find.widgetWithIcon(
      IconButton,
      Icons.settings_rounded,
    );
    expect(settingsButton, findsOneWidget);

    final before = tester.getTopRight(settingsButton);

    // 滚动到底：按钮在同一屏幕位置不动（不是 ListView 的一项）。
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(settingsButton, findsOneWidget);
    expect(tester.getTopRight(settingsButton), before);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('个人页流光与下拉放大遵循系统减少动态效果：$reduceMotion', (tester) async {
      await _pump(tester, reduceMotion: reduceMotion);
      final background = find.byKey(
        const ValueKey('profile-header-background'),
      );
      Future<Uint8List> pixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(background);
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        }))!;
      }

      final first = await pixels();
      await tester.pump(const Duration(milliseconds: 1500));
      final second = await pixels();
      expect(listEquals(first, second), reduceMotion);
      final before = tester.getRect(background);
      final gesture = await tester.startGesture(before.center);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      final pulled = tester.getRect(background);
      expect(pulled.top, closeTo(0, .01));
      if (reduceMotion) {
        expect(pulled, before);
      } else {
        expect(pulled.height, greaterThan(before.height));
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('profile-header-content')))
              .dy,
          closeTo((pulled.top + 32 + pulled.bottom) / 2, .01),
        );
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('个人页横竖屏及大字号完整展示等级和星星', (tester) async {
    for (final (size, scale, brightness) in [
      (const Size(320, 640), 2.0, Brightness.light),
      (const Size(914, 411), 2.0, Brightness.dark),
    ]) {
      await _pump(tester, size: size, textScale: scale, brightness: brightness);
      final background = tester.getRect(
        find.byKey(const ValueKey('profile-header-background')),
      );
      expect(background.left, 0);
      expect(background.right, size.width);
      for (final label in ['诗仙', '12345 颗星星']) {
        final bounds = tester.getRect(find.text(label));
        expect(background.contains(bounds.topLeft), isTrue);
        expect(background.contains(bounds.bottomRight), isTrue);
      }
      expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('设置页占位'), findsOneWidget);
  });
}
