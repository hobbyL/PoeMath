import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// Roughly one MiB of self-authored content, like a prepared whole textbook.
MathTextbookLesson denseMathLearningFixture({int additionalBlocks = 2400}) {
  final lesson = mathLearningFixture();
  return lesson.edit(
    blocks: [
      ...lesson.blocks,
      for (var i = 0; i < additionalBlocks; i++)
        MathTextbookBlock(
          id: 'dense-$i',
          kind: MathTextbookBlockKind.text,
          spans: [MathTextbookSpan.text('自有教材内容。' * 12)],
          sources: const [
            MathTextbookRegion(
              page: 1,
              left: .1,
              top: .1,
              right: .9,
              bottom: .3,
            ),
          ],
        ),
    ],
  );
}

MathTextbookLesson mathLearningFixture({
  bool manual = false,
  int count = 2,
  MathTextbookPracticeKind kind = MathTextbookPracticeKind.engine,
}) {
  final lesson = MathTextbookLesson(
    id: 'math-1-2',
    title: '自有加法与图形课',
    startPage: 1,
    endPage: 2,
    blocks: [
      MathTextbookBlock(
        id: 'example',
        kind: MathTextbookBlockKind.text,
        spans: [const MathTextbookSpan.text('把2个圆和3个圆合在一起，共有5个圆。')],
        sources: const [
          MathTextbookRegion(page: 1, left: .1, top: .1, right: .9, bottom: .3),
        ],
      ),
      MathTextbookBlock(
        id: 'exercise',
        kind: MathTextbookBlockKind.exercise,
        exerciseNumber: '1',
        spans: [MathTextbookSpan.text(manual ? '在纸上画出5个圆。' : '2 + 3 = ?')],
        sources: const [
          MathTextbookRegion(page: 2, left: .1, top: .2, right: .9, bottom: .4),
        ],
      ),
    ],
    learning: MathTextbookLearning(
      unitTitle: '自有测试单元',
      coverageConfirmed: true,
      knowledgePoints: [
        MathTextbookKnowledgePoint(
          id: 'kp',
          title: '合并数量',
          summary: '用加法求合并后的数量。',
          blockIds: ['example'],
        ),
      ],
      exercises: [
        MathTextbookExercise(
          id: 'ex',
          title: '原书第1题',
          number: '1',
          blockIds: ['exercise'],
          knowledgePointIds: ['kp'],
          fields: [
            MathTextbookAnswerField(
              id: 'answer',
              label: manual ? '纸上完成情况' : '你的答案',
              rule: manual
                  ? MathTextbookAnswerRule(
                      kind: MathTextbookAnswerKind.parent,
                      reference: '检查是否有5个圆。',
                    )
                  : MathTextbookAnswerRule(
                      kind: MathTextbookAnswerKind.number,
                      expected: '5',
                      form: MathTextbookNumberForm.integer,
                    ),
            ),
          ],
        ),
      ],
      practicePlans: [
        MathTextbookPracticePlan(
          id: 'plan',
          knowledgePointId: 'kp',
          title: '本课巩固',
          kind: kind,
          skillId: kind == MathTextbookPracticeKind.engine
              ? MathSkill.addition.id
              : null,
          count: count,
          minOperand: 1,
          maxOperand: 5,
          maxResult: 1000,
          operators: {Operator.add},
          mode: ProblemMode.findResult,
          allowCarry: false,
          unit:
              kind == MathTextbookPracticeKind.engine ||
                  kind == MathTextbookPracticeKind.parentTask ||
                  kind == MathTextbookPracticeKind.dataTable
              ? ''
              : 'cm',
          toUnit: kind == MathTextbookPracticeKind.unitConversion ? 'mm' : '',
          task: kind == MathTextbookPracticeKind.parentTask
              ? '画出2个圆和3个圆，并解释合并的数量。'
              : kind == MathTextbookPracticeKind.dataTable
              ? 'total'
              : '',
        ),
      ],
    ),
  );
  return MathTextbookLesson.fromJson(lesson.toJson());
}
