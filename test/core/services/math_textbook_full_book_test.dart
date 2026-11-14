import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';

class _BookFiles extends TextbookFileService {
  _BookFiles(this.input, Directory root)
    : super(directoryProvider: () async => root);
  final String input;
  @override
  Future<String?> installedPath(Textbook book) async => input;
}

/// 逐册调用生产整书生成服务。原PDF、提取内容和验收输出仅保存到指定本机目录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const inputDirectory = String.fromEnvironment(
    'MATH_TEXTBOOK_CATALOG_PDF_DIRECTORY',
  );
  const evidenceDirectory = String.fromEnvironment(
    'MATH_TEXTBOOK_FULL_EVIDENCE_DIRECTORY',
  );
  const library = String.fromEnvironment('TEXTBOOK_PDFIUM_LIBRARY');
  final enabled =
      inputDirectory.isNotEmpty &&
      evidenceDirectory.isNotEmpty &&
      library.isNotEmpty;
  late List<Textbook> books;
  final matrix = <Map<String, Object?>>[];
  setUpAll(() async {
    if (!enabled) return;
    Pdfrx.pdfiumModulePath = library;
    Pdfrx.cacheDirectoryPath = '$evidenceDirectory/native-cache';
    await Directory(evidenceDirectory).create(recursive: true);
    books = (await const TextbookCatalogRepository().load())
        .map((entry) => entry.book)
        .where((book) => book.subject == TextbookSubject.math)
        .toList();
    expect(books, hasLength(12));
    expect(books.map((b) => (b.grade, b.semester)).toSet(), {
      for (final grade in [1, 2, 3, 4, 5, 6])
        for (final semester in ['上', '下']) (grade, semester),
    });
  });
  tearDownAll(() async {
    if (enabled) {
      await File('$evidenceDirectory/matrix.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({'v': 1, 'books': matrix}),
      );
    }
  });

  for (final grade in [1, 2, 3, 4, 5, 6]) {
    for (final semester in ['上', '下']) {
      final key = '$grade${semester == '上' ? 'a' : 'b'}';
      test(
        '全部原书整理、持久化和人工可补齐：$grade年级$semester册',
        () async {
          final book = books.singleWhere(
            (b) => b.grade == grade && b.semester == semester,
          );
          final pdf = File('$inputDirectory/$key.pdf');
          expect(await pdf.length(), book.fileSize);
          expect(
            (await sha256.bind(pdf.openRead()).first).toString(),
            book.pdfSha256,
          );
          final root = await Directory(
            '$evidenceDirectory/$key/run-${DateTime.now().microsecondsSinceEpoch}',
          ).create(recursive: true);
          final repository = MathTextbookCourseRepository(
            directoryProvider: () async => root,
          );
          final service = MathTextbookGenerationService(
            repository,
            _BookFiles(pdf.path, root),
          );
          final progress = <(int, int)>[];
          final stopwatch = Stopwatch()..start();
          final course = await service.generateBook(
            book: book,
            token: TextbookDraftToken(),
            authorize: () {},
            onProgress: (done, total) => progress.add((done, total)),
          );
          stopwatch.stop();
          final ranges = course.outline!.ranges;
          final plannedPages = {
            for (final range in ranges)
              for (var page = range.startPage; page <= range.endPage; page++)
                page,
          };
          final expectedPages = {
            for (var page = 1; page <= book.pageCount; page++) page,
          };
          expect(plannedPages, expectedPages);
          expect(ranges.first.startPage, 1);
          expect(ranges.last.endPage, book.pageCount);
          for (var i = 1; i < ranges.length; i++) {
            expect(ranges[i].startPage, ranges[i - 1].endPage + 1);
          }
          // 这十二份已核验的固定 PDF 的目录均在第 5、6 页。
          // 不能让正文被误标为目录后，再以错误目录自证完整覆盖。
          expect(course.outline!.directoryPages, [5, 6]);
          final sourcePages = course.lessons
              .expand((l) => l.blocks)
              .where((b) => b.kind == MathTextbookBlockKind.sourcePage)
              .expand((b) => b.sources.map((s) => s.page))
              .toSet();
          expect(sourcePages, expectedPages);
          expect(
            course.lessons.map((l) => l.id).toList(),
            ranges.map((r) => r.lessonId).toList(),
          );
          expect(course.lessons.every((l) => l.review == null), isTrue);
          expect(
            course.lessons.every((l) => l.learning!.coverageConfirmed == false),
            isTrue,
          );
          expect(progress.last, (expectedPages.length, expectedPages.length));
          for (var i = 1; i < progress.length; i++) {
            expect(progress[i].$1, greaterThanOrEqualTo(progress[i - 1].$1));
          }
          final reopened = MathTextbookCourseRepository(
            directoryProvider: () async => root,
          );
          expect((await reopened.load(book))!.toJson(), course.toJson());

          // 实际调用保存/严格导入/审核，再还原未审原稿；这只是工程验证，不代替家长核对教材。
          final lesson = course.lessons.first;
          final source = lesson.blocks.firstWhere(
            (b) => b.kind == MathTextbookBlockKind.sourcePage,
          );
          final learning = MathTextbookLearning.fromJson(
            MathTextbookLearning(
              unitTitle: lesson.learning!.unitTitle,
              coverageConfirmed: true,
              knowledgePoints: [
                MathTextbookKnowledgePoint(
                  id: 'validation-kp',
                  title: '来源核对任务',
                  summary: '依据原书给定内容完成纸上任务并说明过程。',
                  blockIds: [source.id],
                ),
              ],
              exercises: [
                MathTextbookExercise(
                  id: 'validation-ex',
                  title: '工程验收来源任务',
                  blockIds: [source.id],
                  knowledgePointIds: ['validation-kp'],
                  fields: [
                    MathTextbookAnswerField(
                      id: 'answer',
                      label: '完成情况',
                      rule: MathTextbookAnswerRule(
                        kind: MathTextbookAnswerKind.parent,
                        reference: '请对照原书来源核对。',
                      ),
                    ),
                  ],
                ),
              ],
              practicePlans: [
                MathTextbookPracticePlan(
                  id: 'validation-plan',
                  knowledgePointId: 'validation-kp',
                  title: '工程验收纸上任务',
                  kind: MathTextbookPracticeKind.parentTask,
                  count: 1,
                  task: '依据本页原书给定内容完成纸上任务，并请家长核对。',
                ),
              ],
            ).toJson(),
          );
          final supplement = lesson
              .edit(learning: learning)
              .approve(
                pdfSha256: book.pdfSha256,
                reviewer: '工程测试',
                editingMilliseconds: 0,
              );
          final supplemented = await reopened.saveLesson(
            book,
            supplement,
            expectedRevision: course.revision,
            generation: 0,
            authorize: () {},
          );
          final persisted = (await MathTextbookCourseRepository(
            directoryProvider: () async => root,
          ).load(book))!.lessons.firstWhere((l) => l.id == lesson.id);
          expect(persisted.toJson(), supplement.toJson());
          expect(persisted.isApproved(book.pdfSha256), isTrue);
          final restored = await reopened.saveLesson(
            book,
            lesson,
            expectedRevision: supplemented.revision,
            generation: 0,
            authorize: () {},
          );
          expect(restored.lessons.every((l) => l.review == null), isTrue);
          final blocks = course.lessons.expand((l) => l.blocks).toList();
          matrix.add({
            'key': key,
            'pdfSha256': book.pdfSha256,
            'editionId': book.learningEditionId,
            'fileSize': book.fileSize,
            'pageCount': book.pageCount,
            'directorySource': course.outline!.source,
            'directoryPages': course.outline!.directoryPages,
            'ranges': ranges.map((r) => r.toJson()).toList(),
            'sourcePages': sourcePages.toList()..sort(),
            'sourcePagesComplete': sourcePages.length == book.pageCount,
            'needsAlignmentRanges': ranges
                .where((range) => range.needsAlignment)
                .length,
            'blocks': blocks.length,
            'exerciseBlocks': blocks
                .where((b) => b.kind == MathTextbookBlockKind.exercise)
                .length,
            'exerciseGroups': course.lessons.fold<int>(
              0,
              (sum, l) => sum + l.learning!.exercises.length,
            ),
            'expressions': blocks
                .expand((b) => b.spans)
                .where((s) => s.expression != null)
                .length,
            'warningBlocks': blocks.where((b) => b.warnings.isNotEmpty).length,
            'outlineWarnings': course.outline!.warnings,
            'reviewedLessons': 0,
            'structuredImportAndManualSupplement': true,
            'elapsedMilliseconds': stopwatch.elapsedMilliseconds,
            'courseFile':
                '${root.path}/textbooks/math-courses/${book.pdfSha256}.json',
          });
        },
        skip: !enabled,
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }
  }
}
