import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_course_review_page.dart';

/// Uses an already installed catalog PDF, and an isolated course/cache directory.
/// Never clears app data or replaces the user's existing course files.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '原生离线：首次自动整理、暂停续跑、原书对照、编辑审核和冷启动恢复',
    (tester) async {
      final catalog = await const TextbookCatalogRepository().load();
      final entry = catalog
          .singleWhere((e) => e.book.grade == 1 && e.book.semester == '下');
      final book = entry.book;
      final path =
          '/data/user/0/com.poemath.app/files/textbooks/${book.pdfSha256}.pdf';
      expect(
        await File(path).length(),
        book.fileSize,
        reason: '先以正常 App 下载/导入一年级下册，不允许测试清理用户教材',
      );
      final directory = await Directory.systemTemp.createTemp('course_native_');
      final courses =
          TextbookCourseRepository(directoryProvider: () async => directory);
      final files =
          TextbookFileService(directoryProvider: () async => directory);
      final oldHttp = HttpOverrides.current;
      final offline = _OfflineHttp();
      HttpOverrides.global = offline;
      ProviderContainer makeContainer() => ProviderContainer(
            overrides: [
              textbookListProvider.overrideWithValue([book]),
              textbookLocalListProvider.overrideWithValue([book]),
              textbookCourseRepositoryProvider.overrideWithValue(courses),
              textbookFileServiceProvider.overrideWithValue(files),
              textbookCatalogProvider.overrideWith((ref) async => [entry]),
              textbookPathProvider.overrideWith(
                  (ref, id) async => id == book.pdfSha256 ? path : null,),
            ],
          );
      var container = makeContainer();
      final watch = Stopwatch()..start();
      int? firstLessonMs;
      try {
        Future<void> open() async {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  home: TextbookCourseReviewPage(bookId: book.pdfSha256),),
            ),
          );
          await tester.pump();
        }

        await open();
        await _until(
            tester,
            () =>
                (container
                        .read(textbookGenerationProvider)[book.pdfSha256]
                        ?.done ??
                    0) >
                0,);
        firstLessonMs = watch.elapsedMilliseconds;
        await container
            .read(textbookGenerationProvider.notifier)
            .stop(book.pdfSha256);
        var document = (await courses.loadDocument(book))!;
        expect(document.generation!.completed, isNotEmpty);
        expect(document.generation!.completed.length,
            lessThan(document.generation!.plans.length),);
        final firstSaved = document.pack.lessons.first.toJson();
        await _until(tester, () => find.text('继续整理').evaluate().isNotEmpty);
        await _tap(tester, find.text('继续整理'), settle: false);
        await _until(
            tester,
            () =>
                container
                    .read(textbookGenerationProvider)[book.pdfSha256]
                    ?.phase ==
                'ready',);
        document = (await courses.loadDocument(book))!;
        expect(document.pack.lessons.first.toJson(), firstSaved);
        expect(document.generation!.completed.length,
            document.generation!.plans.length,);
        expect(document.generation!.errors, isEmpty);
        final lesson = document.pack.lessons.first;
        expect(lesson.writingCharacters.length, 6);
        expect(lesson.paragraphs, isNotEmpty);
        await _tap(tester, find.byKey(ValueKey('course-lesson-${lesson.id}')));
        final paragraph = lesson.paragraphs.first;
        await _tap(
            tester, find.byKey(ValueKey('course-target-${paragraph.id}')),);
        await _tap(tester, find.text('原书'), settle: false);
        await _until(
          tester,
          () =>
              find.byType(PdfViewer).evaluate().isNotEmpty &&
              tester
                  .widget<PdfViewer>(find.byType(PdfViewer))
                  .controller!
                  .isReady,
        );
        Navigator.of(tester.element(find.byType(PdfViewer))).pop();
        await tester.pumpAndSettle();
        await _until(
            tester, () => find.byTooltip('编辑内容').evaluate().isNotEmpty,);
        await _tap(tester, find.byTooltip('编辑内容'));
        final text = find.widgetWithText(TextField, '正文');
        await tester.enterText(text, '${paragraph.text}\n本机离线验收。');
        await _tap(tester, find.text('保存修改'));
        await _until(
            tester, () => find.byTooltip('编辑内容').evaluate().isNotEmpty,);
        for (final label in ['已对照原书页码和来源', '已逐项核对内容']) {
          await _tap(tester, find.text(label));
        }
        await tester.enterText(find.widgetWithText(TextField, '审核人'), '离线验收');
        await tester.enterText(
            find.widgetWithText(TextField, '核对说明 / 退回原因'), '自有测试文字，非教材审核',);
        await _tap(tester, find.text('通过审核'));
        await _until(tester, () => find.byKey(ValueKey('course-target-${paragraph.id}')).evaluate().isNotEmpty);
        final saved = (await courses.loadDocument(book))!;
        expect(
            saved.pack.nodes.firstWhere((n) => n.id == paragraph.id).isApproved,
            isTrue,);
        await tester.pumpWidget(const SizedBox());
        await container
            .read(textbookGenerationProvider.notifier)
            .stop(book.pdfSha256);
        container.dispose();
        final reopened =
            TextbookCourseRepository(directoryProvider: () async => directory);
        expect((await reopened.loadDocument(book))!.toJson(), saved.toJson());
        container = makeContainer();
        await open();
        await _until(
            tester,
            () => find
                .byKey(ValueKey('course-lesson-${lesson.id}'))
                .evaluate()
                .isNotEmpty,);
        expect(
          container.read(textbookGenerationProvider),
          isEmpty,
          reason: '冷启动已有草稿不自动后台重跑',
        );
        expect(offline.requests, 0);
        // Metadata only. Keep extracted content and PDF out of logs and the repo.
        // ignore: avoid_print
        print(
          jsonEncode({
            'nativeCourseAcceptance': true,
            'lessons': saved.generation!.completed.length,
            'firstLessonMs': firstLessonMs,
            'milliseconds': watch.elapsedMilliseconds,
            'peakRssBytes': ProcessInfo.maxRss,
            'networkRequests': offline.requests,
          }),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await container
            .read(textbookGenerationProvider.notifier)
            .stop(book.pdfSha256);
        container.dispose();
        HttpOverrides.global = oldHttp;
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

class _OfflineHttp extends HttpOverrides {
  int requests = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('离线验收禁止网络请求');
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 1800; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待本机课程页面超时');
}

Future<void> _tap(WidgetTester tester, Finder finder,
    {bool settle = true,}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await _until(tester, () => finder.hitTestable().evaluate().isNotEmpty);
  await tester.tap(finder);
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}
