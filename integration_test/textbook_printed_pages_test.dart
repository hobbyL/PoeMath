import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/domain/textbook_printed_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

import '../test/helpers/textbook_fixture.dart';
import '../test/helpers/textbook_page_number_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
      reason: '必须使用 POEMATH_INTEGRATION_TEST=true 隔离测试包',
    );
  });

  testWidgets('真实 PDFium：左右页脚与未编号插页，默认书页定位并复用预览文档', (tester) async {
    final directory = await Directory.systemTemp.createTemp('printed_pages_');
    const printed = [null, null, null, null, null, 1, 2, null, 26];
    final bytes = printedPagesPdf(printed);
    final file = await File('${directory.path}/sample.pdf').writeAsBytes(bytes);
    final book = textbookFixture(
      id: sha256.convert(bytes).toString(),
      pageCount: printed.length,
      fileSize: bytes.length,
    );
    TextbookContentCache reopen() => TextbookContentCache(
      book: book,
      directoryProvider: () async => directory,
    );
    final cache = reopen();
    NativeTextbookPdfSource? source;
    TextbookPageNumberService? numbers;
    TextbookGoToPage? goTo;
    var page = 1;
    int? selected;
    try {
      source = await NativeTextbookPdfSource.open(
        path: file.path,
        book: book,
        cache: cache,
        token: TextbookDraftToken(),
      );
      expect(printedTextbookPage(await source.page(6)), 1);
      await source.close();
      source = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: TextbookPdfPreview(
                      options: TextbookViewerOptions(
                        path: file.path,
                        initialPage: 1,
                        contentCache: cache,
                        onReady: (value) => goTo = value,
                        onPageNumbersReady: (value) => numbers = value,
                        onPageChanged: (value) => page = value,
                        onRetry: () {},
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      selected = await showDialog<int>(
                        context: context,
                        builder: (_) => TextbookPageDialog(
                          page: page,
                          pageCount: printed.length,
                          pageNumbers: numbers,
                        ),
                      );
                      if (selected != null) await goTo!(selected!);
                    },
                    child: const Text('跳到书页'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _until(tester, () => numbers != null && goTo != null);
      final document = tester
          .widget<PdfPageView>(find.byType(PdfPageView).first)
          .document;
      expect(await numbers!.page(7), 2);
      expect(await numbers!.page(1), isNull);
      expect(await numbers!.page(8), isNull);
      expect(await numbers!.page(9), 26);
      expect((await cache.cachedPageLayout(1))!.text, isNot(contains('999')));
      expect((await cache.cachedPageLayout(1))!.text, isNot(contains('888')));
      await tester.tap(find.text('跳到书页'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '书页'))
            .selected,
        isTrue,
      );
      await tester.enterText(find.byType(TextFormField), '2');
      await tester.tap(find.text('跳转'));
      await _until(tester, () => page == 7);
      await tester.pumpAndSettle();
      expect(selected, 7);
      expect(
        tester.widget<PdfPageView>(find.byType(PdfPageView).first).document,
        same(document),
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('第 2 页'), findsOneWidget);
      semantics.dispose();
      expect(numbers!.numbers.complete, isTrue);
      expect((await reopen().readPageNumbers()).pages, {
        for (var i = 0; i < printed.length; i++) i + 1: printed[i],
      });
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => numbers!.page(7), throwsStateError);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await source?.close();
      await directory.delete(recursive: true);
    }
  });

  const realPdf = String.fromEnvironment('TEXTBOOK_PAGE_NUMBER_ACCEPTANCE_PDF');
  const grade1Pdf = String.fromEnvironment(
    'TEXTBOOK_PAGE_NUMBER_ACCEPTANCE_GRADE1_PDF',
  );
  for (final fixture in [
    (
      name: '现有二上教材：真实页脚与完整书页索引',
      path: realPdf,
      sha: 'd120c4c1e461353d3af7781ac73a57b30b9633f053af937e8e1017b3152ed33a',
      pageCount: 126,
      bytes: 23488142,
      pages: <int, int?>{1: null, 6: 1, 7: 2, 8: 3, 31: 26, 66: 61, 126: null},
    ),
    (
      name: '现有一年下教材：春夏秋冬书页 2 与小公鸡和小鸭子书页 26–28',
      path: grade1Pdf,
      sha: '294652c84058ac8d60364e3e04e4cd5ebd37ecf189293b5308ce26c46cfa498f',
      pageCount: 127,
      bytes: 13928918,
      pages: <int, int?>{1: null, 7: 2, 31: 26, 32: 27, 33: 28},
    ),
  ]) {
    testWidgets(fixture.name, (tester) async {
      final file = File(fixture.path);
      expect(await file.length(), fixture.bytes);
      expect(sha256.convert(await file.readAsBytes()).toString(), fixture.sha);
      final directory = await Directory.systemTemp.createTemp(
        'real_page_numbers_',
      );
      final book = textbookFixture(
        id: fixture.sha,
        pageCount: fixture.pageCount,
        fileSize: fixture.bytes,
      );
      final cache = TextbookContentCache(
        book: book,
        directoryProvider: () async => directory,
      );
      NativeTextbookPdfSource? source;
      try {
        source = await NativeTextbookPdfSource.open(
          path: file.path,
          book: book,
          cache: cache,
          token: TextbookDraftToken(),
        );
        final numbers = TextbookPageNumberService(
          pageCount: book.pageCount,
          loadPage: source.page,
          cache: cache,
        );
        for (final expected in fixture.pages.entries) {
          expect(await numbers.page(expected.key), expected.value);
        }
        final complete = await numbers.scan().last;
        expect(complete.scanned, fixture.pageCount);
        expect(complete.numbers.complete, isTrue);
        expect(complete.numbers.targets(2), [7]);
        expect(complete.numbers.targets(26), [31]);
        expect(tester.takeException(), isNull);
      } finally {
        await source?.close();
        await directory.delete(recursive: true);
      }
    }, skip: fixture.path.isEmpty);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('原生页码验收等待超时');
}
