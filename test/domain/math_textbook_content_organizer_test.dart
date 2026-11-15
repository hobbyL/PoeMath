import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

import '../helpers/math_textbook_fixture.dart';

MathTextbookBlock _block(
  String id,
  MathTextbookBlockKind kind,
  String text,
  double top,
  double bottom, {
  String? number,
}) => MathTextbookBlock(
  id: id,
  kind: kind,
  spans: text.isEmpty ? const [] : [MathTextbookSpan.text(text)],
  sources: [
    MathTextbookRegion(page: 1, left: .1, top: top, right: .9, bottom: bottom),
  ],
  exerciseNumber: number,
);

MathTextbookLesson _lesson(
  List<MathTextbookBlock> blocks, {
  String title = '自有例题',
}) => MathTextbookLesson(
  id: 'math-1-1',
  title: title,
  startPage: 1,
  endPage: 1,
  blocks: [
    ...blocks,
    _block('source', MathTextbookBlockKind.sourcePage, '', 0, 1),
  ],
);

void main() {
  for (final parallel in [false, true]) {
    test(parallel ? '无配图的并列待填算式仍按原书保留列位' : '连续上下算式保持结构化展示', () {
      MathTextbookBlock formula(
        String id,
        double left,
        double top,
        String operand,
        String operation,
      ) => MathTextbookBlock(
        id: id,
        kind: MathTextbookBlockKind.formula,
        spans: [
          MathTextbookSpan.math(
            MathTextbookSequence([
              MathTextbookAtom(operand),
              MathTextbookAtom(operation),
              const MathTextbookAtom('2'),
              const MathTextbookAtom('='),
            ]),
          ),
        ],
        sources: [
          MathTextbookRegion(
            page: 1,
            left: left,
            top: top,
            right: left + .12,
            bottom: top + .025,
          ),
        ],
      );
      final organized = organizeMathTextbookLesson(
        _lesson([
          _block(
            'question',
            MathTextbookBlockKind.exercise,
            '1 计算。',
            .1,
            .15,
            number: '1',
          ),
          formula('left', .2, .3, '3', '+'),
          formula('right', parallel ? .65 : .2, parallel ? .3 : .4, '7', '-'),
        ]),
      );
      final question = organized.blocks.singleWhere(
        (b) => b.exerciseNumber == '1',
      );
      expect(question.sourceLayout, parallel);
      expect(
        question.spans
            .map((s) => s.expression)
            .whereType<MathTextbookSequence>()
            .map((e) => e.readable),
        ['3+2=', '7-2='],
      );
    });
  }

  test('配图下沿跨过下一题起始行时完整保留，下一题题干也不裁掉', () {
    final raw = _lesson([
      _block(
        'first',
        MathTextbookBlockKind.exercise,
        '1 根据图表回答。',
        .2,
        .235,
        number: '1',
      ),
      _block('chart', MathTextbookBlockKind.illustration, '', .26, .54),
      _block(
        'next',
        MathTextbookBlockKind.exercise,
        '2 完成下一道题。',
        .5,
        .545,
        number: '2',
      ),
    ]);
    final organized = organizeMathTextbookLesson(raw);
    final first = organized.blocks.singleWhere((b) => b.exerciseNumber == '1');
    final next = organized.blocks.singleWhere((b) => b.exerciseNumber == '2');
    expect(first.sourceLayout, isTrue);
    expect(first.sources.single.bottom, greaterThanOrEqualTo(.54));
    expect(next.sources.single.top, lessThanOrEqualTo(.5));
    expect(next.text, contains('完成下一道题。'));
    expect(
      organizeMathTextbookLesson(raw, legacyLayout: true).blocks
          .singleWhere((b) => b.exerciseNumber == '1')
          .sources
          .single
          .bottom,
      lessThan(.51),
    );
  });

  test('练习标题后的题目保持练习分类，不受小字号图注影响变成例题', () {
    final lesson = organizeMathTextbookLesson(
      _lesson([
        _block(
          'example',
          MathTextbookBlockKind.example,
          '例3 观察示例中的计算过程。',
          .1,
          .3,
          number: '3',
        ),
        _block('practice', MathTextbookBlockKind.heading, '做一做', .4, .44),
        _block(
          'question2',
          MathTextbookBlockKind.example,
          '2 计算并填空。',
          .5,
          .6,
          number: '2',
        ),
        _block(
          'question3',
          MathTextbookBlockKind.example,
          '3 完成下面的算式。',
          .7,
          .8,
          number: '3',
        ),
      ]),
    );
    final learning = seedMathTextbookLearning(lesson);
    expect(learning.knowledgePoints, hasLength(1));
    expect(learning.exercises.map((e) => e.number), ['2', '3']);
  });

  for (final kind in [
    MathTextbookBlockKind.example,
    MathTextbookBlockKind.exercise,
  ]) {
    test('$kind 内大字提示和答案单位不切开原题，下一题仍独立', () {
      final lesson = organizeMathTextbookLesson(
        _lesson([
          _block('question', kind, '1 根据原书给定的条件计算。', .1, .2, number: '1'),
          _block(
            'caption',
            MathTextbookBlockKind.heading,
            '除法也可以写成竖式',
            .3,
            .34,
          ),
          _block('diagram', MathTextbookBlockKind.illustration, '', .36, .60),
          _block('unit', MathTextbookBlockKind.heading, '（个）……（根）', .64, .68),
          _block(
            'next',
            MathTextbookBlockKind.exercise,
            '2 完成下一道题。',
            .8,
            .85,
            number: '2',
          ),
        ]),
      );
      final first = lesson.blocks.firstWhere((b) => b.exerciseNumber == '1');
      expect(first.kind, kind);
      expect(first.sources.single.bottom, greaterThan(.68));
      expect(first.sourceLayout, isTrue);
      expect(first.text, contains('除法也可以写成竖式'));
      expect(first.text, contains('（个）……（根）'));
      expect(
        lesson.blocks
            .singleWhere((b) => b.exerciseNumber == '2')
            .sources
            .single
            .top,
        greaterThan(.7),
      );
    });
  }

  test('与课时名称一致的编号章节标题不生成虚假练习题', () {
    final raw = _lesson([
      _block(
        'chapter',
        MathTextbookBlockKind.exercise,
        '2. 分数除法',
        .08,
        .13,
        number: '2',
      ),
      _block(
        'example',
        MathTextbookBlockKind.example,
        '例1 观察分数除法的计算过程。',
        .18,
        .23,
        number: '1',
      ),
      _block('content', MathTextbookBlockKind.text, '根据折纸实验理解分数的意义。', .25, .6),
    ], title: '分数除法');
    final organized = organizeMathTextbookLesson(raw);
    expect(organized.blocks.first.kind, MathTextbookBlockKind.heading);
    expect(organized.blocks.first.exerciseNumber, isNull);
    expect(seedMathTextbookLearning(organized).exercises, isEmpty);
    expect(seedMathTextbookLearning(organized).knowledgePoints, hasLength(1));
    expect(
      seedMathTextbookLearning(
        organizeMathTextbookLesson(raw, legacyLayout: true),
      ).exercises.single.number,
      '2',
    );
  });

  test('阅读、分析和回顾属于同一例题，完整解答和图表不被阶段标题截断', () {
    final raw = _lesson([
      _block(
        'example',
        MathTextbookBlockKind.example,
        '例5 根据给定关系求出未知量。',
        .1,
        .18,
        number: '5',
      ),
      _block('read', MathTextbookBlockKind.heading, '阅读与理解', .2, .23),
      _block('conditions', MathTextbookBlockKind.text, '先明确原题给定的条件。', .24, .30),
      _block('analyze', MathTextbookBlockKind.heading, '分析与解答', .35, .38),
      _block('process', MathTextbookBlockKind.text, '先列出等量关系，再求出未知量。', .4, .60),
      _block('reflect', MathTextbookBlockKind.heading, '回顾与反思', .66, .69),
      _block('check', MathTextbookBlockKind.text, '对照原题条件检验结果是否合理。', .72, .8),
      _block('diagram', MathTextbookBlockKind.illustration, '', .19, .86),
    ]);
    final lesson = organizeMathTextbookLesson(raw);
    final example = lesson.blocks.singleWhere(
      (b) => b.kind == MathTextbookBlockKind.example,
    );
    expect(example.exerciseNumber, '5');
    expect(example.sources.single.top, lessThan(.1));
    expect(example.sources.single.bottom, greaterThanOrEqualTo(.86));
    expect(example.sourceLayout, isTrue);
    for (final text in ['阅读与理解', '分析与解答', '回顾与反思', '检验结果是否合理']) {
      expect(example.text, contains(text));
    }
    expect(mathTextbookReadingBlocks(lesson.blocks), hasLength(1));
    expect(seedMathTextbookLearning(lesson).knowledgePoints, hasLength(1));
  });

  for (final inPractice in [false, true]) {
    test(inPractice ? '练习区内的编号题仍保留，即使题干包含先、再、然后' : '例题框内的连续计算步骤不成为新的练习题', () {
      final raw = _lesson([
        _block(
          'example',
          MathTextbookBlockKind.example,
          '例2 观察计算过程。',
          .1,
          .15,
          number: '2',
        ),
        if (inPractice)
          _block('practice', MathTextbookBlockKind.heading, '做一做', .2, .23),
        if (!inPractice)
          _block(
            'discussion',
            MathTextbookBlockKind.text,
            '小组讨论计算的方法。',
            .25,
            .28,
          ),
        _block(
          'step1',
          MathTextbookBlockKind.exercise,
          '1. 先计算第一部分。',
          .35,
          .39,
          number: '1',
        ),
        _block(
          'step2',
          MathTextbookBlockKind.exercise,
          '2. 再计算第二部分。',
          .48,
          .52,
          number: '2',
        ),
        _block(
          'step3',
          MathTextbookBlockKind.exercise,
          '3. 然后把结果相加。',
          .61,
          .65,
          number: '3',
        ),
        _block('frame', MathTextbookBlockKind.illustration, '', .32, .69),
        if (!inPractice) ...[
          _block('practice', MathTextbookBlockKind.heading, '做一做', .75, .78),
          _block(
            'question',
            MathTextbookBlockKind.exercise,
            '1. 完成练习。',
            .82,
            .86,
            number: '1',
          ),
        ],
      ]);
      final lesson = organizeMathTextbookLesson(raw);
      expect(
        seedMathTextbookLearning(lesson).exercises.map((e) => e.number),
        inPractice ? ['1', '2', '3'] : ['1'],
      );
      if (!inPractice) {
        final example = lesson.blocks.singleWhere(
          (b) => b.kind == MathTextbookBlockKind.example,
        );
        expect(example.sources.single.bottom, greaterThan(.69));
        expect(example.text, contains('然后把结果相加'));
        expect(example.sourceLayout, isTrue);
      }
    });
  }

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

  test('旧稿提取不完整时完整原页可见，家长补充的正文仍保留', () {
    final edited = MathTextbookBlock(
      id: 'manual-content',
      kind: MathTextbookBlockKind.text,
      spans: const [MathTextbookSpan.text('这段内容由家长对照原书补充。')],
      sources: const [
        MathTextbookRegion(page: 1, left: .1, top: .2, right: .7, bottom: .3),
      ],
      parentNote: '保留人工修改',
    );
    final source = MathTextbookBlock(
      id: 'incomplete-page-source',
      kind: MathTextbookBlockKind.sourcePage,
      spans: const [],
      sources: const [
        MathTextbookRegion(page: 1, left: 0, top: 0, right: 1, bottom: 1),
      ],
      warnings: const ['本页绘图证据未完整读取，已保留整页'],
    );
    final reading = mathTextbookReadingBlocks([edited, source]);
    expect(reading.map((block) => block.toJson()), [
      edited.toJson(),
      source.toJson(),
    ]);
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
