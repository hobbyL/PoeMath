import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/textbook_course_draft_parser.dart';

typedef TextbookPdfSourceFactory = Future<TextbookPdfSource> Function({
  required String path,
  required Textbook book,
  required TextbookContentCache cache,
  required TextbookDraftToken token,
});

class TextbookGenerationProgress {
  const TextbookGenerationProgress(
    this.phase,
    this.done,
    this.total,
    this.message,
  );
  final String phase;
  final int done;
  final int total;
  final String message;
  bool get running => phase == 'running' || phase == 'locating';
}

class TextbookCourseGenerationService {
  TextbookCourseGenerationService(
    this.repository,
    this.files, {
    TextbookPdfSourceFactory? openSource,
  }) : _open = openSource ?? NativeTextbookPdfSource.open;
  final TextbookCourseRepository repository;
  final TextbookFileService files;
  final TextbookPdfSourceFactory _open;
  final _parser = TextbookCourseDraftParser();

  Future<void> run(
    Textbook book,
    TextbookCatalogEntry entry,
    String path,
    TextbookDraftToken token,
    void Function(TextbookGenerationProgress) emit,
    void Function() changed, {
    bool refresh = false,
    String? lessonId,
  }) async {
    TextbookPdfSource? source;
    String? runId;
    var done = 0;
    var total = 0;
    try {
      emit(const TextbookGenerationProgress('locating', 0, 0, '正在读取原书目录…'));
      source = await _open(
        path: path,
        book: book,
        cache: files.contentCache(book),
        token: token,
      );
      source.check();
      var document = await repository.loadDocument(book);
      source.check();
      if (document?.generation == null ||
          refresh ||
          document!.generation!.parserVersion !=
              TextbookCourseDraftParser.version) {
        TextbookTocResult? toc;
        await for (final progress in source.toc(refresh: refresh)) {
          source.check();
          emit(
            TextbookGenerationProgress(
              'locating',
              0,
              0,
              '正在定位目录 ${progress.scanned}/${progress.total} 页…',
            ),
          );
          toc = progress.result ?? toc;
        }
        if (toc == null) throw const FormatException('未找到原书目录');
        final seed = _parser.seed(
          entry,
          toc,
          existing: document?.pack,
          previousPlans: document?.generation?.plans ?? [],
        );
        document = await repository.beginGeneration(
          book,
          seed,
          restart: refresh || document?.generation != null,
          check: source.check,
        );
        source.check();
        changed();
      }
      if (lessonId != null) {
        document = (await repository.updateGeneration(
          book,
          document.generation!.runId,
          (g) => g.copyWith(
            completed: g.completed.where((id) => id != lessonId).toList(),
            errors: {...g.errors}..remove(lessonId),
          ),
          check: source.check,
        ))!;
      }
      final generation = document.generation!;
      runId = generation.runId;
      total = generation.plans.length;
      done = generation.completed.length;
      await repository.updateGeneration(
        book,
        runId,
        (g) => g.copyWith(phase: 'running'),
        check: source.check,
      );
      final appendixPages = <TextbookPageText>[];
      // 低年级字表通常在册末，目录命中的附录可更早；最多保留表区页文。
      final appendixStarts = generation.plans
          .where((p) => p.title.contains('字表') || p.title.contains('词语表'))
          .map((p) => p.startPage);
      final start = appendixStarts.isEmpty
          ? (book.pageCount - 18).clamp(1, book.pageCount)
          : appendixStarts.reduce((a, b) => a < b ? a : b);
      for (var p = start; p <= book.pageCount; p++) {
        source.check();
        emit(
          TextbookGenerationProgress(
            'running',
            done,
            total,
            '正在读取册末字词表 · PDF 第$p页…',
          ),
        );
        try {
          appendixPages.add(await source.page(p));
        } on TextbookDraftCancelled {
          rethrow;
        } on Object {/* 单页失败不伪造目标，课目读取时会保留诊断。 */}
      }
      final tables = _parser.vocabularyTables(document.pack, appendixPages);
      appendixPages.clear();
      for (final plan in generation.plans) {
        source.check();
        if (lessonId != null && plan.id != lessonId) continue;
        if (generation.completed.contains(plan.id)) continue;
        emit(
          TextbookGenerationProgress(
            'running',
            done,
            total,
            '正在整理《${plan.title}》…',
          ),
        );
        try {
          final pages = <TextbookPageText>[];
          for (var p = plan.startPage; p <= plan.endPage; p++) {
            source.check();
            try {
              pages.add(await source.page(p));
            } on TextbookDraftCancelled {
              rethrow;
            } on Object {
              pages.add(
                TextbookPageText(
                  page: p,
                  text: '',
                  width: 1,
                  height: 1,
                  status: 'extraction_error',
                ),
              );
            }
          }
          source.check();
          final lesson =
              document!.pack.lessons.firstWhere((l) => l.id == plan.id);
          final parsed = _parser.parse(
            lesson,
            plan,
            pages,
            vocabulary: tables[plan.id] ?? [],
          );
          document = await repository.commitGeneratedLesson(
            book,
            runId,
            parsed.lesson,
            parsed.candidates,
            check: source.check,
          );
          done = document.generation!.completed.length;
          changed();
        } on TextbookDraftCancelled {
          rethrow;
        } on FormatException catch (error) {
          await repository.updateGeneration(
            book,
            runId,
            (g) => g.copyWith(
              errors: {...g.errors, plan.id: error.message.toString()},
            ),
            check: source.check,
          );
          changed();
        }
      }
      source.check();
      final result = await repository.updateGeneration(
        book,
        runId,
        (g) => g.copyWith(
          phase: g.errors.isNotEmpty
              ? 'failed'
              : g.completed.length == g.plans.length
                  ? 'ready'
                  : 'paused',
        ),
        check: source.check,
      );
      changed();
      final failed = result?.generation?.errors.length ?? 0;
      emit(
        TextbookGenerationProgress(
          result?.generation?.phase ?? 'failed',
          done,
          total,
          failed == 0 ? '已整理 $done 课，内容和范围仍需逐项核对' : '已保存 $done 课，$failed 课需要重试',
        ),
      );
    } on TextbookDraftCancelled {
      if (runId != null) {
        await repository.updateGeneration(
          book,
          runId,
          (g) => g.copyWith(phase: 'paused'),
        );
      }
      changed();
      emit(
        TextbookGenerationProgress('paused', done, total, '已暂停，完成的课目已保存在本机'),
      );
    } on Object {
      if (runId != null) {
        await repository.updateGeneration(
          book,
          runId,
          (g) => g.copyWith(phase: 'failed'),
        );
      }
      changed();
      rethrow;
    } finally {
      // 所有页读取已返回后才关闭独立文档，暂停不抢先 dispose 正在读取的页面。
      await source?.close();
    }
  }
}
