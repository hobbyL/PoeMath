import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_pdf_graphics.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';
import 'package:poemath/domain/math_textbook_course_plan.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';

typedef MathTextbookPageLoader = Future<MathTextbookPageLayout> Function(
  int page,
);

class MathTextbookGenerationService {
  MathTextbookGenerationService(this.repository, this.files);
  final MathTextbookCourseRepository repository;
  final TextbookFileService files;

  /// 每次整理一个完整课时；成功保存后才报告完成。
  Future<MathTextbookCourse> generate({
    required Textbook book,
    required String title,
    required int startPage,
    required int endPage,
    required TextbookDraftToken token,
    required void Function() authorize,
    required void Function(int completed, int total) onProgress,
    MathTextbookPageLoader? pageLoader,
    String unitTitle = '',
    bool needsAlignment = false,
    MathTextbookCourseRange? legacyRange,
  }) async {
    if (book.subject != TextbookSubject.math) {
      throw const FormatException('请先将这本教材的学科确认为数学');
    }
    if (title.trim().isEmpty ||
        title.length > 200 ||
        startPage < 1 ||
        endPage < startPage ||
        endPage > book.pageCount ||
        endPage - startPage >= 40) {
      throw const FormatException('请填写课时名称及不超过 40 页的原书页范围');
    }
    final epoch = repository.generation(book.pdfSha256);
    final cache = files.contentCache(book);
    final cacheRevision = cache.revision;
    void check() {
      token.check();
      authorize();
      repository.checkGeneration(book.pdfSha256, epoch);
      if (cache.revision != cacheRevision) throw const TextbookDraftCancelled();
    }

    PdfDocument? document;
    try {
      check();
      if (pageLoader == null) {
        final path = await files.installedPath(book);
        check();
        if (path == null) throw const FormatException('请先导入本书 PDF');
        await pdfrxFlutterInitialize();
        check();
        document = await PdfDocument.openFile(path);
        check();
        if (document.pages.length != book.pageCount) {
          throw const FormatException('原书页数与登记信息不符');
        }
      }
      final pages = <MathTextbookPageLayout>[];
      for (var number = startPage; number <= endPage; number++) {
        check();
        MathTextbookPageLayout page;
        try {
          if (pageLoader != null) {
            page = await pageLoader(number);
          } else {
            final text = await loadTextbookPdfPage(
              document: document!,
              number: number,
              checkAvailable: check,
              cache: cache,
            );
            check();
            MathTextbookGraphics graphics;
            try {
              graphics = await document.useNativeDocumentHandle(
                (handle) => readMathTextbookGraphics(
                  handle,
                  number,
                  modulePath: Pdfrx.pdfiumModulePath,
                ),
              );
            } on Object catch (error, stackTrace) {
              AppLogger.e(
                '数学页面绘图读取失败',
                tag: 'MathTextbook',
                error: error,
                stackTrace: stackTrace,
              );
              graphics = MathTextbookGraphics(complete: false);
            }
            page = MathTextbookPageLayout(text: text, graphics: graphics);
          }
        } on TextbookDraftCancelled {
          rethrow;
        } on Object catch (error, stackTrace) {
          check();
          AppLogger.e(
            '数学页面提取失败，保留原书页',
            tag: 'MathTextbook',
            error: error,
            stackTrace: stackTrace,
          );
          page = MathTextbookPageLayout(
            text: TextbookPageText(
              page: number,
              text: '',
              width: 1,
              height: 1,
              status: 'extraction_error',
            ),
            graphics: MathTextbookGraphics(complete: false),
          );
        }
        check();
        if (page.text.page != number) throw const FormatException('数学页面来源不一致');
        pages.add(page);
        onProgress(number - startPage + 1, endPage - startPage + 1);
        await Future<void>.delayed(Duration.zero);
      }
      check();
      final parsed = organizeMathTextbookLesson(
        const MathTextbookDraftParser().parse(
          title: title,
          startPage: startPage,
          endPage: endPage,
          pages: pages,
        ),
      );
      final lesson = parsed.edit(
        learning: needsAlignment
            ? MathTextbookLearning(
                unitTitle: unitTitle,
                knowledgePoints: const [],
                exercises: const [],
                practicePlans: const [],
              )
            : seedMathTextbookLearning(parsed, unitTitle: unitTitle),
      );
      String? legacyDigest;
      String? previousDigest;
      if (legacyRange != null && legacyRange.lessonId == lesson.id) {
        final old = const MathTextbookDraftParser().parse(
          title: legacyRange.title,
          startPage: startPage,
          endPage: endPage,
          pages: pages,
          classifyContent: false,
        );
        legacyDigest = old
            .edit(
              learning: legacyMathTextbookLearning(
                old,
                unitTitle: legacyRange.unitTitle,
              ),
            )
            .contentDigest(book.pdfSha256);
        final previous = organizeMathTextbookLesson(
          const MathTextbookDraftParser(legacyLayout: true).parse(
            title: legacyRange.title,
            startPage: startPage,
            endPage: endPage,
            pages: pages,
          ),
          legacyLayout: true,
        );
        previousDigest = previous
            .edit(
              learning: legacyRange.needsAlignment
                  ? MathTextbookLearning(
                      unitTitle: legacyRange.unitTitle,
                      knowledgePoints: const [],
                      exercises: const [],
                      practicePlans: const [],
                    )
                  : seedMathTextbookLearning(
                      previous,
                      unitTitle: legacyRange.unitTitle,
                      legacyLayout: true,
                    ),
            )
            .contentDigest(book.pdfSha256);
      }
      check();
      return await repository.saveGenerated(
        book,
        lesson,
        generation: epoch,
        authorize: check,
        unmodifiedLegacyDigest: legacyDigest,
        unmodifiedPreviousDigest: previousDigest,
      );
    } finally {
      await document?.dispose();
    }
  }

