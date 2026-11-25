import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/domain/math_textbook_example_repair.dart';
import 'package:poemath/domain/math_textbook_study.dart';

import '../helpers/math_textbook_fixture.dart';
import '../helpers/math_textbook_example_fixture.dart';

void main() {
  final book = mathTextbookFixture();
  test('大圆圈内的小字号数字仍是例题，小圆点练习保持原题', () {
    final pages = exampleBadgePages();
    final old = badgeLesson(pages, legacy: true);
    expect(mathTextbookWorkedExamples(old), isEmpty);
    final current = badgeLesson(pages);
    final example = mathTextbookWorkedExamples(current).single;
    expect(example.title, '自有分类课 · 例 1');
    expect(
      example.blocks.map((block) => block.sources.first.page),
      everyElement(1),
    );
    expect(current.learning!.exercises, hasLength(1));
    expect(
      current.learning!.exercises.single.blockIds.single,
      startsWith('math-1-2-p2'),
    );
    final oldBlock = old.blocks.firstWhere((block) => block.id == example.id);
    expect(
      example.blocks.first.sources.single.toJson(),
      oldBlock.sources.single.toJson(),
    );
    expect(current.learning!.coverageConfirmed, isFalse);
  });

  test('旧自动课程完整复现后修正，原稿和新课的复读不变', () {
    final pages = exampleBadgePages();
    final old = badgeLesson(pages, legacy: true);
    final before = old.toJson();
    final repaired = repairMathTextbookExamples(
      old,
      pages,
      bookId: book.pdfSha256,
    );
    expect(mathTextbookWorkedExamples(repaired), hasLength(1));
    expect(repaired.toJson(), badgeLesson(pages).toJson());
    expect(old.toJson(), before);
    expect(
      identical(
        repairMathTextbookExamples(repaired, pages, bookId: book.pdfSha256),
        repaired,
      ),
      isTrue,
    );
  });

  test('人工文本、裁切、学习配置、审核及不完整图形证据不被覆盖', () {
    final pages = exampleBadgePages();
    final old = badgeLesson(pages, legacy: true);
    final first = old.blocks.first;
    final versions = [
      old.edit(
        blocks: [
          MathTextbookBlock.fromJson({
            ...first.toJson(),
            'spans': [const MathTextbookSpan.text('家长改写的题干。').toJson()],
          }),
          ...old.blocks.skip(1),
        ],
      ),
      old.edit(
        learning: MathTextbookLearning.fromJson({
          ...old.learning!.toJson(),
          'exercises': [
            for (final exercise in old.learning!.exercises)
              {...exercise.toJson(), 'note': '人工添加的说明'},
          ],
        }),
      ),
      old.edit(
        blocks: [
          MathTextbookBlock.fromJson({...first.toJson(), 'parentNote': '家长补充'}),
          ...old.blocks.skip(1),
        ],
      ),
      old.edit(
        blocks: [
          MathTextbookBlock.fromJson({
            ...first.toJson(),
            'sources': [
              {...first.sources.single.toJson(), 'left': .02},
            ],
          }),
          ...old.blocks.skip(1),
        ],
      ),
      old.edit(
        learning: MathTextbookLearning.fromJson({
          ...old.learning!.toJson(),
          'coverageConfirmed': true,
        }),
      ),
      old.approve(
        pdfSha256: book.pdfSha256,
        reviewer: '家长',
        editingMilliseconds: 1000,
      ),
    ];
    for (final version in versions) {
      expect(
        identical(
          repairMathTextbookExamples(version, pages, bookId: book.pdfSha256),
          version,
        ),
        isTrue,
      );
    }
    final incomplete = [
      MathTextbookPageLayout(
        text: pages.first.text,
        graphics: MathTextbookGraphics(complete: false),
      ),
      pages.last,
    ];
    expect(
      identical(
        repairMathTextbookExamples(old, incomplete, bookId: book.pdfSha256),
        old,
      ),
      isTrue,
    );
  });
}
