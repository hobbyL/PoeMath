import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/home/home_check_in_header.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

final _background = find.byKey(const ValueKey('home-check-in-background'));

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 914),
  double textScale = 1,
  EdgeInsets safeInsets = const EdgeInsets.only(top: 32),
  bool pageAnimations = false,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  bool checkedIn = false,
  int streak = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        staticDayKeyOverride(),
        streakProvider.overrideWithValue(streak),
        isCheckedInProvider.overrideWithValue(checkedIn),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safeInsets,
            viewPadding: safeInsets,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            accessibleNavigation: accessibleNavigation,
          ),
          child: PageAnimationScope(enabled: pageAnimations, child: child!),
        ),
        home: const HomePage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
  // 在断言之前排空初始化写链，失败时也不会使 Hive tearDown 挂起。
  await drainHiveWritesForTesting(tester);
  // 待打卡背景持续流动，固定帧推进只等待入场与异步数据完成。
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('顶部背景贴边、前景避开状态栏，不重复应用名', (tester) async {
    await _pump(tester);

    expect(find.byType(AppBar), findsNothing);
    // 应用名只在 AppBar 里出现过，去掉后全树不应再有。
    expect(find.text('韵算'), findsNothing);
    final background = tester.getRect(_background);
    expect(background.topLeft, Offset.zero);
    expect(background.right, 411);
    expect(background.height, lessThanOrEqualTo(160));
    expect(tester.getTopLeft(find.text('今日待打卡')).dy, greaterThan(32));
    final card = tester.widget<ColoredCard>(
      find.descendant(of: _background, matching: find.byType(ColoredCard)),
    );
    expect(card.borderRadius, BorderRadius.zero);
    expect(card.boxShadow, isNull);
    expect(
      tester.getCenter(find.widgetWithText(FilledButton, '打卡')).dy,
      closeTo(
        tester
            .getCenter(find.byKey(const ValueKey('home-check-in-summary')))
            .dy,
        .01,
      ),
    );
  });

  testWidgets('等级徽章显示在打卡卡片内，与打卡状态同一行', (tester) async {
    await _pump(tester);

    // 默认等级名（未学习时 level == 0）。
    final defaultLevel = UserStats(profileId: 'default').levelName;
    expect(defaultLevel, UserStats.levelNames.first);
    expect(find.text(defaultLevel), findsOneWidget);

    // 徽章与「今日待打卡」在同一张卡片内 —— 断言两者的纵向中心接近，
    // 而不是只断言「都存在于树上」。
    final badge = tester.getCenter(find.text(defaultLevel));
    final status = tester.getCenter(find.text('今日待打卡'));
    expect((badge.dy - status.dy).abs(), lessThan(20));

    // 背景独立拉伸，徽章和状态在同一个前景区域。
    expect(
      find.ancestor(
        of: find.text(defaultLevel),
        matching: find.byType(HomeCheckInHeader),
      ),
      findsOneWidget,
    );
  });

  for (final pageAnimations in [true, false]) {
    testWidgets('下拉与回弹时信息和按钮随卡片高度保持居中：$pageAnimations', (tester) async {
      await _pump(tester, pageAnimations: pageAnimations);
      final before = tester.getRect(_background);
      final statusSize = tester.getSize(find.text('今日待打卡'));
      final button = find.widgetWithText(FilledButton, '打卡');
      final buttonSize = tester.getSize(button);
      final summary = find.byKey(const ValueKey('home-check-in-summary'));
      final summaryRect = tester.getRect(summary);
      final safeTop = MediaQuery.paddingOf(
        tester.element(find.byType(HomePage)),
      ).top;
      void expectCentered() {
        final background = tester.getRect(_background);
        // 屏幕状态栏之外的可用背景区域，上下留白应相等。
        final contentCenter =
            (background.top + safeTop + background.bottom) / 2;
        expect(tester.getCenter(summary).dy, closeTo(contentCenter, .01));
        expect(tester.getCenter(button).dy, closeTo(contentCenter, .01));
        expect(tester.getSize(summary), summaryRect.size);
        expect(tester.getSize(button), buttonSize);
      }

      expectCentered();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final gesture = await tester.startGesture(before.center);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      expectCentered();
      await gesture.moveBy(const Offset(0, 140));
      await tester.pump(const Duration(milliseconds: 16));
      final pulled = tester.getRect(_background);
      expect(scroll.position.pixels, lessThan(-30));
      expect(pulled.top, closeTo(0, .01));
      expect(pulled.left, lessThanOrEqualTo(0));
      expect(pulled.right, greaterThanOrEqualTo(411));
      expect(pulled.height, greaterThan(before.height + 30));
      expect(tester.getSize(find.text('今日待打卡')), statusSize);
      expect(tester.getTopLeft(summary).dy, greaterThan(summaryRect.top));
      expectCentered();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectCentered();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      final restored = tester.getRect(_background);
      expect(restored.top, closeTo(before.top, .01));
      expect(restored.size, before.size);
      expect(scroll.position.pixels, closeTo(0, .01));
      expect(tester.getTopLeft(summary).dy, closeTo(summaryRect.top, .01));
      expectCentered();
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('上滑时下方内容覆盖慢速上移的背景，后续模块可达', (tester) async {
    await _pump(tester);
    SystemUiOverlayStyle? statusBarStyle() => tester
        .binding
        .renderViews
        .first
        .debugLayer!
        .find<SystemUiOverlayStyle>(const Offset(205, 16));
    expect(statusBarStyle()?.statusBarIconBrightness, Brightness.light);
    final before = tester.getRect(_background);
    final summary = find.byKey(const ValueKey('home-check-in-summary'));
    final summaryBefore = tester.getTopLeft(summary);
    final goalBefore = tester.getTopLeft(find.text('打卡目标 · 诗词与口算'));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(120);
    await tester.pump();
    final after = tester.getRect(_background);
    expect(before.top - after.top, greaterThan(0));
    expect(before.top - after.top, lessThan(120));
    expect(summaryBefore.dy - tester.getTopLeft(summary).dy, closeTo(120, .01));
    expect(
      goalBefore.dy - tester.getTopLeft(find.text('打卡目标 · 诗词与口算')).dy,
      closeTo(120, .01),
    );
    // 内容已抵达状态栏，视差背景仍在其后方：前方的浅底必须接管图标颜色。
    scroll.position.jumpTo(before.height);
    await tester.pump();
    expect(tester.getRect(_background).bottom, greaterThan(32));
    expect(statusBarStyle()?.statusBarIconBrightness, Brightness.dark);
    await tester.ensureVisible(find.text('快捷入口'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('快捷入口').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final accessibility in [false, true]) {
    testWidgets('系统减少动态效果/无障碍导航时禁用拉伸：$accessibility', (tester) async {
      await _pump(
        tester,
        reduceMotion: !accessibility,
        accessibleNavigation: accessibility,
      );
      final before = tester.getRect(_background);
      await tester.dragFrom(
        tester.getCenter(_background),
        const Offset(0, 180),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_background), before);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, 0);
      scroll.position.jumpTo(100);
      await tester.pump();
      expect(tester.getTopLeft(_background).dy, -100);
    });
  }

  for (final size in [
    const Size(320, 640),
    const Size(411, 914),
    const Size(914, 411),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('窄屏/横屏与大字号保持安全区、内容完整和按钮可达：$size × $scale', (tester) async {
        final landscape = size.width > size.height;
        final safe = landscape
            ? const EdgeInsets.only(left: 32, right: 24)
            : const EdgeInsets.only(top: 32);
        await _pump(
          tester,
          size: size,
          textScale: scale,
          safeInsets: safe,
          streak: 3650,
        );
        final status = tester.getRect(find.text('今日待打卡'));
        final streak = tester.getRect(find.text('3650'));
        final button = find.widgetWithText(FilledButton, '打卡');
        final rect = tester.getRect(button);
        for (final area in [status, streak, rect]) {
          expect(area.left, greaterThanOrEqualTo(safe.left));
          expect(area.right, lessThanOrEqualTo(size.width - safe.right));
          expect(area.top, greaterThanOrEqualTo(safe.top));
        }
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(button.hitTestable(), findsOneWidget);
        expect(
          rect.center.dy,
          closeTo(
            tester
                .getCenter(find.byKey(const ValueKey('home-check-in-summary')))
                .dy,
            .01,
          ),
        );
        expect(tester.getRect(_background).width, size.width);
        await tester.ensureVisible(find.text('快捷入口'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('快捷入口').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('已打卡状态在新背景中保留，等级和连续天数完整', (tester) async {
    await _pump(tester, checkedIn: true, streak: 12);
    expect(find.text('今日已打卡 ✓'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text(UserStats.levelNames.first), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '打卡'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
