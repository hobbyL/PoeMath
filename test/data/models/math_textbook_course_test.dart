import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_editing.dart';

import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';

void main() {
  final book = mathTextbookFixture();
  test('内容审核独立完成，不要求先补齐自动练习配置', () {
    final source = mathLearningFixture();
    final pending = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {
        ...source.learning!.toJson(),
        'coverageConfirmed': false,
        'practicePlans': <Object>[],
      },
    });
    expect(pending.learning!.checkReady, throwsFormatException);
    final reviewed = pending.approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 1000,
    );
    final reopened = MathTextbookLesson.fromJson(
      jsonDecode(jsonEncode(reviewed.toJson())),
    );
    expect(reopened.isApproved(book.pdfSha256), isTrue);
    expect(reopened.learning!.coverageConfirmed, isFalse);
    expect(reopened.learning!.checkReady, throwsFormatException);
    expect(reopened.edit(title: '修改内容').isApproved(book.pdfSha256), isFalse);
  });

  test('独立格式在实际解析、JSON 往返和整课审核后保持公式与来源', () {
    final lesson = mathLessonFixture();
    final reviewed = lesson.approve(
      pdfSha256: book.pdfSha256,
      reviewer: '测试家长',
      editingMilliseconds: 1200,
      at: DateTime.utc(2026, 11, 13),
    );
    final course = MathTextbookCourse.forBook(book)
        .replace(lessons: [reviewed]);
    final restored = MathTextbookCourse.fromJson(
      jsonDecode(jsonEncode(course.toJson())),
    );
    expect(restored.toJson(), course.toJson());
    expect(restored.lessons.single.isApproved(book.pdfSha256), isTrue);
    expect(restored.lessons.single.isApproved('b' * 64), isFalse);
    expect(
      restored.lessons.single.edit(title: '已修改').isApproved(book.pdfSha256),
      isFalse,
    );
    expect(
      restored.lessons.single.blocks
          .expand((b) => b.sources)
          .map((s) => s.page)
          .toSet(),
      {1, 2},
    );
    expect(
      restored.lessons.single.blocks
          .expand((b) => b.spans)
          .map((s) => s.expression)
          .whereType<MathTextbookFraction>(),
      hasLength(2),
    );
    expect(
      () => restored.matchBook(book.withSubject(TextbookSubject.chinese)),
      throwsFormatException,
    );
  });

  test('文字与公式混排支持换行，拒绝只有空白的正文', () {
    final block = mathLessonFixture().blocks.first;
    final merged = mergeMathTextbookBlocks(block, block);
    expect(MathTextbookBlock.fromJson(merged.toJson()).text, contains('\n'));
    expect(
      () => MathTextbookBlock.fromJson({
        ...block.toJson(),
        'spans': [const MathTextbookSpan.text('  \n').toJson()],
      }),
      throwsFormatException,
    );
  });

  test('错误坐标、缺页、重复编号和跨书身份被拒绝', () {
    final lesson = mathLessonFixture();
    final raw = lesson.toJson();
    final first = lesson.blocks.first;
    for (final coords in [
      {'left': double.nan},
      {'right': 1.1},
      {'right': 0.0},
      {'page': 0},
      {'top': double.infinity},
    ]) {
      expect(
        () => MathTextbookRegion.fromJson({
          ...first.sources.first.toJson(),
          ...coords,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => MathTextbookLesson.fromJson({
        ...raw,
        'blocks': lesson.blocks
            .where((b) => b.sources.every((s) => s.page == 1))
            .map((b) => b.toJson())
            .toList(),
      }),
      throwsFormatException,
    );
    expect(
      () => MathTextbookLesson.fromJson({
        ...raw,
        'blocks': [...lesson.blocks.map((b) => b.toJson()), first.toJson()],
      }),
      throwsFormatException,
    );
    expect(
      () => MathTextbookCourse.fromJson({
        ...MathTextbookCourse.forBook(book).toJson(),
        'subject': 'chinese',
      }),
      throwsFormatException,
    );
    expect(
      () => MathTextbookCourse.forBook(book).matchBook(
        Textbook.fromJson({...book.toJson(), 'fileSize': book.fileSize + 1}),
      ),
      throwsFormatException,
    );
  });

  test('公式输入保留带分数和上标，拒绝除零及未支持的字符串', () {
    final expression = parseMathTextbookExpression('7/3 = 7 ÷ 3 = 2又1/3');
    expect(expression, isA<MathTextbookSequence>());
    expect(
      (expression as MathTextbookSequence).parts.last,
      isA<MathTextbookMixedNumber>(),
    );
    expect(parseMathTextbookExpression('cm^3').toJson(), {
      'kind': 'power',
      'base': 'cm',
      'exponent': 3,
    });
    for (final input in ['1/0', '1又4/3', r'\input{file}', '这是文字', '']) {
      expect(
        () => parseMathTextbookExpression(input),
        throwsFormatException,
        reason: input,
      );
    }
    final vertical = MathTextbookVerticalAddition(
      ['541', '267', '808'],
      [const MathTextbookCarry(1, 1), const MathTextbookCarry(1, 2)],
    );
    final decoded = MathTextbookExpression.fromJson(
      vertical.toJson(),
    ) as MathTextbookVerticalAddition;
    expect(decoded.rows, ['541', '267', '808']);
    expect(decoded.carries.map((c) => c.columnFromRight), [1, 2]);
    expect(decoded.latex, contains(r'\hline'));
    expect(
      () => MathTextbookExpression.fromJson({
        ...vertical.toJson(),
        'carries': [const MathTextbookCarry(1, 3).toJson()],
      }),
      throwsFormatException,
    );
    expect(
      () => MathTextbookExpression.fromJson(
        MathTextbookSequence([vertical, const MathTextbookAtom('1')]).toJson(),
      ),
      throwsFormatException,
    );
  });

  test('手工跨页合并保留来源，不允许移除整页对照', () {
    final lesson = mathLessonFixture();
    final first = lesson.blocks.firstWhere(
      (b) => b.sources.first.page == 1 && b.kind == MathTextbookBlockKind.text,
    );
    final next = lesson.blocks.firstWhere(
      (b) => b.sources.first.page == 2 && b.kind == MathTextbookBlockKind.text,
    );
    final joined = mergeMathTextbookBlocks(first, next);
    expect(joined.sources.map((s) => s.page), [1, 2]);
    expect(joined.text, contains(first.text));
    expect(joined.text, contains(next.text));
    expect(
      () => mergeMathTextbookBlocks(first, lesson.blocks.last),
      throwsFormatException,
    );
  });
}
