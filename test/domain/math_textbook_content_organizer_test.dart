import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

import '../helpers/math_textbook_fixture.dart';

void main() {
  test('完整原页按讲解、例题和练习成组，保留题干后续、子题和配图', () {
    final page = MathPageFixture(1)
      ..text('长度的比较', .1, .05, height: .04)
      ..text('1', .1, .15, height: .028, width: .015)
      ..text('比较时要使用相同的长度单位。', .18, .15, height: .022)
      ..text('先把左端对齐，再观察右端的位置。', .18, .195, height: .022)
      ..text('图中标注', .25, .32, height: .016)
      ..text('做一做', .1, .5, height: .026)
      ..text('1', .1, .6, height: .013, width: .01)
      ..text('观察图形并完成下面两项。', .18, .6, height: .022)
      ..text('（1）画出与示例同长的线段。', .18, .65, height: .022)
      ..text('测量标注', .25, .75, height: .016)
      ..text('4', .1, .95, height: .014, width: .01);
    page.regions.addAll(const [
      MathTextbookRegion(
        page: 1,
        left: .09,
        top: .14,
        right: .145,
        bottom: .183,
      ),
      MathTextbookRegion(page: 1, left: .18, top: .27, right: .8, bottom: .44),
      MathTextbookRegion(
        page: 1,
        left: .095,
        top: .595,
        right: .14,
        bottom: .625,
      ),
      MathTextbookRegion(page: 1, left: .18, top: .71, right: .8, bottom: .85),
    ]);
    final parsed = const MathTextbookDraftParser().parse(
      title: '长度的比较',
      startPage: 1,
      endPage: 1,
      pages: [page.build()],
    );
    expect(
      parsed.blocks
          .where((b) => b.kind == MathTextbookBlockKind.example)
          .map((b) => b.exerciseNumber),
      ['1'],
    );
    final organized = organizeMathTextbookLesson(parsed);
    final learning = seedMathTextbookLearning(organized);
    expect(learning.knowledgePoints, hasLength(1));
    expect(
      learning.knowledgePoints.single.summary,
      '比较时要使用相同的长度单位。\n先把左端对齐，再观察右端的位置。',
    );
    expect(learning.exercises, hasLength(1));
    final exercise = organized.blocks.singleWhere(
      (b) => b.id == learning.exercises.single.blockIds.single,
    );
    expect(exercise.text, contains('（1）画出与示例同长的线段。'));
    expect(exercise.sources.single.bottom, closeTo(.854, .001));
    expect(exercise.sources.single.left, lessThanOrEqualTo(.095));
    expect(exercise.needsSource, isTrue);
    expect(exercise.sourceLayout, isTrue);
    expect(
      learning.exercises.single.fields.single.rule.kind,
      MathTextbookAnswerKind.parent,
    );
    expect(
      organized.blocks
          .where((b) => b.kind == MathTextbookBlockKind.sourcePage)
          .single
          .sources
          .single
          .printedPage,
      '4',
    );
    expect(organized.blocks.any((b) => b.text.trim() == '4'), isFalse);
    expect(organized.blocks.every((b) => !b.text.contains('图中标注')), isTrue);
    expect(organized.review, isNull);
  });

  test('已恢复的二维公式仍保留表达式，原页锚点不重复进入阅读正文', () {
    final original = mathLessonFixture();
    final lesson = organizeMathTextbookLesson(original);
    expect(
      lesson.blocks
          .expand((b) => b.spans)
          .where((s) => s.expression is MathTextbookFraction)
          .map((s) => s.expression!.toJson()),
      original.blocks
          .expand((b) => b.spans)
          .where((s) => s.expression is MathTextbookFraction)
          .map((s) => s.expression!.toJson()),
    );
    expect(
      mathTextbookReadingBlocks(lesson.blocks)
          .where((b) => b.kind == MathTextbookBlockKind.sourcePage),
      isEmpty,
    );
    expect(
      lesson.blocks.where((b) => b.kind == MathTextbookBlockKind.sourcePage),
      hasLength(2),
    );
    expect(
      MathTextbookLesson.fromJson(lesson.toJson()).toJson(),
      lesson.toJson(),
    );
  });

  test('无字原页保留整页，不生成虚假的知识点或练习', () {
    final page = MathPageFixture(1);
    final lesson = organizeMathTextbookLesson(
      const MathTextbookDraftParser().parse(
        title: '待核图形',
        startPage: 1,
        endPage: 1,
        pages: [page.build(status: 'no_text')],
      ),
    );
    expect(
      mathTextbookReadingBlocks(lesson.blocks).single.kind,
      MathTextbookBlockKind.sourcePage,
    );
    final learning = seedMathTextbookLearning(lesson);
    expect(learning.knowledgePoints, isEmpty);
    expect(learning.exercises, isEmpty);
    expect(learning.practicePlans, isEmpty);
    expect(learning.coverageConfirmed, isFalse);
  });

  test('原页内容和家长说明中的数字不会被作为页脚去除', () {
    MathTextbookBlock number(String id, double top, {String note = ''}) =>
        MathTextbookBlock(
          id: id,
          kind: MathTextbookBlockKind.text,
          spans: const [MathTextbookSpan.text('4')],
          sources: [
            MathTextbookRegion(
              page: 1,
              left: .1,
              top: top,
              right: .12,
              bottom: top + .02,
            ),
          ],
          parentNote: note,
        );
    final blocks = [
      number('quantity', .4),
      number('note', .94, note: '保留这个数'),
      number('footer', .94),
    ];
    expect(mathTextbookReadingBlocks(blocks).map((b) => b.id), [
      'quantity',
      'note',
    ]);
  });

  test('摘要选完整陈述句，图外短标注保留在原图而不混入知识', () {
    final page = MathPageFixture(1)
      ..text('例1', .1, .12, height: .028)
      ..text('比较两条纸带，你发现了什么？', .18, .18, height: .022)
      ..text('比较前，纸带的左端需要对齐。', .18, .22, height: .022)
      ..text('对齐后，要比较右端的位置。', .18, .26, height: .022)
      ..text('第一条', .3, .45, height: .016)
      ..text('第二条', .65, .45, height: .016)
      ..text('用相同的单位可以比较长短。', .18, .55, height: .022);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .2,
        top: .31,
        right: .8,
        bottom: .42,
      ),
    );
    final lesson = organizeMathTextbookLesson(
      const MathTextbookDraftParser().parse(
        title: '长度比较',
        startPage: 1,
        endPage: 1,
        pages: [page.build()],
      ),
    );
    final knowledge = seedMathTextbookLearning(lesson).knowledgePoints.single;
    expect(knowledge.summary, '比较前，纸带的左端需要对齐。\n对齐后，要比较右端的位置。\n用相同的单位可以比较长短。');
    final block = lesson.blocks.singleWhere(
      (b) => knowledge.blockIds.contains(b.id),
    );
    expect(block.sourceLayout, isTrue);
    expect(block.sources.single.bottom, greaterThan(.55));
    expect(block.text, isNot(contains('第一条')));
    expect(block.text, contains('比较两条纸带，你发现了什么？'));
  });

  test('配图起点高于题号时完整归入该题，不被上一段截走', () {
    final page = MathPageFixture(1)
      ..text('先观察示例中的两条线段。', .15, .2, height: .022)
      ..text('1', .1, .5, height: .014, width: .014)
      ..text('对照图形完成两个小问题。', .18, .5, height: .022)
      ..text('（1）哪条线段更长？', .18, .7, height: .022)
      ..text('（2）说说你的比较方法。', .18, .78, height: .022);
    page.regions.addAll(const [
      MathTextbookRegion(
        page: 1,
        left: .09,
        top: .49,
        right: .14,
        bottom: .525,
      ),
      MathTextbookRegion(page: 1, left: .65, top: .48, right: .88, bottom: .65),
    ]);
    final lesson = organizeMathTextbookLesson(
      const MathTextbookDraftParser().parse(
        title: '画图与比较',
        startPage: 1,
        endPage: 1,
        pages: [page.build()],
      ),
    );
    final exercise = lesson.blocks.singleWhere(
      (b) => b.kind == MathTextbookBlockKind.exercise,
    );
    expect(exercise.sources.single.top, lessThanOrEqualTo(.48));
    expect(exercise.sources.single.bottom, greaterThan(.78));
    expect(exercise.text, contains('（1）哪条线段更长？'));
    expect(exercise.text, contains('（2）说说你的比较方法。'));
    expect(seedMathTextbookLearning(lesson).exercises.single.blockIds, [
      exercise.id,
    ]);
  });

  test('明确字词注音按字体与字典双重核对，单位和代数记号保持原样', () {
    final page = MathPageFixture(1)
      ..text('摆（bAi）好纸带，再比较长度。', .1, .15)
      ..text('电流（mA）与容量（mL）保留原单位。', .1, .3)
      ..text('点（pA）是题目中的标记。', .1, .45);
    final raw = const MathTextbookDraftParser().parse(
      title: '自有注音示例',
      startPage: 1,
      endPage: 1,
      pages: [page.build()],
    );
    final lesson = organizeMathTextbookLesson(raw);
    final text = lesson.blocks.map((b) => b.text).join('\n');
    expect(text, contains('摆（bǎi）'));
    expect(text, contains('电流（mA）'));
    expect(text, contains('容量（mL）'));
    expect(text, contains('点（pA）'));
    expect(raw.blocks.map((b) => b.text).join(), contains('摆（bAi）'));
  });
}
