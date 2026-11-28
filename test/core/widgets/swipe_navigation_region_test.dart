import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/swipe_navigation_region.dart';

void main() {
  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('分段选中底色跟随拖动、回退和松手，边界不串联：$subject/$brightness', (
        tester,
      ) async {
        final theme = AppTheme.resolve(
          subject: subject,
          brightness: brightness,
        );
        var selected = 0;
        var outerChanges = 0;
        final changes = <int>[];
        const buttonKey = ValueKey('segment-pixels');
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: StatefulBuilder(
              builder: (context, setState) {
                void select(int value) {
                  changes.add(value);
                  setState(() => selected = value);
                }

                return SwipeNavigationRegion(
                  onNext: () => outerChanges++,
                  onPrevious: () => outerChanges++,
                  child: SwipeNavigationRegion(
                    animateBodyOnly: true,
                    transitionKey: selected,
                    onNext: selected < 2 ? () => select(selected + 1) : null,
                    onPrevious: selected > 0
                        ? () => select(selected - 1)
                        : null,
                    child: Scaffold(
                      appBar: AppBar(
                        title: RepaintBoundary(
                          key: buttonKey,
                          child: SwipeNavigationSegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 0, label: Text('课本')),
                              ButtonSegment(value: 1, label: Text('表达')),
                              ButtonSegment(value: 2, label: Text('诗词')),
                            ],
                            selected: selected,
                            onSelectionChanged: (values) =>
                                select(values.single),
                          ),
                        ),
                      ),
                      body: const SwipeNavigationBody(child: SizedBox.expand()),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        final region = find.byType(SwipeNavigationRegion).last;
        final width = tester.getSize(region).width;
        final switcherRect = tester.getRect(find.byKey(buttonKey));

        Future<void> expectSelectionAt(double position) async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(buttonKey),
          );
          final samples = await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final samples = <(Color, Color)>[];
              for (var i = 0; i < 3; i++) {
                // 取每项左、中、右的无文字区域，确认底色真实平移而非混色。
                for (final fraction in [.125, .5, .875]) {
                  final x = ((i + fraction) * image.width / 3).floor();
                  final offset = (8 * image.width + x) * 4;
                  final withinSelection =
                      x >= position * image.width / 3 &&
                      x < (position + 1) * image.width / 3;
                  samples.add((
                    Color.fromARGB(
                      255,
                      bytes.getUint8(offset),
                      bytes.getUint8(offset + 1),
                      bytes.getUint8(offset + 2),
                    ),
                    withinSelection
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surface,
                  ));
                }
              }
              return samples;
            } finally {
              image.dispose();
            }
          });
          for (final (actual, expected) in samples!) {
            expect(actual.r, closeTo(expected.r, 2 / 255));
            expect(actual.g, closeTo(expected.g, 2 / 255));
            expect(actual.b, closeTo(expected.b, 2 / 255));
          }
        }

        await expectSelectionAt(0);
        var gesture = await tester.startGesture(tester.getCenter(region));
        await gesture.moveBy(Offset(-width / 4, 0));
        await tester.pump();
        await expectSelectionAt(.25);
        expect(tester.getRect(find.byKey(buttonKey)), switcherRect);
        expect(changes, isEmpty);
        expect(find.bySemanticsLabel('课本'), findsOneWidget);
        expect(find.bySemanticsLabel('表达'), findsOneWidget);
        expect(find.bySemanticsLabel('诗词'), findsOneWidget);

        await gesture.moveBy(Offset(-width / 4, 0));
        await tester.pump();
        await expectSelectionAt(.5);
        await gesture.moveBy(Offset(width / 4, 0));
        await tester.pump();
        await expectSelectionAt(.25);
        await gesture.cancel();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        final rebound = .25 * (1 - Curves.easeOutCubic.transform(.5));
        await expectSelectionAt(rebound);
        await tester.pumpAndSettle();
        await expectSelectionAt(0);
        expect(changes, isEmpty);

        gesture = await tester.startGesture(tester.getCenter(region));
        await gesture.moveBy(Offset(-width / 4, 0));
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        final progress = .25 + .75 * Curves.easeOutCubic.transform(.5);
        await expectSelectionAt(progress);
        await tester.pumpAndSettle();
        await expectSelectionAt(1);
        expect(changes, [1]);

        gesture = await tester.startGesture(tester.getCenter(region));
        await gesture.moveBy(Offset(-width / 4, 0));
        await tester.pump();
        await expectSelectionAt(1.25);
        await gesture.moveBy(Offset(width / 2, 0));
        await tester.pump();
        await expectSelectionAt(.75);
        await gesture.up();
        await tester.pumpAndSettle();
        await expectSelectionAt(0);
        expect(changes, [1, 0]);

        gesture = await tester.startGesture(tester.getCenter(region));
        await gesture.moveBy(Offset(width / 4, 0));
        await tester.pump();
        await expectSelectionAt(0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(outerChanges, 1);
        expect(changes, [1, 0]);

        await tester.tap(find.text('诗词'));
        await tester.pumpAndSettle();
        await expectSelectionAt(2);
        expect(changes, [1, 0, 2]);
        semantics.dispose();
      });
    }
  }

  testWidgets('左划下一项、右划上一项，松手后每次只切换一次', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onNext: () => changes.add('next'),
          onPrevious: () => changes.add('previous'),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(200, 200));
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.moveBy(const Offset(-100, 0));
    expect(changes, isEmpty);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(changes, ['next']);
    await tester.drag(find.byType(SwipeNavigationRegion), const Offset(180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(changes, ['next', 'previous']);
  });

  testWidgets('拖动时页面跟随手指平移，松手后继续滑出再切换', (tester) async {
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onNext: () => changes++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final region = find.byType(SwipeNavigationRegion);
    final gesture = await tester.startGesture(tester.getCenter(region));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();

    Transform translatedContent() => tester.widget<Transform>(
      find.descendant(
        of: region,
        matching: find.byKey(const ValueKey('swipe-navigation-content')),
      ),
    );

    expect(translatedContent().transform.getTranslation().x, -80);
    expect(changes, 0, reason: '切换应等到松手并完成滑出动画');
    await gesture.up();
    expect(changes, 0);
    await tester.pump();
    Animation<double> settleAnimation() =>
        tester
                .widget<AnimatedBuilder>(
                  find.descendant(
                    of: region,
                    matching: find.byType(AnimatedBuilder),
                  ),
                )
                .animation
            as Animation<double>;
    expect(settleAnimation().isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 110));
    expect(settleAnimation().value, greaterThan(0));
    expect(translatedContent().transform.getTranslation().x, lessThan(-80));
    await tester.pump(const Duration(milliseconds: 120));
    expect(changes, 1);
  });

  testWidgets('拖动时相邻页跟手进入，松手后目标页直接接管', (tester) async {
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => SwipeNavigationRegion(
            transitionKey: page,
            transitionDirection: 1,
            onNext: () => setState(() => page++),
            nextPageBuilder: (_) => const ColoredBox(
              key: ValueKey('next-page-preview'),
              color: Colors.red,
            ),
            child: SizedBox.expand(key: ValueKey(page)),
          ),
        ),
      ),
    );
    final region = find.byType(SwipeNavigationRegion);
    final gesture = await tester.startGesture(tester.getCenter(region));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final regionRect = tester.getRect(region);
    final preview = find.descendant(
      of: region,
      matching: find.byKey(const ValueKey('swipe-navigation-next-preview')),
    );
    expect(preview, findsOneWidget);
    expect(
      tester.widget<Transform>(preview).transform.getTranslation().x,
      closeTo(regionRect.width - 100, 1),
      reason: '下一页应该从右侧进入 100dp',
    );
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(page, 1);

    await tester.pump();
    Transform translatedContent() => tester.widget<Transform>(
      find.descendant(
        of: region,
        matching: find.byKey(const ValueKey('swipe-navigation-content')),
      ),
    );
    expect(
      translatedContent().transform.getTranslation().x,
      0,
      reason: '拖动预览完成后不应再让真实目标页从空白处重复入场',
    );
  });

  testWidgets('内层边界继承外层相邻页预览', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onNext: () {},
          nextPageBuilder: (_) => const ColoredBox(
            key: ValueKey('outer-next-page-preview'),
            color: Colors.red,
          ),
          child: const SwipeNavigationRegion(child: SizedBox.expand()),
        ),
      ),
    );
    final inner = find.byType(SwipeNavigationRegion).last;
    final regionRect = tester.getRect(inner);
    final gesture = await tester.startGesture(tester.getCenter(inner));
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();

    final preview = find.descendant(
      of: inner,
      matching: find.byKey(const ValueKey('swipe-navigation-next-preview')),
    );
    expect(preview, findsOneWidget);
    expect(
      tester.widget<Transform>(preview).transform.getTranslation().x,
      closeTo(regionRect.width - 90, 1),
      reason: '栏目边界应预览外层 Tab 的真实页面',
    );
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('正文模式支持顶部起滑和取消，边界才带动整页', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onPrevious: () => changes.add('outer'),
          previousPageBuilder: (_) => const Scaffold(body: Text('上一主栏目')),
          child: SwipeNavigationRegion(
            animateBodyOnly: true,
            onNext: () => changes.add('inner'),
            nextPageBuilder: (_) => const Scaffold(body: Text('下一子栏目')),
            child: Scaffold(
              appBar: AppBar(title: const Text('固定导航')),
              body: const SwipeNavigationBody(
                child: Center(child: Text('当前正文')),
              ),
            ),
          ),
        ),
      ),
    );
    final title = find.text('固定导航');
    final content = find.text('当前正文');
    final titleRect = tester.getRect(title);
    final contentRect = tester.getRect(content);
    var gesture = await tester.startGesture(tester.getCenter(title));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(tester.getRect(title), titleRect);
    expect(tester.getRect(content), contentRect.shift(const Offset(-80, 0)));
    expect(find.text('下一子栏目'), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(tester.getRect(title), titleRect);
    expect(tester.getRect(content), contentRect);

    gesture = await tester.startGesture(tester.getCenter(content));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(tester.getRect(title), titleRect.shift(const Offset(80, 0)));
    expect(
      tester.getRect(content),
      contentRect.shift(const Offset(80, 0)),
      reason: '边界滑动不能同时在整页与正文上各平移一次',
    );
    expect(find.text('上一主栏目'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, ['outer']);
  });

  testWidgets('低于最小距离的抖动和纵向拖动不切换', (tester) async {
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onNext: () => changes++,
          onPrevious: () => changes++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final region = find.byType(SwipeNavigationRegion);
    await tester.drag(region, const Offset(30, 0));
    expect(changes, 0, reason: '短距离拖动不应触发切换');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.drag(region, const Offset(15, -180));
    expect(changes, 0, reason: '纵向拖动不应触发切换');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.drag(region, const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(changes, 1, reason: '下一次有效手势仍可切换');
  });

  testWidgets('越过最小滑动距离后切换', (tester) async {
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onNext: () => changes++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.fling(
      find.byType(SwipeNavigationRegion),
      const Offset(-80, 0),
      800,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(changes, 1);
  });

  testWidgets('内层栏目优先，到边界时只触发外层对应方向', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeNavigationRegion(
          onNext: () => changes.add('outer-next'),
          onPrevious: () => changes.add('outer-previous'),
          child: SwipeNavigationRegion(
            onNext: () => changes.add('inner-next'),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final inner = find.byType(SwipeNavigationRegion).last;
    await tester.drag(inner, const Offset(-180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(changes, ['inner-next']);
    await tester.drag(inner, const Offset(180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(changes, ['inner-next', 'outer-previous']);
  });

  for (final axis in Axis.values) {
    testWidgets('$axis 列表滚动优先，点击保持有效', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var changes = 0;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeNavigationRegion(
              onNext: () => changes++,
              onPrevious: () => changes++,
              child: ListView.builder(
                controller: controller,
                scrollDirection: axis,
                itemExtent: 80,
                itemCount: 30,
                itemBuilder: (_, index) => TextButton(
                  onPressed: () => taps++,
                  child: Text('item $index'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('item 0'));
      expect(taps, 1);
      await tester.drag(
        find.byType(ListView),
        axis == Axis.vertical ? const Offset(5, -200) : const Offset(-200, 5),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(100));
      expect(changes, 0);
    });
  }
}
