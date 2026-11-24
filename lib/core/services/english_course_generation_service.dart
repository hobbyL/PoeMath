import 'package:poemath/core/services/textbook_course_generation_service.dart'
    show TextbookPdfSourceFactory;
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/domain/english_course_parser.dart';

class EnglishCourseGenerationService {
  EnglishCourseGenerationService(
    this.courses,
    this.files, {
    TextbookPdfSourceFactory? open,
  }) : _open = open ?? NativeTextbookPdfSource.open;
  final EnglishCourseRepository courses;
  final TextbookFileService files;
  final TextbookPdfSourceFactory _open;

  Future<void> run(
    Textbook book,
    TextbookDraftToken token,
    void Function(String message, int completed, int total) progress,
    void Function() changed, {
    bool refresh = false,
  }) async {
    final path = await files.installedPath(book);
    token.check();
    if (path == null) throw const FormatException('请先下载或导入英语原书');
    final source = await _open(
      path: path,
      book: book,
      cache: files.contentCache(book),
      token: token,
    );
    try {
      final pages = <TextbookPageText>[];
      for (var p = 1; p <= book.pageCount; p++) {
        source.check();
        progress('正在读取原书 $p / ${book.pageCount} 页', 0, 0);
        try {
          pages.add(await source.page(p));
        } on TextbookDraftCancelled {
          rethrow;
        } on Object {
          source.check();
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
      final parser = EnglishCourseParser();
      final outline = parser.outline(book, pages);
      final course = await courses.seed(book, outline, check: source.check);
      changed();
      final vocabulary = parser.vocabulary(pages);
      var done = 0;
      for (final plan in outline.lessons) {
        source.check();
        if (!refresh && course.lesson(plan.id)?.prepared == true) {
          done++;
          continue;
        }
        progress(
          '正在整理 ${plan.unitTitle} · ${plan.title}',
          done,
          outline.lessons.length,
        );
        final lesson = parser.prepare(
          plan,
          pages.where((p) => plan.containsPage(p.page)).toList(),
          vocabulary,
        );
        await courses.saveGenerated(book, lesson, check: source.check);
        source.check();
        changed();
        done++;
      }
      progress('已整理 $done 个课时，请逐项对照原书核对', done, outline.lessons.length);
    } finally {
      await source.close();
    }
  }
}
