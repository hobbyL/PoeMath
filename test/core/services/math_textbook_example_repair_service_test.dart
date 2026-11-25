import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/math_textbook_example_repair_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_study.dart';

import '../../helpers/math_textbook_example_fixture.dart';
import '../../helpers/math_textbook_fixture.dart';

void main() {
  late Directory root;
  late TextbookFileService files;
  final book = mathTextbookFixture();
  final pages = exampleBadgePages();
  final old = badgeLesson(pages, legacy: true);
  final original = MathTextbookCourse.forBook(book).replace(lessons: [old]);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-example-repair-');
    files = TextbookFileService(directoryProvider: () async => root);
  });
  tearDown(() => root.delete(recursive: true));

  test('整个课时修复为只读投影，保留版本与原始课程', () async {
    final before = original.toJson();
    final result = await repairMathTextbookCourseExamples(
      course: original,
      book: book,
      files: files,
      pageLoader: (number) async => pages[number - 1],
    );
    expect(mathTextbookWorkedExamples(result.lessons.single), hasLength(1));
    expect(result.revision, original.revision);
    expect(result.lessons.single.review, isNull);
    expect(original.toJson(), before);
    expect(await root.list(recursive: true).toList(), isEmpty);
  });

  test('待采纳、保留旧课及未对齐范围不自动修复', () async {
    final excluded = [
      original.replace(pendingLessons: [old]),
      original.replace(
        outline: MathTextbookCourseOutline(
          source: 'text',
          ranges: [
            const MathTextbookCourseRange(
              title: '新课时',
              startPage: 3,
              endPage: 3,
            ),
          ],
          retainedLessonIds: [old.id],
        ),
      ),
      original.replace(
        outline: MathTextbookCourseOutline(
          source: 'text',
          ranges: [
            MathTextbookCourseRange(
              title: old.title,
              startPage: 1,
              endPage: 2,
              needsAlignment: true,
            ),
          ],
        ),
      ),
    ];
    for (final course in excluded) {
      final result = await repairMathTextbookCourseExamples(
        course: course,
        book: book,
        files: files,
        pageLoader: (_) => throw StateError('不应读取原书'),
      );
      expect(identical(result, course), isTrue);
    }
  });

  test('读取失败或清理期间的迟到修复不发布，重试仍能完整修复', () async {
    await expectLater(
      repairMathTextbookCourseExamples(
        course: original,
        book: book,
        files: files,
        pageLoader: (_) => throw const FormatException('原书暂不可读'),
      ),
      throwsFormatException,
    );
    await expectLater(
      repairMathTextbookCourseExamples(
        course: original,
        book: book,
        files: files,
        pageLoader: (number) async {
          await files.contentCache(book).clearExtracted();
          return pages[number - 1];
        },
      ),
      throwsStateError,
    );
    final result = await repairMathTextbookCourseExamples(
      course: original,
      book: book,
      files: files,
      pageLoader: (number) async => pages[number - 1],
    );
    expect(mathTextbookWorkedExamples(result.lessons.single), hasLength(1));
  });
}
