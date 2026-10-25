import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_management_page.dart';
import 'package:poemath/features/textbook/textbook_shelf_page.dart';
import 'package:poemath/features/textbook/textbook_detail_page.dart';
import 'package:poemath/features/textbook/textbook_reader_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import '../test/helpers/textbook_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实 PDFium：App 导入、离线渲染、跳页、续读与重导', (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('textbook_journey_');
    // 独立测试 box/目录；不打开或改写正常应用的学习数据。
    final box =
        await Hive.openBox<dynamic>('textbook_journey', path: directory.path);
    final repo = TextbookRepository(box: box);
    final service =
        TextbookFileService(directoryProvider: () async => directory);
    final source =
        await File('${directory.path}/sample.pdf').writeAsBytes(syntheticPdf());
    final router = GoRouter(
      initialLocation: AppRoutes.textbookManagement,
      routes: [
        GoRoute(
          path: AppRoutes.textbookManagement,
          builder: (_, __) => TextbookManagementPage(
            pickPdf: () async => PlatformFile(
              name: 'PoeMath sample.pdf',
              path: source.path,
              size: source.lengthSync(),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.textbookManageDetail,
          builder: (_, state) => TextbookDetailPage(
            bookId: state.pathParameters['id']!,
            manage: true,
          ),
        ),
        GoRoute(
          path: AppRoutes.textbookRead,
          builder: (_, state) => TextbookReaderPage(
            bookId: state.pathParameters['id']!,
            initialPage: state.extra is int ? state.extra as int : null,
          ),
        ),
      ],
    );
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            textbookRepositoryProvider.overrideWithValue(repo),
            textbookFileServiceProvider.overrideWithValue(service),
            textbookCatalogProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await _until(tester, () => find.byTooltip('导入').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('导入'));
      await _until(tester, () => find.text('登记教材').evaluate().isNotEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('三年级').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上册').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入教材'));
      await _until(tester, () => repo.list().length == 1);
      final book = repo.list().single;
      expect(book.pageCount, 3);
      expect(book.title, 'PoeMath sample');
      final installed = await service.installedPath(book);
      expect(await File(installed!).readAsBytes(), syntheticPdf());
      await _until(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
      final cover = tester.widget<RawImage>(
        find.descendant(
          of: find.byType(TextbookPdfCover),
          matching: find.byType(RawImage),
        ),
      );
      expect(cover.image!.width, 576);
      expect(cover.image!.height, 768);
      expect(cover.fit, BoxFit.contain);
      final coverPixels = await cover.image!.toByteData();
      expect(coverPixels!.buffer.asUint8List().toSet().length, greaterThan(1));
      // 验证真实原生渲染，而非仅打开文档或挂载 placeholder。
      final document = await PdfDocument.openFile(installed);
      try {
        final image =
            await document.pages.first.render(width: 150, height: 200);
        expect(image, isNotNull);
        expect(image!.pixels.length, 150 * 200 * 4);
        expect(image.pixels.toSet().length, greaterThan(1));
        image.dispose();
      } finally {
        await document.dispose();
      }
      router.go(AppRoutes.textbookManageDetailOf(book.pdfSha256));
      await _until(
        tester,
        () =>
            find.byType(TextbookPdfPreview).evaluate().isNotEmpty &&
            find.byType(RawImage).evaluate().isNotEmpty,
      );
      final previewImage = tester.widget<RawImage>(find.byType(RawImage).first);
      final previewPixels = await previewImage.image!.toByteData();
      expect(
        previewPixels!.buffer.asUint8List().toSet().length,
        greaterThan(1),
      );
      expect(find.text('版本信息'), findsNothing);
      expect(find.textContaining('MB'), findsNothing);
      expect(find.byTooltip('移除本地 PDF'), findsOneWidget);
      await _until(
        tester,
        () =>
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, '下一页'),
                )
                .onPressed !=
            null,
      );
      await tester.tap(find.text('下一页'));
      await _until(
        tester,
        () =>
            find.byType(PageView).evaluate().isNotEmpty &&
            tester.widget<PageView>(find.byType(PageView)).controller!.page ==
                1,
      );
      await _until(
        tester,
        () => repo.reading('default', book.pdfSha256).page == 2,
      );
      expect(repo.reading('default', book.pdfSha256).page, 2);
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await _until(
        tester,
        () =>
            find.byType(PageView).evaluate().isNotEmpty &&
            tester.widget<PageView>(find.byType(PageView)).controller!.page ==
                2,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('上一页'));
      await _until(
        tester,
        () =>
            find.byType(PageView).evaluate().isNotEmpty &&
            tester.widget<PageView>(find.byType(PageView)).controller!.page ==
                1,
      );
      await tester.pump(const Duration(milliseconds: 100));
      final previewDocument =
          tester.widget<PdfPageView>(find.byType(PdfPageView).first).document;
      for (final target in [3, 2]) {
        await tester.tap(find.byTooltip('搜索本书'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.enterText(find.byType(TextField), 'sample - $target');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await _until(
          tester,
          () => find.text('第 $target 页 · 1 处').evaluate().isNotEmpty,
        );
        expect(find.text('第 $target 页 · 1 处'), findsOneWidget);
        await tester.tap(
          find.byKey(ValueKey('textbook-search-result-$target')),
        );
        await _until(
          tester,
          () =>
              find.byType(PageView).evaluate().isNotEmpty &&
              tester.widget<PageView>(find.byType(PageView)).controller!.page ==
                  target - 1 &&
              _detailReadEnabled(tester),
        );
        await _until(
          tester,
          () => repo.reading('default', book.pdfSha256).page == target,
        );
        expect(repo.reading('default', book.pdfSha256).page, target);
        expect(
          tester.widget<PdfPageView>(find.byType(PdfPageView).first).document,
          same(previewDocument),
        );
      }
      router.go(AppRoutes.textbookManagement);
      await _until(
        tester,
        () => find.byType(TextbookPdfPreview).evaluate().isEmpty,
      );
      router.go(AppRoutes.textbookManageDetailOf(book.pdfSha256));
      await _until(
        tester,
        () =>
            find.byType(PageView).evaluate().isNotEmpty &&
            tester.widget<PageView>(find.byType(PageView)).controller!.page ==
                1 &&
            _detailReadEnabled(tester),
      );
      expect(find.text('2 / 3'), findsOneWidget);
      expect(repo.reading('default', book.pdfSha256).page, 2);
      await tester.tap(find.byKey(const ValueKey('textbook-detail-read')));
      await _until(
        tester,
        () =>
            find.byType(PdfViewer).evaluate().isNotEmpty &&
            tester
                .widget<PdfViewer>(find.byType(PdfViewer))
                .controller!
                .isReady,
      );
      expect(
        tester.widget<PdfViewer>(find.byType(PdfViewer)).initialPageNumber,
        2,
      );
      await _until(
        tester,
        () =>
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.chevron_right),
                )
                .onPressed !=
            null,
      );
      await tester.tap(find.byTooltip('下一页'));
      await _until(
        tester,
        () => repo.reading('default', book.pdfSha256).page == 3,
      );
      await tester.tap(find.byTooltip('上一页'));
      await _until(
        tester,
        () => repo.reading('default', book.pdfSha256).page == 2,
      );
      expect(find.text('PDF 第 2 / 3 页'), findsOneWidget);
      router.go(AppRoutes.textbookManagement);
      await _until(tester, () => find.text('书籍管理').evaluate().isNotEmpty);
      await _until(tester, () => find.byType(PdfViewer).evaluate().isEmpty);
      expect(repo.reading('default', book.pdfSha256).page, 2);
      router.go(AppRoutes.textbookReadOf(book.pdfSha256));
      await _until(
        tester,
        () =>
            find.byType(PdfViewer).evaluate().isNotEmpty &&
            tester
                .widget<PdfViewer>(find.byType(PdfViewer))
                .controller!
                .isReady,
      );
      expect(
        tester.widget<PdfViewer>(find.byType(PdfViewer)).initialPageNumber,
        2,
      );
      router.go(AppRoutes.textbookManageDetailOf(book.pdfSha256));
      await _until(
        tester,
        () => find.byType(TextbookPdfPreview).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('移除本地 PDF'));
      await _until(tester, () => find.text('移除本地 PDF？').evaluate().isNotEmpty);
      await tester.tap(find.text('移除 PDF'));
      await _until(
        tester,
        () => find.byType(TextbookPdfPreview).evaluate().isEmpty,
      );
      await _until(
        tester,
        () => find.textContaining('本地 PDF 已移除或丢失。').evaluate().isNotEmpty,
      );
      expect(await service.installedPath(book), isNull);
      expect(repo.reading('default', book.pdfSha256).page, 2);
      final reimported = await service.importPdf(
        sourcePath: source.path,
        token: TextbookImportToken(),
      );
      expect(reimported.sha256, book.pdfSha256);
      expect(repo.reading('default', book.pdfSha256).page, 2);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });

  testWidgets(
    '公开教材：书架直接下载、版本标注、真实渲染及同版重下续读',
    (tester) async {
      final directory =
          await Directory.systemTemp.createTemp('textbook_cloud_');
      final box =
          await Hive.openBox<dynamic>('textbook_cloud', path: directory.path);
      final repo = TextbookRepository(box: box);
      final files = TextbookFileService(
        directoryProvider: () async => directory,
        requestTimeout: const Duration(seconds: 45),
      );
      final catalog = await const TextbookCatalogRepository().load();
      final entry = catalog.singleWhere(
        (entry) => entry.book.grade == 6 && entry.book.semester == '上',
      );
      final router = GoRouter(
        initialLocation: AppRoutes.textbookShelf,
        routes: [
          GoRoute(
            path: AppRoutes.textbookShelf,
            builder: (_, __) => const TextbookShelfPage(),
          ),
          GoRoute(
            path: AppRoutes.textbookDetail,
            builder: (_, state) =>
                TextbookDetailPage(bookId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: AppRoutes.textbookRead,
            builder: (_, state) =>
                TextbookReaderPage(bookId: state.pathParameters['id']!),
          ),
        ],
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              textbookRepositoryProvider.overrideWithValue(repo),
              textbookFileServiceProvider.overrideWithValue(files),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await _until(
          tester,
          () => find.byTooltip('下载一年级上册').evaluate().isNotEmpty,
        );
        await tester.scrollUntilVisible(find.byTooltip('下载六年级上册'), 300);
        await tester.tap(find.byTooltip('下载六年级上册'));
        for (var i = 0;
            i < 1800 && repo.find(entry.book.pdfSha256) == null;
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          repo.find(entry.book.pdfSha256),
          isNotNull,
          reason: '真实上游教材下载应成功，失败时书架保留明确错误',
        );
        final path = await files.installedPath(entry.book);
        expect(path, isNotNull);
        expect(await File(path!).length(), entry.book.fileSize);
        final document = await PdfDocument.openFile(path);
        try {
          expect(document.pages.length, entry.book.pageCount);
          final image =
              await document.pages.first.render(width: 150, height: 200);
          expect(image, isNotNull);
          expect(image!.pixels.toSet().length, greaterThan(1));
          image.dispose();
        } finally {
          await document.dispose();
        }
        router.go(AppRoutes.textbookReadOf(entry.book.pdfSha256));
        await _until(
          tester,
          () => find.byType(PdfViewer).evaluate().isNotEmpty,
        );
        await _until(
          tester,
          () =>
              tester
                  .widget<IconButton>(
                    find.widgetWithIcon(IconButton, Icons.chevron_right),
                  )
                  .onPressed !=
              null,
        );
        await tester.tap(find.byTooltip('下一页'));
        await _until(
          tester,
          () => repo.reading('default', entry.book.pdfSha256).page == 2,
        );
        router.go(AppRoutes.textbookShelf);
        await _until(tester, () => find.byType(PdfViewer).evaluate().isEmpty);
        await files.removePdf(entry.book.pdfSha256);
        expect(repo.reading('default', entry.book.pdfSha256).page, 2);
        await files.downloadPdf(entry: entry, token: TextbookImportToken());
        expect(repo.reading('default', entry.book.pdfSha256).page, 2);
        expect(repo.reading('other', entry.book.pdfSha256).page, 1);
        // 五下原raw来源可能限流，服务可自动转同一blob的GitHub API。
        final old = catalog.singleWhere(
          (entry) => entry.book.grade == 5 && entry.book.semester == '下',
        );
        await files.downloadPdf(entry: old, token: TextbookImportToken());
        final oldDocument =
            await PdfDocument.openFile((await files.installedPath(old.book))!);
        expect(oldDocument.pages.length, 131);
        await oldDocument.dispose();
        expect(old.editionLabel, '2019年12月第1版（旧版）');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await box.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('TEXTBOOK_NETWORK_ACCEPTANCE'),
  );
}

bool _detailReadEnabled(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('textbook-detail-read'));
  if (finder.evaluate().isEmpty) return false;
  final button = tester.widget(finder);
  if (button is IconButton) return button.onPressed != null;
  return button is ButtonStyleButton && button.onPressed != null;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待教材页面或 PDF 就绪超时');
}
