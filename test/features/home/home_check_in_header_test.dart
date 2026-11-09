import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/features/home/home_check_in_header.dart';

final _button = find.widgetWithText(FilledButton, '打卡');
final _background = find.byKey(const ValueKey('home-check-in-background'));

Future<ScrollController> _mount(
  WidgetTester tester, {
  bool animations = true,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  bool tickerEnabled = true,
  ValueNotifier<bool>? pending,
  VoidCallback? onPressed,
}) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  final pendingState = pending ?? ValueNotifier(true);
  if (pending == null) addTearDown(pendingState.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: PageAnimationScope(
        enabled: animations,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              accessibleNavigation: accessibleNavigation,
            ),
            child: Scaffold(
              body: TickerMode(
                enabled: tickerEnabled,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: pendingState,
                        builder: (context, pending, _) => HomeCheckInHeader(
                          scrollController: scroll,
                          pending: pending,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(pending ? '今日待打卡' : '今日已打卡'),
                              ),
                              if (pending)
                                HomeCheckInReminder(
                                  child: FilledButton(
                                    onPressed: onPressed ?? () {},
                                    child: const Text('打卡'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 1200),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(Duration.zero);
  await tester.pump();
  return scroll;
}

List<double> _entranceOpacities(WidgetTester tester) => tester
    .widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(HomeCheckInHeader),
        matching: find.byType(FadeTransition),
      ),
    )
    .map((fade) => fade.opacity.value)
    .toList();

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(_background);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final animations in [true, false]) {
    testWidgets('页面动画 $animations：卡片自身淡入和上移始终展示，背景贴边', (tester) async {
      await _mount(tester, animations: animations);
      final before = tester.getTopLeft(find.text('今日待打卡'));
      expect(tester.getTopLeft(_background), Offset.zero);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_entranceOpacities(tester), everyElement(inExclusiveRange(0, 1)));
      expect(tester.getTopLeft(_background), Offset.zero);
      await tester.pump(const Duration(milliseconds: 250));
      expect(_entranceOpacities(tester), everyElement(1));
      expect(tester.getTopLeft(find.text('今日待打卡')).dy, lessThan(before.dy));
      expect(tester.getTopLeft(_background), Offset.zero);
      expect(tester.takeException(), isNull);
    });

    testWidgets('页面动画 $animations：停留首页仍有光效和间歇呼吸，按钮居中可点', (tester) async {
      var taps = 0;
      await _mount(tester, animations: animations, onPressed: () => taps++);
      await tester.pump(const Duration(seconds: 1));
      final firstPeak = tester.getRect(_button);
      await tester.tap(_button);
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 1));
      final rest = tester.getRect(_button);
      expect(firstPeak.width, greaterThan(rest.width * 1.05));
      expect(firstPeak.center.dx, closeTo(rest.center.dx, .01));
      expect(firstPeak.center.dy, closeTo(rest.center.dy, .01));
      // 已超过旧版 2.6 秒的一次性入场，等待下一个提醒周期。
      await tester.pump(const Duration(seconds: 5));
      expect(tester.getRect(_button).width, closeTo(firstPeak.width, .01));
      final before = await _pixels(tester);
      final label = tester.getRect(find.text('今日待打卡'));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(listEquals(await _pixels(tester), before), isFalse);
      expect(tester.getRect(find.text('今日待打卡')), label);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('启用无障碍导航但未要求减少动态效果时，顶部背景继续播放', (tester) async {
    await _mount(tester, animations: false, accessibleNavigation: true);
    await tester.pump(const Duration(milliseconds: 350));
    final before = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(listEquals(await _pixels(tester), before), isFalse);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  for (final mode in ['减少动态效果', '不可见']) {
    testWidgets('$mode 时按钮保持静态、可操作', (tester) async {
      var taps = 0;
      await _mount(
        tester,
        animations: false,
        reduceMotion: mode == '减少动态效果',
        tickerEnabled: mode != '不可见',
        onPressed: () => taps++,
      );
      await tester.pump(const Duration(milliseconds: 350));
      final before = tester.getRect(_button);
      final pixels = await _pixels(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(tester.getRect(_button), before);
      expect(listEquals(await _pixels(tester), pixels), isTrue);
      expect(_entranceOpacities(tester), everyElement(1));
      await tester.tap(_button);
      expect(taps, 1);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('顶部滚出屏幕后停止，滚回时继续', (tester) async {
    final scroll = await _mount(tester);
    await tester.pump(const Duration(seconds: 1));
    scroll.jumpTo(250);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    scroll.jumpTo(0);
    await tester.pump();
    final before = await _pixels(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(listEquals(await _pixels(tester), before), isFalse);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('App 进入后台停止，恢复前台继续', (tester) async {
    await _mount(tester);
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    final before = await _pixels(tester);
    await tester.pump(const Duration(seconds: 7));
    expect(listEquals(await _pixels(tester), before), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(listEquals(await _pixels(tester), before), isFalse);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('离开当前路由停止，返回后继续', (tester) async {
    await _mount(tester);
    await tester.pump(const Duration(seconds: 1));
    final navigator = Navigator.of(tester.element(_button));
    final route = PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const Center(child: Text('其他页面')),
    );
    final closed = navigator.push(route);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    navigator.pop();
    await closed;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打卡完成后停止背景和按钮提醒', (tester) async {
    final pending = ValueNotifier(true);
    addTearDown(pending.dispose);
    await _mount(tester, pending: pending);
    await tester.pump(const Duration(seconds: 1));
    pending.value = false;
    await tester.pumpAndSettle();
    final before = await _pixels(tester);
    await tester.pump(const Duration(seconds: 7));
    expect(listEquals(await _pixels(tester), before), isTrue);
    expect(find.text('今日已打卡'), findsOneWidget);
    expect(_button, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
