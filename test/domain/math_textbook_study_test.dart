import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_study.dart';

import '../helpers/math_textbook_learning_fixture.dart';

void main() {
  test('学一学提取完整的方法说明，不携带例题编号、题干、公式碎片和后记', () {
    final source = mathMisclassifiedPracticeFixture();
    final lesson = source.edit(
      blocks: [
        for (final block in source.blocks)
          if (block.id == 'example')
            MathTextbookBlock.fromJson({
              ...block.toJson(),
              'spans': [
                const MathTextbookSpan.text('1 小猫有3支笔，小狗有2支笔，一共有几支笔？\n'),
                MathTextbookSpan.math(
                  MathTextbookSequence(const [
                    MathTextbookAtom('3'),
                    MathTextbookAtom('+'),
                    MathTextbookAtom('2'),
                    MathTextbookAtom('='),
                    MathTextbookAtom('5'),
                  ]),
                ),
                const MathTextbookSpan.text('\n相同数位要对齐。\n个位相加满十，向十位进1。\n'),
                const MathTextbookSpan.text('用尺子量出上面三条线段的长度。\n'),
                const MathTextbookSpan.text('对插图团队表示深深的敬意和诚挚的谢意！'),
              ].map((s) => s.toJson()).toList(),
            })
          else
            block,
      ],
    );
    final automatic = lesson.edit(learning: seedMathTextbookLearning(lesson));
    final notes = mathTextbookStudyNotes(automatic);
    expect(notes.map((n) => n.title), ['自有长度课', '认识角']);
    expect(notes.first.summary, '相同数位要对齐。\n个位相加满十，向十位进1。');
    expect(notes.last.summary, '两条边从同一个顶点出发，可以形成一个角。');
    expect(automatic.blocks.first.exerciseNumber, '1');
    expect(automatic.learning!.knowledgePoints.first.title, contains('例 1'));
  });

  test('已编写的知识摘要原样显示，切换展示不改写原始课程', () {
    final lesson = mathLearningFixture();
    final before = lesson.toJson();
    expect(mathTextbookStudyNotes(lesson).single.summary, '用加法求合并后的数量。');
    expect(lesson.toJson(), before);
  });

  test('学一学保留跨页例题的解答与图示，在独立练习标题处结束', () {
    final source = mathMisclassifiedPracticeFixture();
    MathTextbookBlock continuation(
      String id,
      MathTextbookBlockKind kind,
      String text,
    ) => MathTextbookBlock(
      id: id,
      kind: kind,
      spans: [MathTextbookSpan.text(text)],
      sources: const [
        MathTextbookRegion(page: 2, left: .1, top: .1, right: .9, bottom: .3),
      ],
    );
    final lesson = source.edit(
      blocks: [
        source.blocks.first,
        continuation('source', MathTextbookBlockKind.sourcePage, ''),
        continuation('step', MathTextbookBlockKind.heading, '回顾与反思'),
        continuation('explanation', MathTextbookBlockKind.text, '检查画出的线段长度。'),
        continuation('diagram', MathTextbookBlockKind.illustration, '线段示意图'),
        continuation('practice', MathTextbookBlockKind.heading, '做一做'),
        continuation('question', MathTextbookBlockKind.text, '画一条新的线段。'),
      ],
    );
    final examples = mathTextbookWorkedExamples(lesson);
    expect(examples.single.id, source.blocks.first.id);
    expect(examples.single.blocks.map((b) => b.id), [
      'example',
      'step',
      'explanation',
      'diagram',
    ]);
  });

  TextbookPageText pageWithLine(String line, {int page = 1}) =>
      TextbookPageText(
        page: page,
        text: line,
        width: 600,
        height: 800,
        glyphs: [
          for (var i = 0; i < line.length; i++)
            TextbookPageGlyph(
              text: line[i],
              index: i,
              left: .2 + i * .02,
              right: .218 + i * .02,
              top: .6,
              bottom: .625,
            ),
        ],
      );
  const region = MathTextbookRegion(
    page: 1,
    left: .1,
    top: .2,
    right: .9,
    bottom: .9,
    printedPage: '12',
  );
  for (final heading in ['做一做', '练习十一', '试一试']) {
    test('例题图片在独立的“$heading”标题之前结束，保留原有来源信息', () {
      final crop = mathTextbookExampleRegion(region, pageWithLine(heading));
      expect(crop.top, region.top);
      expect(crop.left, region.left);
      expect(crop.right, region.right);
      expect(crop.bottom, lessThan(.6));
      expect(crop.bottom, greaterThan(.58));
      expect(crop.printedPage, '12');
    });
  }
  for (final text in ['想一想：还能怎样计算？', '请做一做下面的练习。', '阅读与理解']) {
    test('例题正文“$text”不触发截断', () {
      expect(
        mathTextbookExampleRegion(region, pageWithLine(text)),
        same(region),
      );
    });
  }
  test('无文字层或其他页的标题不改变图片范围', () {
    expect(mathTextbookExampleRegion(region, pageWithLine('')), same(region));
    expect(
      mathTextbookExampleRegion(region, pageWithLine('做一做', page: 2)),
      same(region),
    );
  });
  test('例题的解释与练习标题并排时，不能为了裁标题而截断解释', () {
    final heading = pageWithLine('做一做');
    final page = TextbookPageText(
      page: 1,
      text: '做一做方法',
      width: 600,
      height: 800,
      glyphs: [
        ...heading.glyphs,
        const TextbookPageGlyph(
          text: '方',
          index: 3,
          left: .65,
          right: .67,
          top: .585,
          bottom: .605,
        ),
        const TextbookPageGlyph(
          text: '法',
          index: 4,
          left: .67,
          right: .69,
          top: .585,
          bottom: .605,
        ),
      ],
    );
    expect(mathTextbookExampleRegion(region, page), same(region));
  });
}
