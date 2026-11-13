import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_reading_content.dart';
import 'package:poemath/domain/textbook_text_display.dart';
import 'package:poemath/domain/textbook_printed_page.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';
import 'package:poemath/data/repositories/textbook_progress_cleanup.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/data/repositories/textbook_download_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';
import 'package:poemath/core/services/textbook_course_generation_service.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/features/textbook/providers/textbook_generation_controller.dart';

final textbookRepositoryProvider = Provider<TextbookRepository>(
  (ref) => TextbookRepository(),
);
final textbookDownloadRepositoryProvider = Provider<TextbookDownloadRepository>(
  (ref) => TextbookDownloadRepository(),
);
final textbookProgressCleanupProvider = Provider<TextbookProgressCleanup>(
  (ref) => TextbookProgressCleanup(),
);
final textbookFileServiceProvider = Provider<TextbookFileService>(
  (ref) => TextbookFileService(),
);
final textbookCourseRepositoryProvider = Provider<TextbookCourseRepository>(
  (ref) => TextbookCourseRepository(),
);
final textbookCourseProvider = FutureProvider.autoDispose
    .family<TextbookCoursePack?, String>((ref, id) async {
      final book = ref
          .watch(textbookListProvider)
          .where((book) => book.pdfSha256 == id)
          .firstOrNull;
      if (book == null) return null;
      return ref.watch(textbookCourseRepositoryProvider).load(book);
    });
final textbookCourseDocumentProvider = FutureProvider.autoDispose
    .family<TextbookCourseDocument?, String>((ref, id) async {
      final book = ref
          .watch(textbookListProvider)
          .where((b) => b.pdfSha256 == id)
          .firstOrNull;
      if (book == null) return null;
      return ref.watch(textbookCourseRepositoryProvider).loadDocument(book);
    });
final textbookReadingContentProvider = FutureProvider.autoDispose
    .family<TextbookReadingContent?, ({String bookId, String lessonId})>((
      ref,
      key,
    ) async {
      final book = ref
          .watch(textbookListProvider)
          .where((book) => book.pdfSha256 == key.bookId)
          .firstOrNull;
      if (book == null) return null;
      final files = ref.watch(textbookFileServiceProvider);
      final course = ref.watch(textbookCourseProvider(key.bookId).future);
      final token = TextbookDraftToken();
      ref.onDispose(token.cancel);
      TextbookPdfSource? source;
      TextbookCourseLesson? lesson;
      try {
        final pack = await course;
        token.check();
        lesson = pack?.lessons
            .where((lesson) => lesson.id == key.lessonId)
            .firstOrNull;
        if (lesson == null || pack == null) return null;
        TextbookCourseDocument? document;
        try {
          document = await ref.watch(
            textbookCourseDocumentProvider(key.bookId).future,
          );
        } on Object {
          // 导入课程或检查点不可用时，仍可按保存正文恢复布局。
        }
        token.check();
        final resolver = TextbookReadingResolver();
        final plan = resolver.automaticPlan(document, lesson);
        final cache = files.contentCache(book);
        final revision = cache.revision;
        final pages = <int, TextbookPageText>{};
        final numbers =
            lesson.paragraphs
                .expand((paragraph) => paragraph.sources)
                .map((source) => source.pdfPage)
                .toSet()
                .toList()
              ..sort();
        if (plan != null) {
          numbers.clear();
          numbers.addAll([
            for (var p = plan.startPage; p <= plan.endPage; p++) p,
          ]);
        }
        for (final number in numbers) {
          token.check();
          if (cache.revision != revision) return TextbookReadingContent(lesson);
          var page = await cache.cachedPageLayout(number);
          token.check();
          if (page == null) {
            final localPath = await files.installedPath(book);
            token.check();
            if (localPath == null) continue;
            source ??= await NativeTextbookPdfSource.open(
              path: localPath,
              book: book,
              cache: cache,
              token: token,
            );
            page = await source.page(number);
          }
          pages[number] = page;
        }
        token.check();
        if (cache.revision != revision) return TextbookReadingContent(lesson);
        return resolver.resolve(
          pack,
          lesson,
          pages.values.toList(),
          document: document,
        );
      } on Object {
        // 原书缺失或布局不可匹配时使用课程已有分节；不能阻断阅读或改写课程。
        return lesson == null ? null : TextbookReadingContent(lesson);
      } finally {
        await source?.close();
      }
    });