  /// 顺序生成目录区间，逐段保存；取消或失败保留已存草稿与人工成果。
  Future<MathTextbookCourse> generateBook({
    required Textbook book,
    required TextbookDraftToken token,
    required void Function() authorize,
    required void Function(int completed, int total) onProgress,
    void Function(String message)? onStatus,
    void Function(int completed, int total)? onLessonProgress,
    void Function()? onSaved,
    bool refresh = false,
    MathTextbookPageLoader? pageLoader,
    TextbookTocResult? toc,
  }) async {
    if (book.subject != TextbookSubject.math) {
      throw const FormatException('请先确认教材学科为数学');
    }
    final epoch = repository.generation(book.pdfSha256),
        cache = files.contentCache(book),
        revision = cache.revision;
    void check() {
      token.check();
      authorize();
      repository.checkGeneration(book.pdfSha256, epoch);
      if (cache.revision != revision) throw const TextbookDraftCancelled();
    }

    PdfDocument? document;
    try {
      check();
      var current = await repository.load(book);
      check();
      final previousOutline = current?.outline;
      final outdated =
          previousOutline != null &&
          previousOutline.organizationVersion < mathTextbookOrganizationVersion;
      var outline = refresh || outdated ? null : previousOutline;
      if (pageLoader == null) {
        final path = await files.installedPath(book);
        check();
        if (path == null) throw const FormatException('请先导入本书 PDF');
        await pdfrxFlutterInitialize();
        check();
        document = await PdfDocument.openFile(path);
        check();
        if (document.pages.length != book.pageCount) {
          throw const FormatException('原书页数与登记信息不符');
        }
      }
      Future<TextbookPageText> textPage(int number) async {
        check();
        if (pageLoader != null) return (await pageLoader(number)).text;
        return loadTextbookPdfPage(
          document: document!,
          number: number,
          checkAvailable: check,
          cache: cache,
        );
      }

      if (outline == null) {
        var directory = toc;
        if (directory == null) {
          final scanner = TextbookTocService(
            pageCount: book.pageCount,
            cache: cache,
            loadOutline: () async {
              if (document == null) return <TextbookTocEntry>[];
              check();
              final outline = await document.loadOutline();
              check();
              final entries = <TextbookTocEntry>[];
              void visit(List<PdfOutlineNode> nodes, int level) {
                for (final node in nodes) {
                  entries.add(
                    TextbookTocEntry(
                      title: node.title,
                      page: node.dest?.pageNumber,
                      level: level,
                    ),
                  );
                  visit(node.children, level + 1);
                }
              }

              visit(outline, 0);
              return entries;
            },
            loadPage: (number) async =>
                TextbookTocPage.fromPageText(await textPage(number)),
          );
          await for (final progress in scanner.scan(
            refresh: refresh || outdated,
          )) {
            check();
            onStatus?.call(
              '正在定位目录 · 已读取 ${progress.scanned}/${progress.total} 页',
            );
            if (progress.result != null) directory = progress.result;
          }
        }
        check();
        final planned = planMathTextbookCourse(
          directory ??
              const TextbookTocResult(
                entries: [],
                source: TextbookTocSource.text,
                hasText: false,
              ),
          book.pageCount,
        ).withCompleted(const []);
        final legacyRanges = <MathTextbookCourseRange>[];
        if (previousOutline != null) {
          legacyRanges.addAll(
            outdated ? previousOutline.ranges : previousOutline.legacyRanges,
          );
        }
        outline = MathTextbookCourseOutline.fromJson({
          ...planned.toJson(),
          'legacyRanges': legacyRanges.map((range) => range.toJson()).toList(),
        });
        current = await repository.saveOutline(
          book,
          outline,
          generation: epoch,
          authorize: check,
        );
        onSaved?.call();
      } else if (outline.completedLessonIds == null) {
        // Older drafts already contain whole saved lessons, but no run progress.
        final saved = current!.lessons.map((lesson) => lesson.id).toSet();
        outline = outline.withCompleted(
          outline.ranges.map((range) => range.lessonId).where(saved.contains),
        );
        current = await repository.saveOutline(
          book,
          outline,
          generation: epoch,
          authorize: check,
        );
        onSaved?.call();
      }
      check();
      final completedIds = outline.completedLessonIds!.toSet();
      final total = outline.ranges.fold<int>(
        0,
        (count, range) => count + range.endPage - range.startPage + 1,
      );
      var completed = outline.ranges
          .where((range) => completedIds.contains(range.lessonId))
          .fold<int>(
            0,
            (count, range) => count + range.endPage - range.startPage + 1,
          );
      var result = current!;
      onProgress(completed, total);
      onLessonProgress?.call(completedIds.length, outline.ranges.length);
      for (final range in outline.ranges) {
        check();
        if (completedIds.contains(range.lessonId)) continue;
        onStatus?.call('正在整理“${range.title}”');
        result = await generate(
          book: book,
          title: range.title,
          startPage: range.startPage,
          endPage: range.endPage,
          unitTitle: range.unitTitle,
          needsAlignment: range.needsAlignment,
          legacyRange: outline.legacyRanges
              .where((old) => old.lessonId == range.lessonId)
              .firstOrNull,
          token: token,
          authorize: check,
          onProgress: (count, _) => onProgress(completed + count, total),
          pageLoader:
              pageLoader ??
              (number) async {
                final text = await textPage(number);
                check();
                MathTextbookGraphics graphics;
                try {
                  graphics = await document!.useNativeDocumentHandle(
                    (handle) => readMathTextbookGraphics(
                      handle,
                      number,
                      modulePath: Pdfrx.pdfiumModulePath,
                    ),
                  );
                } on Object catch (error, stackTrace) {
                  check();
                  AppLogger.e(
                    '数学全书绘图读取失败，保留原书区域',
                    tag: 'MathTextbook',
                    error: error,
                    stackTrace: stackTrace,
                  );
                  graphics = MathTextbookGraphics(complete: false);
                }
                check();
                return MathTextbookPageLayout(text: text, graphics: graphics);
              },
        );
        check();
        result = await repository.completeRange(
          book,
          range.lessonId,
          generation: epoch,
          authorize: check,
        );
        completed += range.endPage - range.startPage + 1;
        completedIds.add(range.lessonId);
        onLessonProgress?.call(completedIds.length, outline.ranges.length);
        onSaved?.call();
        check();
      }
      onProgress(total, total);
      return result;
    } finally {
      await document?.dispose();
    }
  }
}
