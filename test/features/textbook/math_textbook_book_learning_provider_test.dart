import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';

import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';

void main() {
  final book = mathTextbookFixture();

  test('大课本列表后台汇总后，换稿仍将课程与摘要作为同一份快照返回', () async {
    final lesson = denseMathLearningFixture().approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 1000,
    );
    var course = MathTextbookCourse.forBook(book).replace(lessons: [lesson]);
    final container = ProviderContainer(
      overrides: [
        mathTextbookCourseProvider(book.pdfSha256)
            .overrideWith((ref) async => course),
        mathTextbookProgressProvider(book.pdfSha256).overrideWith(
          (ref) async => MathTextbookProgress(
            profileId: 'child',
            bookId: book.pdfSha256,
            editionId: book.learningEditionId,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final snapshots = <MathTextbookBookLearning>[];
    final subscription = container.listen(
      mathTextbookBookLearningProvider(book.pdfSha256),
      (_, next) => next.whenData(snapshots.add),
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final first = await container.read(
      mathTextbookBookLearningProvider(book.pdfSha256).future,
    );
    expect(first.lessons[lesson.id]!.ready, isTrue);
    expect(first.lessons[lesson.id]!.complete, isFalse);

    final changed = MathTextbookLesson(
      id: 'replaced-lesson',
      title: '更新后的课时',
      startPage: lesson.startPage,
      endPage: lesson.endPage,
      blocks: lesson.blocks,
      learning: lesson.learning,
    );
    course = course.replace(lessons: [changed]);
    container.invalidate(mathTextbookCourseProvider(book.pdfSha256));
    final updated = await container.read(
      mathTextbookBookLearningProvider(book.pdfSha256).future,
    );
    expect(updated.course!.lessons.single.id, changed.id);
    expect(updated.lessons.keys, [changed.id]);
    expect(updated.lessons[changed.id]!.ready, isFalse);
    for (final snapshot in snapshots) {
      expect(snapshot.lessons.keys.toSet(), {
        for (final value in snapshot.course!.lessons) value.id,
      });
    }
  });

  test('课本加载失败仍传递错误，不将损坏课本显示为空列表', () async {
    final container = ProviderContainer(
      overrides: [
        mathTextbookCourseProvider(book.pdfSha256)
            .overrideWith((ref) async => throw const FormatException('课程已损坏')),
        mathTextbookProgressProvider(book.pdfSha256).overrideWith((ref) async {
          await ref.watch(mathTextbookCourseProvider(book.pdfSha256).future);
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(mathTextbookBookLearningProvider(book.pdfSha256).future),
      throwsFormatException,
    );
  });
}
