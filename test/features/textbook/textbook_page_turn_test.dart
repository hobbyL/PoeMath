import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_curl.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_turn.dart';

void main() {
  test('纸张有静止、弯曲、纸背三段，朝观察者凸起，遮挡轮廓没有重叠空洞', () {
    final curl = TextbookPageCurl(size: const Size(320, 400), progress: 0.5);
    final flat = curl.project(const Offset(20, 200));
    expect(flat.position, const Offset(20, 200));
    expect(flat.height, 0);
    final bend = curl.project(
      Offset(curl.fold + curl.radius * math.pi / 2, 200),
    );
    expect(bend.height, greaterThan(0));
    expect(bend.angle, greaterThan(0));
    expect(bend.angle, lessThan(math.pi));
    expect(curl.project(const Offset(320, 200)).angle, math.pi);
    expect(curl.mesh.front, isNotEmpty);
    expect(curl.mesh.back, isNotEmpty);
    expect(curl.coverage.contains(const Offset(20, 200)), isTrue);
    expect(curl.coverage.contains(const Offset(145, 200)), isTrue);
    expect(curl.coverage.contains(const Offset(310, 200)), isFalse);
  });

  test('卷曲端点平整，双页右纸张翻到左侧，背面坐标保留正常阅读方向', () {
    const size = Size(320, 400);
    final start = TextbookPageCurl(size: size, progress: 0);
    expect(
      start.project(const Offset(300, 40)).position,
      const Offset(300, 40),
    );
    final end = TextbookPageCurl(size: size, progress: 1, doublePage: true);
    expect(
      end.project(const Offset(160, 200)).position.dx,
      closeTo(160, 0.001),
    );
    expect(end.project(const Offset(320, 200)).position.dx, closeTo(0, 0.001));
    final back = end.meshFor(
      const Rect.fromLTWH(0, 0, 160, 400),
      reverse: true,
    );
    for (var i = 0; i < back.positions.length; i++) {
      expect(back.positions[i].dx, closeTo(back.texture[i].dx, 0.001));
    }
  });

  test('纸面留边时，平面裁剪保留与斜折线的真实交点', () {
    const size = Size(320, 400);
    const source = Rect.fromLTRB(12, 0, 308, 400);
    for (final progress in [0.035, 0.965]) {
      final curl = TextbookPageCurl(size: size, progress: progress);
      final clip = curl.flatClip(source);
      for (var y = 2; y < 398; y += 4) {
        for (var x = 14; x < 306; x += 4) {
          final point = Offset(x + 0.5, y + 0.5);
          expect(
            clip.contains(point),
            curl.project(point).angle == 0,
            reason: 'progress=$progress point=$point',
          );
        }
      }
      final edgePoint = progress < 0.5
          ? const Offset(307.5, 100)
          : const Offset(12.5, 300);
      expect(clip.contains(edgePoint), curl.project(edgePoint).angle == 0);
    }
  });

  late List<ui.Image> images;
  setUp(() {
    images = [Colors.red, Colors.blue, Colors.green, Colors.orange].map((
      color,
    ) {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 320, 400), Paint()..color = color);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(320, 400);
      picture.dispose();
      return image;
    }).toList();
  });
  tearDown(() {
    for (final image in images) {
      image.dispose();
    }
  });

  Future<void> pumpBook(
    WidgetTester tester,
    PageController controller, {
    bool reduceMotion = false,
    bool doublePage = false,
    Size pageSize = const Size(320, 400),
    double pageInset = 0,
  }) async {
    Widget sheet(int index, double width, {double start = 0, double end = 1}) =>
        Center(
          child: TextbookCurlPageImage(
            image: RawImage(
              image: images[index],
              width: width - pageInset * 2,
              height: pageSize.height,
              fit: BoxFit.fill,
            ),
            start: start,
            end: end,
            gutter: end - start < 1 ? 4 : 0,
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(surface: Color(0xFFFFF0D0)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('book'),
              child: SizedBox(
                width: pageSize.width,
                height: pageSize.height,
                child: PageView.builder(
                  controller: controller,
                  allowImplicitScrolling: true,
                  itemCount: 3,
                  itemBuilder: (context, index) => TextbookPageTurn(
                    key: ValueKey('turn-$index'),
                    controller: controller,
                    index: index,
                    doublePage: doublePage,
                    child: doublePage && index > 0
                        ? Row(
                            children: [
                              Expanded(
                                child: sheet(
                                  index == 1 ? 0 : 2,
                                  (pageSize.width - 4) / 2,
                                  end: 0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: sheet(
                                  index == 1 ? 3 : 1,
                                  (pageSize.width - 4) / 2,
                                  start: 0.5,
                                ),
                              ),
                            ],
                          )
                        : sheet(index, pageSize.width),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Uint8List> pixels(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('book')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          return (await image.toByteData())!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;

  void expectColor(Color actual, Color expected) =>
      expect(actual.toARGB32(), expected.toARGB32());

  Color pixel(Uint8List bytes, int x, int y, {int width = 320}) {
    final offset = (y * width + x) * 4;
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }

  testWidgets('极小进度和动画各帧遮挡有效，不出现原生路径异常或提前露出下一页', (tester) async {
    for (final doublePage in [false, true]) {
      final initialPage = doublePage ? 1 : 0;
      final controller = PageController(initialPage: initialPage);
      addTearDown(controller.dispose);
      await pumpBook(
        tester,
        controller,
        doublePage: doublePage,
        pageSize: const Size(360, 480),
      );
      for (final progress in [
        0.00000001,
        0.000001,
        0.0001,
        for (var frame = 1; frame < 64; frame++) frame / 64,
        0.9999,
        0.999999,
        0.99999999,
      ]) {
        controller.jumpTo((initialPage + progress) * 360);
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'progress=$progress doublePage=$doublePage',
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('前后翻页像素同时显示未翻区域、纸背和下一页，结束后整页完整且缓存保持', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await pumpBook(tester, controller);
    final raw = find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image == images[1],
      skipOffstage: false,
    );
    final cached = tester.element(raw);
    // 固定取样进度，真实设备的绘制耗时不能参与像素断言。
    controller.jumpTo(320 * 0.5);
    await tester.pump();
    expect(controller.page, closeTo(0.5, 0.001));
    final frame = await pixels(tester);
    expectColor(pixel(frame, 20, 200), Colors.red);
    expectColor(pixel(frame, 310, 200), Colors.blue);
    final back = pixel(frame, 145, 200);
    expect(back.r, greaterThan(0.7));
    expect(back.g, greaterThan(0.7));
    expect(back.b, greaterThan(0.7));
    expect(tester.element(raw), same(cached));
    final next = controller.animateToPage(
      1,
      duration: textbookPageTurnDuration,
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await next;
    expectColor(pixel(await pixels(tester), 20, 200), Colors.blue);
    controller.jumpTo(320 * 0.5);
    await tester.pump();
    final reverse = await pixels(tester);
    expectColor(pixel(reverse, 20, 200), pixel(frame, 20, 200));
    expectColor(pixel(reverse, 145, 200), back);
    expectColor(pixel(reverse, 310, 200), pixel(frame, 310, 200));
    final previous = controller.animateToPage(
      0,
      duration: textbookPageTurnDuration,
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await previous;
    expectColor(pixel(await pixels(tester), 310, 200), Colors.red);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('双页只翻动右纸张，未翻左页保持，纸背使用下一展开页的左页内容', (tester) async {
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);
    await pumpBook(tester, controller, doublePage: true);
    controller.jumpTo(320 * 1.85);
    await tester.pump();
    final frame = await pixels(tester);
    expectColor(pixel(frame, 20, 200), Colors.red);
    expectColor(pixel(frame, 310, 200), Colors.blue);
    final back = pixel(frame, 110, 200);
    expect(back.g, greaterThan(back.r * 1.6));
    expect(back.g, greaterThan(back.b * 1.6));
    final next = controller.animateToPage(
      2,
      duration: textbookPageTurnDuration,
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await next;
    expectColor(pixel(await pixels(tester), 110, 200), Colors.green);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手势驱动卷曲并可松手取消，减少动态效果直接显示完整页', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await pumpBook(tester, controller);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('book'))),
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(controller.page, greaterThan(0));
    expect(controller.page, lessThan(0.5));
    final frame = await pixels(tester);
    expectColor(pixel(frame, 310, 200), Colors.blue);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    await pumpBook(tester, controller, reduceMotion: true);
    controller.jumpToPage(2);
    await tester.pumpAndSettle();
    expectColor(pixel(await pixels(tester), 20, 200), Colors.green);
    expectColor(pixel(await pixels(tester), 310, 200), Colors.green);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('卷页底部保持遮挡，下一页不能穿过纸背形成三角缺口', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    const size = Size(320, 400);
    await pumpBook(tester, controller, pageSize: size);
    for (var frame = 1; frame < 32; frame++) {
      final progress = frame / 32;
      controller.jumpTo(progress * size.width);
      await tester.pump();
      final framePixels = await pixels(tester);
      final coverage = TextbookPageCurl(
        size: size,
        progress: progress,
      ).coverage;
      for (var y = 304; y < 396; y += 4) {
        for (var x = 4; x < 316; x += 4) {
          final point = Offset(x + 0.5, y + 0.5);
          final inside = [
            const Offset(-2, 0),
            const Offset(2, 0),
            const Offset(0, -2),
            const Offset(0, 2),
          ].every((offset) => coverage.contains(point + offset));
          if (!inside) continue;
          final color = pixel(framePixels, x, y);
          final nextPage = color.b > 0.7 && color.r < 0.3 && color.g < 0.7;
          expect(nextPage, isFalse, reason: 'progress=$progress point=$point');
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('底页阴影沿倾斜卷边延伸，底部不留无阴影的白色三角', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await pumpBook(tester, controller);
    controller.jumpTo(320 * 0.5);
    await tester.pump();
    final frame = await pixels(tester);
    // 位于倾斜纸张右侧、旧竖直阴影左侧；这里必须受到卷页投影遮蔽。
    final shadow = pixel(frame, 196, 350);
    expect(shadow.b, lessThan(Colors.blue.b * 0.94));
    expectColor(pixel(frame, 310, 350), Colors.blue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('留边预览的纸背连续，不露出底色或原书白色三角', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    const size = Size(320, 400);
    await pumpBook(tester, controller, pageInset: 12);
    var checkedPixels = 0;
    for (final progress in [0.04, 0.08, 0.12, 0.2, 0.35, 0.5]) {
      controller.jumpTo(progress * size.width);
      await tester.pump();
      final frame = await pixels(tester);
      final curl = TextbookPageCurl(size: size, progress: progress);
      for (var y = 240; y < 396; y += 4) {
        for (var x = 14; x < 306; x += 4) {
          final point = curl.project(Offset(x.toDouble(), y.toDouble()));
          if (point.angle < 2 ||
              point.position.dx < 2 ||
              point.position.dx >= 318 ||
              point.position.dy < 2 ||
              point.position.dy >= 398) {
            continue;
          }
          // 取样像素中心须在纸张内部，不能把边缘点取整到下一页。
          final center = Offset(
            point.position.dx.round() + 0.5,
            point.position.dy.round() + 0.5,
          );
          if (![
            const Offset(-2, 0),
            const Offset(2, 0),
            const Offset(0, -2),
            const Offset(0, 2),
          ].every((offset) => curl.leafCoverage.contains(center + offset))) {
            continue;
          }
          final color = pixel(
            frame,
            point.position.dx.round(),
            point.position.dy.round(),
          );
          checkedPixels++;
          expect(color.a, 1);
          expect(
            color.b,
            lessThan(color.r * 0.85),
            reason:
                'progress=$progress source=($x, $y) '
                'position=${point.position} color=$color',
          );
        }
      }
    }
    expect(checkedPixels, greaterThan(500));
    await tester.pumpWidget(const SizedBox());
  });
}
