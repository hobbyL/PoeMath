import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

import '../test/helpers/textbook_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final doublePage in [false, true]) {
    testWidgets('原书${doublePage ? '对开' : '单页'}左右滑动跟手、吸附与缩放兼容', (tester) async {
      final directory = await Directory.systemTemp.createTemp('reader_swipe_');
      final file = await File('${directory.path}/sample.pdf')
          .writeAsBytes(syntheticPdf());
      TextbookGoToPage? goTo;
      var page = doublePage ? 3 : 2;
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: doublePage ? 600 : 360,
                  height: doublePage ? 400 : 480,
                  child: TextbookPdfView(
                    horizontalPaging: true,
                    options: TextbookViewerOptions(
                      path: file.path,
                      initialPage: page,
                      doublePage: doublePage,
                      onReady: (value) => goTo = value,
                      onPageChanged: (value) {
                        page = value;
                        changes.add(value);
                      },
                      onRetry: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(tester, () => goTo != null);
        await tester.pumpAndSettle();
        final viewer = find.byType(PdfViewer);
        final controller = tester.widget<PdfViewer>(viewer).controller!;
        final originalPage = page;
        final originalCenter = controller.centerPosition;
        final originalZoom = controller.currentZoom;
        expect(controller.minScale, lessThanOrEqualTo(originalZoom));
        if (doublePage) {
          expect(
            controller.visibleRect.contains(
              controller.layout.pageLayouts[1].center,
            ),
            isTrue,
          );
          expect(
            controller.visibleRect.contains(
              controller.layout.pageLayouts[2].center,
            ),
            isTrue,
          );
        }
        final sample = controller.layout.pageLayouts[page - 1].center;
        final gesture = await tester.startGesture(tester.getCenter(viewer));
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        final before = controller.documentToLocal(sample);
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        final after = controller.documentToLocal(sample);
        // 手指未松开时，PDF 已移动相同距离，页码仍代表已完成的阅读页。
        expect(after.dx - before.dx, closeTo(40, 1));
        expect(page, originalPage);
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(page, originalPage);
        expect(controller.centerPosition.dx, closeTo(originalCenter.dx, 0.1));
        expect(controller.currentZoom, closeTo(originalZoom, 0.001));

        changes.clear();
        await tester.drag(viewer, const Offset(240, 0));
        await tester.pumpAndSettle();
        expect(page, 1);
        expect(changes, [1]);
        await tester.drag(viewer, const Offset(240, 0));
        await tester.pumpAndSettle();
        expect(page, 1);
        await tester.drag(viewer, const Offset(-240, 0));
        await tester.pumpAndSettle();
        expect(page, 2);
        if (doublePage) {
          final rects = controller.layout.pageLayouts;
          expect(controller.visibleRect.contains(rects[1].center), isTrue);
          expect(controller.visibleRect.contains(rects[2].center), isTrue);
          final toRight = goTo!(3);
          await tester.pumpAndSettle();
          await toRight;
          expect(page, 3);
        } else {
          // 短而快的轻扫也能翻页，不要求拖过距离阈值。
          await tester.fling(viewer, const Offset(-60, 0), 1200);
          await tester.pumpAndSettle();
          expect(page, 3);
        }
        await tester.drag(viewer, const Offset(-240, 0));
        await tester.pumpAndSettle();
        expect(page, 3);

        final restore = goTo!(2);
        await tester.pumpAndSettle();
        await restore;
        final zoom = controller.currentZoom * 2;
        await controller.setZoom(
          controller.layout.pageLayouts[1].center,
          zoom,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        final zoomedCenter = controller.centerPosition;
        await tester.drag(viewer, const Offset(-90, 0));
        await tester.pumpAndSettle();
        expect(page, 2);
        expect(controller.currentZoom, closeTo(zoom, 0.001));
        expect(controller.centerPosition.dx, greaterThan(zoomedCenter.dx));

        // 双指缩小应回到完整的一页/对开页，不受整本横向布局宽度影响。
        final center = tester.getCenter(viewer);
        final left = await tester.startGesture(
          center - const Offset(80, 0),
          pointer: 1,
        );
        final right = await tester.startGesture(
          center + const Offset(80, 0),
          pointer: 2,
        );
        await left.moveBy(const Offset(60, 0));
        await right.moveBy(const Offset(-60, 0));
        await tester.pump();
        await left.up();
        await right.up();
        await tester.pumpAndSettle();
        expect(controller.currentZoom, closeTo(controller.minScale, 0.001));
        expect(page, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await directory.delete(recursive: true);
      }
    });
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('原书未在期限内准备好');
}
