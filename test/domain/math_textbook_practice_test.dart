import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/domain/math_textbook_course_plan.dart';
import 'package:poemath/domain/math_textbook_grading.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../helpers/math_textbook_learning_fixture.dart';
import '../helpers/math_textbook_fixture.dart';

void main() {
  final book = mathTextbookFixture();
  test('未审核且覆盖未确认的纸上原题和实践可练习', () {
    final source = mathLearningFixture(
      manual: true,
      kind: MathTextbookPracticeKind.parentTask,
    );
    final lesson = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {...source.learning!.toJson(), 'coverageConfirmed': false},
    });
    final access = mathTextbookPracticeAvailability(lesson, book.pdfSha256);
    expect(lesson.isApproved(book.pdfSha256), isFalse);
    expect(access.exerciseIds, {'ex'});
    expect(access.planIds, {'plan'});
    expect(access.ready, isTrue);
  });

  test('未核对的自动答案和引擎约束不会因开放学习而用于自动练习', () {
    final source = mathLearningFixture();
    final pending = mathTextbookPracticeAvailability(source, book.pdfSha256);
    expect(pending.exerciseIds, isEmpty);
    expect(pending.planIds, isEmpty);
    final incomplete =
        MathTextbookLesson.fromJson({
          ...source.toJson(),
          'learning': {
            ...source.learning!.toJson(),
            'coverageConfirmed': false,
          },
        }).approve(
          pdfSha256: book.pdfSha256,
          reviewer: '测试家长',
          editingMilliseconds: 1000,
        );
    final access = mathTextbookPracticeAvailability(incomplete, book.pdfSha256);
    expect(incomplete.isApproved(book.pdfSha256), isTrue);
    expect(access.exerciseIds, isEmpty);
    expect(access.planIds, isEmpty);
    expect(access.ready, isFalse);
  });

  test('含开放项的混合题仍需核对自动答案，不能当作纯纸上题开放', () {
    final source = mathLearningFixture(
      kind: MathTextbookPracticeKind.parentTask,
    );
    final exercise = source.learning!.exercises.single;
    final mixed = MathTextbookExercise.fromJson({
      ...exercise.toJson(),
      'fields': [
        ...exercise.fields.map((field) => field.toJson()),
        MathTextbookAnswerField(
          id: 'paper',
          label: '完成说明',
          rule: MathTextbookAnswerRule(
            kind: MathTextbookAnswerKind.parent,
            reference: '请说明想法。',
          ),
        ).toJson(),
      ],
    });
    final lesson = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {
        ...source.learning!.toJson(),
        'exercises': [mixed.toJson()],
      },
    });
    expect(lesson.learning!.exercises.single.needsParent, isTrue);
    final access = mathTextbookPracticeAvailability(lesson, book.pdfSha256);
    expect(access.exerciseIds, isEmpty);
    expect(access.planIds, {'plan'});
    expect(access.ready, isFalse);
  });

  for (final (kind, answer, unit) in [
    (MathTextbookPracticeKind.engine, '4', ''),
    (MathTextbookPracticeKind.unitConversion, '20', 'mm'),
    (MathTextbookPracticeKind.rectanglePerimeter, '8', 'cm'),
    (MathTextbookPracticeKind.rectangleArea, '4', 'cm²'),
    (MathTextbookPracticeKind.triangleArea, '2', 'cm²'),
    (MathTextbookPracticeKind.trapezoidArea, '4', 'cm²'),
    (MathTextbookPracticeKind.circlePerimeter, '12.56', 'cm'),
    (MathTextbookPracticeKind.circleArea, '12.56', 'cm²'),
    (MathTextbookPracticeKind.cuboidVolume, '8', 'cm³'),
    (MathTextbookPracticeKind.cubeVolume, '8', 'cm³'),
    (MathTextbookPracticeKind.cylinderVolume, '25.12', 'cm³'),
    (MathTextbookPracticeKind.dataTable, '6', ''),
  ]) {
    test('${kind.name} 按本课给定数值生成题目并用精确结果和单位核对', () {
      final lesson = mathLearningFixture(kind: kind);
      final plan = MathTextbookPracticePlan.fromJson({
        ...lesson.learning!.practicePlans.single.toJson(),
        'minOperand': 2,
        'maxOperand': 2,
      });
      final items = generateMathTextbookPractice(
        lesson: lesson,
        plan: plan,
        grade: 3,
        semester: '上',
        random: Random(42),
      );
      expect(items, hasLength(2));
      for (final item in items) {
        expect(item.exercise.fields.single.rule.unit, unit);
        expect(
          gradeMathTextbookExercise(item.exercise, {
            'answer': '$answer$unit',
          }).result,
          MathTextbookResult.correct,
        );
        expect(
          gradeMathTextbookExercise(item.exercise, {
            'answer': '-999$unit',
          }).result,
          MathTextbookResult.incorrect,
        );
        expect(item.blocks.single.sources.single.page, 1);
        if (kind == MathTextbookPracticeKind.engine) {
          expect(item.problem!.operands.map((n) => n.asInteger).toList(), [
            2,
            2,
          ]);
          expect(
            ConstraintChecker.check(item.problem!, plan.config(3, '上')),
            isNull,
          );
        }
      }
    });
  }

  test('统计表各计算方式保留明确的给定值和问题', () {
    final lesson = mathLearningFixture(
      kind: MathTextbookPracticeKind.dataTable,
    );
    for (final (task, answer) in [
      ('total', '6'),
      ('mean', '2'),
      ('max', '2'),
      ('difference', '0'),
    ]) {
      final plan = MathTextbookPracticePlan.fromJson({
        ...lesson.learning!.practicePlans.single.toJson(),
        'minOperand': 2,
        'maxOperand': 2,
        'task': task,
      });
      final item = generateMathTextbookPractice(
        lesson: lesson,
        plan: plan,
        grade: 3,
        semester: '上',
        random: Random(17),
      ).first;
      expect(item.blocks.single.text, startsWith('统计表：甲 2、乙 2、丙 2。'));
      expect(
        gradeMathTextbookAnswer(item.exercise.fields.single.rule, answer),
        isTrue,
      );
    }
  });

  test('实践类保留具体任务，只产生待家长核对结果', () {
    final lesson = mathLearningFixture(
      kind: MathTextbookPracticeKind.parentTask,
    );
    final plan = lesson.learning!.practicePlans.single;
    final items = generateMathTextbookPractice(
      lesson: lesson,
      plan: plan,
      grade: 3,
      semester: '上',
    );
    expect(items, hasLength(1));
    expect(items.single.blocks.single.text, plan.task);
    expect(
      gradeMathTextbookExercise(items.single.exercise, {
        'answer': '已画好并解释',
      }).result,
      MathTextbookResult.pendingParent,
    );
  });

  for (final kind in [
    MathTextbookPracticeKind.engine,
    MathTextbookPracticeKind.rectangleArea,
  ]) {
    test('${kind.name} 无解约束明确失败，不放宽数值范围凑题', () {
      final lesson = mathLearningFixture(kind: kind);
      final plan = MathTextbookPracticePlan.fromJson({
        ...lesson.learning!.practicePlans.single.toJson(),
        'minOperand': 5,
        'maxOperand': 5,
        'maxResult': 1,
      });
      expect(
        () => generateMathTextbookPractice(
          lesson: lesson,
          plan: plan,
          grade: 3,
          semester: '上',
          random: Random(1),
        ),
        throwsStateError,
      );
    });
  }

  test('教材引擎拒绝册次与约束不一致且遵守已核对的运算集合', () {
    final lesson = mathLearningFixture();
    final plan = lesson.learning!.practicePlans.single;
    expect(
      () => MathEngine.generate(
        grade: 2,
        semester: '下',
        skillId: MathSkill.addition.id,
        curriculum: plan.config(3, '上'),
      ),
      throwsArgumentError,
    );
    final incompatible = MathTextbookPracticePlan.fromJson({
      ...plan.toJson(),
      'operators': ['subtract'],
    });
    expect(
      () => generateMathTextbookPractice(
        lesson: lesson,
        plan: incompatible,
        grade: 3,
        semester: '上',
        random: Random(8),
      ),
      throwsStateError,
    );
  });

  test('无可定位目录时完整保留原书区间，按40页上限分段且不自动审核', () {
    final outline = planMathTextbookCourse(
      const TextbookTocResult(
        entries: [],
        source: TextbookTocSource.text,
        hasText: false,
      ),
      82,
    );
    expect(outline.ranges.map((r) => (r.startPage, r.endPage)).toList(), [
      (1, 40),
      (41, 80),
      (81, 82),
    ]);
    expect(outline.ranges.every((r) => r.needsAlignment), isTrue);
    expect(outline.source, 'pages');
    final seeded = seedMathTextbookLearning(mathLearningFixture());
    expect(seeded.coverageConfirmed, isFalse);
    expect(
      seeded.exercises.single.fields.single.rule.kind,
      MathTextbookAnswerKind.parent,
    );
    expect(() => seeded.checkReady(), throwsFormatException);
  });

  test('没有页码的目录单元仍传到其下课时，课时边界和待核状态准确', () {
    final outline = planMathTextbookCourse(
      const TextbookTocResult(
        source: TextbookTocSource.bookmarks,
        entries: [
          TextbookTocEntry(title: '分数单元', isGroup: true),
          TextbookTocEntry(title: '分数的意义', level: 1, page: 5),
          TextbookTocEntry(title: '分数的运算', level: 1, page: 8),
          TextbookTocEntry(title: '几何单元', isGroup: true),
          TextbookTocEntry(title: '图形的认识', level: 1, page: 12),
        ],
        directoryPages: [3],
      ),
      15,
    );
    expect(
      outline.ranges.map((r) => (r.unitTitle, r.startPage, r.endPage)).toList(),
      [('', 1, 4), ('分数单元', 5, 7), ('分数单元', 8, 11), ('几何单元', 12, 15)],
    );
    expect(outline.ranges.first.needsAlignment, isTrue);
    expect(outline.directoryPages, [3]);
  });

  test('第一课无法定位时保留其原页，不能把首个已定位课之前的正文丢掉', () {
    final outline = planMathTextbookCourse(
      const TextbookTocResult(
        source: TextbookTocSource.text,
        directoryPages: [5, 6],
        entries: [
          TextbookTocEntry(title: '第一单元', isGroup: true),
          TextbookTocEntry(title: '第一课', printedPage: 1, level: 1),
          TextbookTocEntry(title: '第二课', page: 51, printedPage: 45, level: 1),
        ],
      ),
      92,
    );
    expect(outline.ranges.map((r) => (r.startPage, r.endPage)).toList(), [
      (1, 40),
      (41, 50),
      (51, 90),
      (91, 92),
    ]);
    expect(outline.ranges.every((r) => r.needsAlignment), isTrue);
    expect(
      {
        for (final range in outline.ranges)
          for (var page = range.startPage; page <= range.endPage; page++) page,
      },
      {for (var page = 1; page <= 92; page++) page},
    );
    expect(outline.warnings, hasLength(2));
    expect(outline.directoryPages, [5, 6]);
  });
}
