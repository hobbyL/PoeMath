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
    final bend =
        curl.project(Offset(curl.fold + curl.radius * math.pi / 2, 200));
    expect(bend.height, greaterThan(0));
    expect(bend.angle, greaterThan(0));
    expect(bend.angle, lessThan(math.pi));
    expect(curl.project(const Offset(320, 200)).angle, math.pi);
    expect(curl.mesh.front, isNotEmpty);
    expect(curl.mesh.back, isNotEmpty);
    expect(curl.coverage.contains(const Offset(20, 200)), isTrue);
    expect(curl.coverage.contains(const Offset(145, 200)), isTrue);
    expect(curl.revealed.contains(const Offset(145, 200)), isFalse);
    expect(curl.revealed.contains(const Offset(310, 200)), isTrue);
    expect(curl.revealed.contains(const Offset(160, -10)), isFalse);
  });

  test('卷曲端点平整，双页右纸张翻到左侧，背面坐标保留正常阅读方向', () {
    const size = Size(320, 400);
    final start = TextbookPageCurl(size: size, progress: 0);
    expect(
        start.project(const Offset(300, 40)).position, const Offset(300, 40),);
    final end = TextbookPageCurl(size: size, progress: 1, doublePage: true);
    expect(
        end.project(const Offset(160, 200)).position.dx, closeTo(160, 0.001),);
    expect(end.project(const Offset(320, 200)).position.dx, closeTo(0, 0.001));
    final back =
        end.meshFor(const Rect.fromLTWH(0, 0, 160, 400), reverse: true);
    for (var i = 0; i < back.positions.length; i++) {
      expect(back.positions[i].dx, closeTo(back.texture[i].dx, 0.001));
    }
  });

  late List<ui.Image> images;
  setUp(() {
    images =
        [Colors.red, Colors.blue, Colors.green, Colors.orange].map((color) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 320, 400), Paint()..color = color,);
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
  }) async {
    Widget sheet(int index, double width, {double start = 0, double end = 1}) =>
        Center(
          child: TextbookCurlPageImage(
            image: RawImage(image: images[index], width: width, height: 400),
            start: start,
            end: end,
            gutter: end - start < 1 ? 4 : 0,
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('book'),
              child: SizedBox(
                width: 320,
                height: 400,
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
                                  child:
                                      sheet(index == 1 ? 0 : 2, 158, end: 0.5),),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: sheet(index == 1 ? 3 : 1, 158,
                                      start: 0.5,),),
                            ],
                          )
                        : sheet(index, 320),
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
            find.byKey(const ValueKey('book')),);
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          return (await image.toByteData())!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;

  void expectColor(Color actual, Color expected) =>
      expect(actual.toARGB32(), expected.toARGB32());

  Color pixel(Uint8List bytes, int x, int y) {
    final offset = (y * 320 + x) * 4;
    return Color.fromARGB(
        bytes[offset + 3], bytes[offset], bytes[offset + 1], bytes[offset + 2],);
  }

  testWidgets('前后翻页像素同时显示未翻区域、纸背和下一页，结束后整页完整且缓存保持', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await pumpBook(tester, controller);
    final raw = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image == images[1],
        skipOffstage: false,);
    final cached = tester.element(raw);
    final next = controller.animateToPage(1,
        duration: textbookPageTurnDuration, curve: Curves.linear,);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(controller.page, closeTo(0.5, 0.001));
    final frame = await pixels(tester);
    expectColor(pixel(frame, 20, 200), Colors.red);
    expectColor(pixel(frame, 310, 200), Colors.blue);
    final back = pixel(frame, 145, 200);
    expect(back.r, greaterThan(0.7));
    expect(back.g, greaterThan(0.7));
    expect(back.b, greaterThan(0.7));
    expect(tester.element(raw), same(cached));
    await tester.pumpAndSettle();
    await next;
    expectColor(pixel(await pixels(tester), 20, 200), Colors.blue);
    final previous = controller.animateToPage(0,
        duration: textbookPageTurnDuration, curve: Curves.linear,);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final reverse = await pixels(tester);
    expectColor(pixel(reverse, 20, 200), pixel(frame, 20, 200));
    expectColor(pixel(reverse, 145, 200), back);
    expectColor(pixel(reverse, 310, 200), pixel(frame, 310, 200));
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
    final next = controller.animateToPage(2,
        duration: textbookPageTurnDuration, curve: Curves.linear,);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 408));
    final frame = await pixels(tester);
    expectColor(pixel(frame, 20, 200), Colors.red);
    expectColor(pixel(frame, 310, 200), Colors.blue);
    final back = pixel(frame, 110, 200);
    expect(back.g, greaterThan(back.r * 1.6));
    expect(back.g, greaterThan(back.b * 1.6));
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
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('book'))));
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
}
