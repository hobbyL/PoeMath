import 'dart:isolate';

import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_pdf_graphics.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_example_repair.dart';

/// A cached, read-only projection of already organized courses. It does not
/// regenerate authored files or grant approval for exercises.
Future<MathTextbookCourse> repairMathTextbookCourseExamples({
  required MathTextbookCourse course,
  required Textbook book,
  required TextbookFileService files,
  Future<MathTextbookPageLayout> Function(int)? pageLoader,
}) async {
  final excluded = {
    ...?course.outline?.retainedLessonIds,
    ...course.pendingLessons.map((lesson) => lesson.id),
    for (final range in course.outline?.ranges ?? <MathTextbookCourseRange>[])
      if (range.needsAlignment) range.lessonId,
  };
  final candidates = course.lessons.where(
    (lesson) =>
        !excluded.contains(lesson.id) && canRepairMathTextbookExamples(lesson),
  );
  if (candidates.isEmpty) return course;
  final cache = files.contentCache(book);
  final revision = cache.revision;
  void check() {
    if (cache.revision != revision) throw StateError('原书缓存已失效');
  }

  PdfDocument? document;
  try {
    if (pageLoader == null) {
      final path = await files.peekInstalledPath(book);
      check();
      if (path == null) return course;
      await pdfrxFlutterInitialize();
      document = await PdfDocument.openFile(path);
      check();
      if (document.pages.length != book.pageCount) {
        throw const FormatException('原书页数与登记信息不符');
      }
    }
    final replacements = <String, MathTextbookLesson>{};
    for (final lesson in candidates) {
      final pages = <MathTextbookPageLayout>[];
      for (var number = lesson.startPage; number <= lesson.endPage; number++) {
        check();
        if (pageLoader != null) {
          pages.add(await pageLoader(number));
        } else {
          final text = await loadTextbookPdfPage(
            document: document!,
            number: number,
            checkAvailable: check,
            cache: cache,
          );
          final graphics = await document.useNativeDocumentHandle(
            (handle) => readMathTextbookGraphics(
              handle,
              number,
              modulePath: Pdfrx.pdfiumModulePath,
            ),
          );
          pages.add(MathTextbookPageLayout(text: text, graphics: graphics));
        }
      }
      check();
      final repaired = await _repairLesson(lesson, pages, book.pdfSha256);
      check();
      replacements[lesson.id] = repaired;
    }
    return MathTextbookCourse(
      pdfSha256: course.pdfSha256,
      pageCount: course.pageCount,
      fileSize: course.fileSize,
      grade: course.grade,
      semester: course.semester,
      revision: course.revision,
      lessons: [
        for (final lesson in course.lessons) replacements[lesson.id] ?? lesson,
      ],
      pendingLessons: course.pendingLessons,
      outline: course.outline,
    );
  } finally {
    await document?.dispose();
  }
}

Future<MathTextbookLesson> _repairLesson(
  MathTextbookLesson lesson,
  List<MathTextbookPageLayout> pages,
  String bookId,
) => Isolate.run(
  () => repairMathTextbookExamples(lesson, pages, bookId: bookId),
  debugName: 'math-textbook-example-repair',
);