final textbookReadingLayoutProvider = FutureProvider.autoDispose
    .family<
      Map<String, TextbookReadingLayout>,
      ({String bookId, String lessonId})
    >((ref, key) async {
      return (await ref.watch(textbookReadingContentProvider(key).future))
              ?.layouts ??
          const {};
    });
final textbookGenerationServiceProvider =
    Provider<TextbookCourseGenerationService>(
      (ref) => TextbookCourseGenerationService(
        ref.watch(textbookCourseRepositoryProvider),
        ref.watch(textbookFileServiceProvider),
      ),
    );
final textbookGenerationProvider =
    StateNotifierProvider<
      TextbookGenerationController,
      Map<String, TextbookGenerationProgress>
    >(
      (ref) => TextbookGenerationController(
        ref.watch(textbookGenerationServiceProvider),
        (id) {
          ref.invalidate(textbookCourseProvider(id));
          ref.invalidate(textbookCourseDocumentProvider(id));
        },
      ),
    );
final textbookLocalListProvider = Provider<List<Textbook>>(
  (ref) => ref.watch(textbookRepositoryProvider).list(),
);
final textbookCatalogProvider = FutureProvider<List<TextbookCatalogEntry>>(
  (ref) => const TextbookCatalogRepository().load(),
);
final textbookListProvider = Provider<List<Textbook>>((ref) {
  final local = ref.watch(textbookLocalListProvider);
  final catalog = ref.watch(textbookCatalogProvider).valueOrNull ?? [];
  final books = {for (final book in local) book.pdfSha256: book};
  for (final entry in catalog) {
    books.putIfAbsent(entry.book.pdfSha256, () => entry.book);
  }
  return books.values.toList();
});
final textbookDownloadsProvider =
    StateNotifierProvider<
      TextbookDownloadController,
      Map<String, TextbookDownloadState>
    >((ref) {
      return TextbookDownloadController(
        ref.watch(textbookFileServiceProvider),
        ref.watch(textbookRepositoryProvider),
        (id) {
          ref.invalidate(textbookLocalListProvider);
          ref.invalidate(textbookPathProvider(id));
        },
        downloads: ref.watch(textbookDownloadRepositoryProvider),
      );
    });
final textbookPathProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, id) async {
    // 管理页反复进出时保留检查结果：否则每次先闪「正在检查本地文件」占位，
    // 再闪「正在生成封面」，即使封面早已缓存。导入、下载、删除 PDF 的
    // 入口都会显式 invalidate 本 provider。
    ref.keepAlive();
    final book = ref
        .watch(textbookLocalListProvider)
        .where((book) => book.pdfSha256 == id)
        .firstOrNull;
    if (book == null) return null;
    return ref.watch(textbookFileServiceProvider).installedPath(book);
  },
);

/// 没有阅读器的书架/续读入口只提取保存位置，不在列表中索引全书。
final textbookPrintedPageProvider = FutureProvider.autoDispose
    .family<int?, ({String bookId, int page})>((ref, key) async {
      final book = ref
          .watch(textbookLocalListProvider)
          .where((book) => book.pdfSha256 == key.bookId)
          .firstOrNull;
      if (book == null) return null;
      final files = ref.watch(textbookFileServiceProvider);
      final token = TextbookDraftToken();
      ref.onDispose(token.cancel);
      final cache = files.contentCache(book);
      final path = await ref.watch(textbookPathProvider(key.bookId).future);
      token.check();
      if (path == null) throw StateError('本地课本文件缺失');
      final printed = await cache.pageNumber(key.page, () async {
        token.check();
        final layout = await cache.cachedPageLayout(key.page);
        token.check();
        if (layout != null) return printedTextbookPage(layout);
        NativeTextbookPdfSource? source;
        try {
          source = await NativeTextbookPdfSource.open(
            path: path,
            book: book,
            cache: cache,
            token: token,
          );
          return printedTextbookPage(await source.page(key.page));
        } finally {
          await source?.close();
        }
      });
      token.check();
      return printed;
    });
