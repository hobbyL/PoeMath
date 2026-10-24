import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

import '../test/helpers/textbook_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实预览：邻页预渲染及翻页等待测量', (tester) async {
    final directory = await Directory.systemTemp.createTemp('preview_render_');
    final file =
        await File('${directory.path}/sample.pdf').writeAsBytes(syntheticPdf());
    TextbookGoToPage? goTo;
    var page = 1;
    Widget preview({bool doublePage = false, bool reduceMotion = false}) =>
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: doublePage ? 600 : 360,
                height: doublePage ? 400 : 480,
                child: TextbookPdfPreview(
                  options: TextbookViewerOptions(
                    path: file.path,
                    initialPage: 1,
                    doublePage: doublePage,
                    onReady: (value) => goTo = value,
                    onPageChanged: (value) => page = value,
                    onRetry: () {},
                  ),
                ),
              ),
            ),
          ),
        );
    try {
      await tester.pumpWidget(preview());
      await _until(tester, () => goTo != null && _rendered(tester, 1));
      await _until(tester, () => _rendered(tester, 2));
      // 渐进尺寸加载会合法替换缓存；先等待合成样本的三页全部稳定。
      await _until(
        tester,
        () =>
            tester
                .widget<PdfPageView>(find.byType(PdfPageView).first)
                .document!
                .pages
                .every((page) => page.isLoaded) &&
            _rendered(tester, 3),
      );
      await tester.pumpAndSettle();
      final prefetched = _rendered(tester, 2);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      final firstPage = find.byWidgetPredicate(
        (widget) => widget is PdfPageView && widget.pageNumber == 1,
        skipOffstage: false,
      );
      final secondPage = find.byWidgetPredicate(
        (widget) => widget is PdfPageView && widget.pageNumber == 2,
        skipOffstage: false,
      );
      final cachedSecondPage = tester.element(secondPage);
      final cachedImage = tester
          .widget<RawImage>(
            find.descendant(
              of: secondPage,
              matching: find.byType(RawImage, skipOffstage: false),
              skipOffstage: false,
            ),
          )
          .image;
      final stopwatch = Stopwatch()..start();
      final turning = goTo!(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(pageView.controller!.page, greaterThan(0));
      expect(pageView.controller!.page, lessThan(1));
      final flat =
          find.descendant(of: firstPage, matching: find.byType(ClipPath));
      final flatSize = tester.getSize(flat);
      final clip = tester.widget<ClipPath>(flat).clipper!.getClip(flatSize);
      expect(clip.contains(Offset(1, flatSize.height / 2)), isTrue);
      expect(
        clip.contains(Offset(flatSize.width - 1, flatSize.height / 2)),
        isFalse,
      );
      expect(tester.element(secondPage), same(cachedSecondPage));
      expect(
        identical(
          tester
              .widget<RawImage>(
                find.descendant(
                  of: secondPage,
                  matching: find.byType(RawImage, skipOffstage: false),
                  skipOffstage: false,
                ),
              )
              .image,
          cachedImage,
        ),
        isTrue,
      );
      await _until(tester, () => page == 2 && _rendered(tester, 2));
      await tester.pumpAndSettle();
      await turning;
      stopwatch.stop();
      debugPrint(
        'PREVIEW_RENDER prefetched=$prefetched turnMs=${stopwatch.elapsedMilliseconds}',
      );
      expect(page, 2);
      expect(prefetched, isTrue);
      expect(_rendered(tester, 2), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(preview(reduceMotion: true));
      final reducedTurn = goTo!(1);
      await tester.pump();
      await reducedTurn;
      expect(pageView.controller!.page, 0);
      expect(page, 1);
      expect(tester.takeException(), isNull);
      final reducedReturn = goTo!(2);
      await tester.pump();
      await reducedReturn;
      expect(page, 2);
      await tester.pumpWidget(preview(doublePage: true));
      // 先沿用当前页2，改变显示模式不能跳回封面。
      await _until(tester, () => _rendered(tester, 2) && _rendered(tester, 3));
      final left = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is PdfPageView && widget.pageNumber == 2,
        ),
      );
      final right = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is PdfPageView && widget.pageNumber == 3,
        ),
      );
      expect(left.top, right.top);
      expect(right.left, greaterThan(left.right));
      expect(page, 2);
      // 同一展开页输入右页仍保留精确页码。
      final sameSpreadRight = goTo!(3);
      await tester.pumpAndSettle();
      await sameSpreadRight;
      expect(page, 3);
      final toCover = goTo!(1);
      await _until(tester, () => page == 1);
      await tester.pumpAndSettle();
      await toCover;
      expect(page, 1);
      // 跳到右页时中途切为单页，不能留下左页画面/右页状态。
      final interruptedRight = goTo!(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final doubleController =
          tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(doubleController.page, greaterThan(0.5));
      expect(doubleController.page, lessThan(1));
      await tester.pumpWidget(preview());
      await _until(tester, () => page == 3 && _rendered(tester, 3));
      await tester.pumpAndSettle();
      await interruptedRight;
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        2,
      );
      expect(page, 3);
      expect(tester.takeException(), isNull);
      goTo = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextbookPdfView(
              options: TextbookViewerOptions(
                path: file.path,
                initialPage: 3,
                doublePage: true,
                onReady: (value) => goTo = value,
                onPageChanged: (value) => page = value,
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await _until(tester, () => goTo != null);
      await tester.pumpAndSettle();
      final controller =
          tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      final rects = controller.layout.pageLayouts;
      expect(rects[1].top, rects[2].top);
      expect(rects[2].left, greaterThan(rects[1].right));
      expect(controller.visibleRect.contains(rects[1].center), isTrue);
      expect(controller.visibleRect.contains(rects[2].center), isTrue);
      expect(page, 3);
      final readerCover = goTo!(1);
      await _until(tester, () => page == 1);
      await tester.pumpAndSettle();
      await readerCover;
      final readerRight = goTo!(3);
      await _until(tester, () => page == 3);
      await tester.pumpAndSettle();
      await readerRight;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextbookPdfView(
              options: TextbookViewerOptions(
                path: file.path,
                initialPage: 3,
                onReady: (value) => goTo = value,
                onPageChanged: (value) => page = value,
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(page, 3);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await directory.delete(recursive: true);
    }
  });

  const localPdf = String.fromEnvironment('TEXTBOOK_SEARCH_ACCEPTANCE_PDF');
  testWidgets(
    '本机一年级下册：注音正文中文搜索与原PDF复用',
    (tester) async {
      TextbookSearch? search;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextbookPdfPreview(
              options: TextbookViewerOptions(
                path: localPdf,
                initialPage: 1,
                onReady: (_) {},
                onPageChanged: (_) {},
                onRetry: () {},
                onSearchReady: (value) => search = value,
              ),
            ),
          ),
        ),
      );
      await _until(tester, () => search != null);
      final document =
          tester.widget<PdfPageView>(find.byType(PdfPageView).first).document;
      expect(document!.pages.length, 127);
      for (final entry in {
        '春晓': [17],
        '小鸭子': [4, 31, 32, 33, 79],
        '小公鸡和小鸭子': [4, 31, 33],
      }.entries) {
        final results = await search!(entry.key).toList();
        expect(results.length, 127);
        expect(
          results
              .where((result) => result.matchCount > 0)
              .map((result) => result.page),
          entry.value,
        );
        expect(
          tester.widget<PdfPageView>(find.byType(PdfPageView).first).document,
          same(document),
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    skip: localPdf.isEmpty,
  );
}

bool _rendered(WidgetTester tester, int number) {
  final page = find.byWidgetPredicate(
    (widget) => widget is PdfPageView && widget.pageNumber == number,
    skipOffstage: false,
  );
  return find
      .descendant(
        of: page,
        matching: find.byType(RawImage, skipOffstage: false),
        skipOffstage: false,
      )
      .evaluate()
      .any((element) => (element.widget as RawImage).image != null);
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('PDF 预览未在期限内准备好');
}
