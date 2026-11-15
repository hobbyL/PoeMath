import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

import '../helpers/math_textbook_fixture.dart';

MathTextbookLesson _parse(
  MathPageFixture page, {
  bool legacy = false,
  bool organized = false,
}) {
  final lesson = MathTextbookDraftParser(legacyLayout: legacy).parse(
    title: '自有教材提取验收',
    startPage: page.page,
    endPage: page.page,
    pages: [page.build()],
  );
  return organized ? organizeMathTextbookLesson(lesson) : lesson;
}

List<MathTextbookExpression> _expressions(MathTextbookLesson lesson) => lesson
    .blocks
    .expand((block) => block.spans)
    .map((span) => span.expression)
    .whereType<MathTextbookExpression>()
    .toList();

MathPageFixture _vertical(String operation, List<String> rows) {
  final page = MathPageFixture(1);
  for (var row = 0; row < rows.length; row++) {
    for (var column = 0; column < rows[row].length; column++) {
      final char = rows[row][column];
      if (char == ' ') continue;
      final y = [.30, .35, .405][row];
      page.text(
        char,
        .52 + column * .03,
        char == '.' ? y + .013 : y,
        width: char == '.' ? .006 : .014,
        height: char == '.' ? .005 : .02,
      );
    }
  }
  page.text(
    operation,
    .49,
    operation == '-' ? .36 : .35,
    width: .014,
    height: operation == '-' ? .003 : .02,
  );
  page.lines.add(
    const MathTextbookLine(left: .49, right: .62, y: .395, dark: true),
  );
  return page;
}

void main() {
  test('绘图读取不完整时显示整页，不把缺图题干作为完整题组', () {
    final input = (MathPageFixture(
      1,
    )..text('1. 根据图中的条件，回答下面的问题。', .1, .2)).build();
    final lesson = const MathTextbookDraftParser().parse(
      title: '绘图读取失败的原页',
      startPage: 1,
      endPage: 1,
      pages: [
        MathTextbookPageLayout(
          text: input.text,
          graphics: MathTextbookGraphics(complete: false),
        ),
      ],
    );
    expect(lesson.blocks.single.kind, MathTextbookBlockKind.sourcePage);
    expect(lesson.blocks.single.sources.single.toJson(), {
      'page': 1,
      'left': 0.0,
      'top': 0.0,
      'right': 1.0,
      'bottom': 1.0,
    });
    expect(lesson.blocks.single.warnings, ['本页绘图证据未完整读取，已保留整页']);
    expect(
      mathTextbookReadingBlocks(lesson.blocks).single.toJson(),
      lesson.blocks.single.toJson(),
    );
    final learning = seedMathTextbookLearning(lesson);
    expect(learning.exercises, isEmpty);
    expect(learning.knowledgePoints, isEmpty);
    expect(learning.practicePlans, isEmpty);
  });

  test('图片中的位置编号属于题目配图，不成为新题组或截断题干', () {
    final page = MathPageFixture(1)
      ..text('2. 请判断各幅图片是在什么位置看到的。', .1, .2)
      ..text('1', .15, .40)
      ..text('2', .45, .40)
      ..text('3', .75, .40)
      ..text('3. 把对应的图形连起来。', .1, .65);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .13,
        top: .3,
        right: .88,
        bottom: .58,
      ),
    );
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .14,
        top: .393,
        right: .181,
        bottom: .433,
      ),
    );
    final lesson = _parse(page, organized: true);
    final questions = seedMathTextbookLearning(lesson).exercises;
    expect(questions.map((question) => question.number), ['2', '3']);
    final second = lesson.blocks.firstWhere(
      (block) => block.exerciseNumber == '2',
    );
    expect(second.text, contains('各幅图片是在什么位置看到的'));
    expect(second.sourceLayout, isTrue);
    expect(second.sources.single.bottom, greaterThan(.58));
    expect(second.sources.single.right, greaterThanOrEqualTo(.88));
  });

  test('与前题同栏的图画题号保留独立题组，整幅图片属于本题', () {
    final page = MathPageFixture(1)
      ..text('做一做', .1, .08, height: .03)
      ..text('1', .106, .2, width: .012, height: .018)
      ..text('计算并填写结果。', .16, .2)
      ..text('2', .106, .55, width: .012, height: .018)
      ..text('3元', .35, .72);
    page.regions.addAll(const [
      MathTextbookRegion(
        page: 1,
        left: .095,
        top: .193,
        right: .129,
        bottom: .224,
      ),
      MathTextbookRegion(
        page: 1,
        left: .095,
        top: .543,
        right: .129,
        bottom: .574,
      ),
      MathTextbookRegion(page: 1, left: .17, top: .54, right: .85, bottom: .75),
    ]);
    final lesson = _parse(page, organized: true);
    final learning = seedMathTextbookLearning(lesson);
    expect(learning.exercises.map((e) => e.number), ['1', '2']);
    final picture = lesson.blocks.singleWhere((b) => b.exerciseNumber == '2');
    expect(picture.sourceLayout, isTrue);
    expect(picture.sources.single.top, lessThan(.54));
    expect(picture.sources.single.bottom, greaterThan(.75));
    expect(picture.sources.single.right, greaterThanOrEqualTo(.85));
  });

  test('与例题题号同行的大字题干不成为章节标题，原题和配图保持完整', () {
    final page = MathPageFixture(1)
      ..text('示例单元', .1, .08, height: .04)
      ..text('例1', .1, .2, height: .03)
      ..text('这一组同学和带队老师', .4, .205)
      ..text('一共有多少人？', .4, .24)
      ..text('35+2=', .4, .29)
      ..text('插图中使用小字号说明内容', .35, .34, height: .012)
      ..text('插图中使用小字号说明内容', .35, .37, height: .012)
      ..text('插图中使用小字号说明内容', .35, .40, height: .012)
      ..text('做一做', .1, .68, height: .03)
      ..text('1. 完成下一题。', .1, .75);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .32,
        top: .19,
        right: .9,
        bottom: .52,
      ),
    );
    final lesson = _parse(page, organized: true);
    final example = lesson.blocks.singleWhere(
      (b) => b.kind == MathTextbookBlockKind.example,
    );
    expect(example.exerciseNumber, '1');
    expect(example.sources.single.top, lessThan(.2));
    expect(example.sources.single.bottom, greaterThan(.52));
    expect(example.sources.single.right, greaterThanOrEqualTo(.9));
    expect(example.sourceLayout, isTrue);
    expect(
      lesson.blocks
          .where((b) => b.kind == MathTextbookBlockKind.heading)
          .map((b) => b.text),
      isNot(contains('这一组同学和带队老师')),
    );
  });

  test('相邻横式不属于竖式计算行，空结果的竖式仍按原列位恢复', () {
    final page = _vertical('+', ['56', '37', '  '])
      ..text('56+37=', .51, .25, width: .014, height: .02, step: .02)
      ..text('8+2=10', .51, .445, width: .014, height: .02, step: .02);
    final expressions = _expressions(_parse(page));
    final vertical = expressions
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(vertical.rows, ['56', '37', '  ']);
    expect(vertical.readable, contains('尚未填写'));
    expect(
      expressions.whereType<MathTextbookSequence>().map((e) => e.readable),
      containsAll(['56+37=', '8+2=10']),
    );
  });

  test('大例题号与同行的括号子题合并，主编号和全部子题仍属于同一例题', () {
    final page = MathPageFixture(1)
      ..text('3', .106, .2, width: .018, height: .03)
      ..text('（1）根据图中的条件计算。', .18, .204)
      ..text('（2）解释下面的计算过程。', .18, .48)
      ..text('做一做', .1, .75);
    page.regions.addAll(const [
      MathTextbookRegion(
        page: 1,
        left: .095,
        top: .193,
        right: .144,
        bottom: .239,
      ),
      MathTextbookRegion(page: 1, left: .2, top: .25, right: .85, bottom: .70),
    ]);
    final lesson = _parse(page, organized: true);
    final example = lesson.blocks.singleWhere(
      (b) => b.kind == MathTextbookBlockKind.example,
    );
    expect(example.exerciseNumber, '3');
    expect(example.text, contains('（1）'));
    expect(example.text, contains('（2）'));
    expect(example.sources.single.bottom, greaterThan(.7));
    expect(example.sourceLayout, isTrue);
    expect(seedMathTextbookLearning(lesson).exercises, isEmpty);
  });

  test('图画例题的大题号保留，即使本页没有相邻的例题编号', () {
    final page = MathPageFixture(1)
      ..text('加法的认识', .1, .08, height: .028)
      ..text('1', .106, .2, width: .018, height: .03)
      ..text('3+1=4', .35, .52)
      ..text('做一做', .1, .65)
      ..text('1. 看图计算。', .1, .75);
    page.regions.addAll(const [
      MathTextbookRegion(
        page: 1,
        left: .095,
        top: .193,
        right: .144,
        bottom: .239,
      ),
      MathTextbookRegion(page: 1, left: .23, top: .19, right: .85, bottom: .45),
    ]);
    final lesson = _parse(page, organized: true);
    final example = lesson.blocks.singleWhere(
      (b) => b.kind == MathTextbookBlockKind.example,
    );
    expect(example.exerciseNumber, '1');
    expect(example.sources.single.bottom, greaterThan(.45));
    expect(example.sourceLayout, isTrue);
    expect(seedMathTextbookLearning(lesson).knowledgePoints, hasLength(1));
    expect(seedMathTextbookLearning(lesson).exercises, hasLength(1));
    expect(seedMathTextbookLearning(lesson).knowledgePoints.single.summary, '');
    expect(
      seedMathTextbookLearning(lesson, legacyLayout: true).knowledgePoints,
      isEmpty,
    );
  });

  test('试商的商、被除数、积和余数不是分子分母，完整列式保留', () {
    final page = MathPageFixture(1)
      ..text('2. 根据试商情况，说出准确的商。', .1, .12)
      ..text('3', .52, .26, width: .014, height: .02)
      ..text('22', .44, .30, width: .014, height: .02)
      ..text('64', .49, .30, width: .014, height: .02)
      ..text('66', .49, .35, width: .014, height: .02)
      ..text('1', .515, .399, width: .014, height: .02);
    page.lines.addAll(const [
      MathTextbookLine(left: .48, right: .55, y: .294, dark: true),
      MathTextbookLine(left: .48, right: .55, y: .389, dark: true),
    ]);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .473,
        top: .293,
        right: .483,
        bottom: .324,
      ),
    );
    final lesson = _parse(page, organized: true);
    expect(_expressions(lesson).whereType<MathTextbookFraction>(), isEmpty);
    final question = lesson.blocks.singleWhere((b) => b.exerciseNumber == '2');
    expect(question.sourceLayout, isTrue);
    expect(question.sources.single.bottom, greaterThan(.419));
    expect(
      _expressions(_parse(page, legacy: true))
          .whereType<MathTextbookFraction>(),
      isNotEmpty,
    );
  });

  test('对齐的商和被除数仍按除法括号保留，不能转成26/78', () {
    final page = MathPageFixture(1)
      ..text('1. 观察竖式并计算。', .1, .12)
      ..text('26', .50, .268, width: .014, height: .02)
      ..text('3', .464, .31, width: .014, height: .02)
      ..text('78', .50, .31, width: .014, height: .02)
      ..text('78', .50, .36, width: .014, height: .02)
      ..text('0', .52, .414, width: .014, height: .02);
    page.lines.addAll(const [
      MathTextbookLine(left: .49, right: .555, y: .305, dark: true),
      MathTextbookLine(left: .49, right: .555, y: .397, dark: true),
    ]);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .480,
        top: .304,
        right: .492,
        bottom: .336,
      ),
    );
    final lesson = _parse(page, organized: true);
    expect(_expressions(lesson).whereType<MathTextbookFraction>(), isEmpty);
    final question = lesson.blocks.singleWhere((b) => b.exerciseNumber == '1');
    expect(question.sourceLayout, isTrue);
    expect(question.sources.single.bottom, greaterThan(.434));
    expect(
      _expressions(_parse(page, legacy: true))
          .whereType<MathTextbookFraction>()
          .map((e) => e.readable),
      contains('26/78'),
    );
  });

  test('小写单位的矮字形仍恢复实际上标，普通cm2保持原样', () {
    final page = MathPageFixture(1)
      ..text('c', .40, .30, width: .01, height: .012)
      ..text('m', .413, .30, width: .02, height: .012)
      ..text('2', .435, .289, width: .009, height: .0105)
      ..text('cm2', .40, .45, width: .014, height: .02);
    final expressions = _expressions(_parse(page));
    expect(expressions.whereType<MathTextbookPower>().single.readable, 'cm²');
    expect(_parse(page).blocks.map((b) => b.text).join(), contains('cm2'));
    expect(
      _expressions(_parse(page, legacy: true)).whereType<MathTextbookPower>(),
      isEmpty,
    );
  });

  test('细数字1的墨迹间隙不会丢失11分母和11分子', () {
    final page = MathPageFixture(1)
      ..text('6', .515, .204, width: .0112, height: .012)
      ..text('11', .509, .223, width: .0077, height: .012, step: .0152)
      ..text('11', .65, .204, width: .0077, height: .012, step: .0152)
      ..text('6', .65585, .223, width: .0112, height: .012);
    page.lines.addAll(const [
      MathTextbookLine(left: .505, right: .538, y: .220, dark: true),
      MathTextbookLine(left: .645, right: .678, y: .220, dark: true),
    ]);
    expect(
      _expressions(_parse(page))
          .whereType<MathTextbookFraction>()
          .map((e) => e.readable),
      ['6/11', '11/6'],
    );
    expect(
      _expressions(_parse(page, legacy: true))
          .whereType<MathTextbookFraction>(),
      isEmpty,
    );
  });

  test('填空题的左括号与题号同行时仍连接右括号和完整题干', () {
    final page = MathPageFixture(1)
      ..text('做一做', .1, .08)
      ..text('1', .106, .205, width: .008, height: .013)
      ..text('（', .15, .20, width: .007, height: .018)
      ..text('）里最大能填几？', .22, .20, width: .024, height: .018)
      ..text('2. 完成计算。', .1, .5);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .09,
        top: .193,
        right: .135,
        bottom: .229,
      ),
    );
    final lesson = _parse(page, organized: true);
    final first = lesson.blocks.singleWhere((b) => b.exerciseNumber == '1');
    expect(first.kind, MathTextbookBlockKind.exercise);
    expect(first.text, contains('里最大能填几？'));
    expect(first.sources.single.right, greaterThan(.4));
    expect(
      lesson.blocks
          .where((b) => b.kind == MathTextbookBlockKind.exercise)
          .map((b) => b.exerciseNumber),
      ['1', '2'],
    );
  });

  test('重叠的同一个题号只保留一次，普通相邻的44仍保留', () {
    final page = MathPageFixture(1)
      ..text('4. 看图填序号。', .1, .2)
      ..text('4', .107, .199)
      ..text('44. 计算并检查。', .1, .6);
    final lesson = _parse(page);
    expect(
      lesson.blocks
          .where((block) => block.exerciseNumber != null)
          .map((block) => block.exerciseNumber),
      ['4', '44'],
    );
    expect(
      _parse(page, legacy: true).blocks
          .where((block) => block.exerciseNumber != null)
          .map((block) => block.exerciseNumber),
      contains('44'),
    );
  });

  test('分步计算只写个位7时保留十位空位，不伪造35+2=7', () {
    final page = _vertical('+', ['35', ' 2', ' 7']);
    final lesson = _parse(page);
    final expression = _expressions(lesson)
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(expression.rows, ['35', ' 2', ' 7']);
    expect(expression.readable, contains('空位、7'));
    expect(expression.readable, isNot(contains('= 7')));
    expect(expression.latex, contains(r'&{}&7\end{array}'));
    expect(lesson.blocks.first.sourceLayout, isTrue);
    final old = _expressions(_parse(page, legacy: true))
        .whereType<MathTextbookVerticalAddition>()
        .single;
    expect(old.readable, '35 + 2 = 7');
  });

  test('未填写结果和括号占位保留原式及完整来源', () {
    final page = _vertical('-', ['48', '36', '  '])
      ..text('（', .51, .405)
      ..text('）', .58, .405);
    final lesson = _parse(page);
    final expression = _expressions(lesson)
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(expression.rows, ['48', '36', '  ']);
    expect(expression.readable, contains('尚未填写'));
    final block = lesson.blocks.firstWhere(
      (block) => block.spans.any((span) => span.expression == expression),
    );
    expect(block.sourceLayout, isTrue);
    expect(block.sources.single.bottom, greaterThan(.425));
  });

  test('薄减号和完整减法结果按数位恢复，不误判为分数', () {
    final expressions = _expressions(
      _parse(_vertical('-', ['48', '36', '12'])),
    );
    final expression = expressions
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(expression.operation, '-');
    expect(expression.rows, ['48', '36', '12']);
    expect(expressions.whereType<MathTextbookFraction>(), isEmpty);
  });

  test('借位后的2、16和圆点保留位置及上下层次', () {
    final page = _vertical('-', ['36', '19', '17'])
      ..text('2', .52, .274, width: .008, height: .01)
      ..text('16', .545, .274, width: .006, height: .01, step: .007)
      ..text('.', .52, .293, width: .005, height: .003);
    final expression = _expressions(_parse(page))
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(expression.annotations.map((annotation) => annotation.toJson()), [
      {'value': '2', 'row': 0, 'columnFromRight': 1},
      {'value': '16', 'row': 0, 'columnFromRight': 0},
      {'value': '.', 'row': 0, 'columnFromRight': 1, 'level': 1},
    ]);
    expect(expression.rows, ['36', '19', '17']);
    expect(expression.latex, contains(r'\scriptstyle 16'));
    expect(expression.latex, contains(r'\scriptstyle \cdot'));
  });

  test('绘图形式的借位圆点和划线保留原版面，不伪造文字标注', () {
    final page = _vertical('-', ['36', '19', '17']);
    page.regions.addAll(const [
      MathTextbookRegion(
        page: 1,
        left: .52,
        top: .291,
        right: .525,
        bottom: .295,
      ),
      MathTextbookRegion(
        page: 1,
        left: .518,
        top: .301,
        right: .537,
        bottom: .318,
      ),
    ]);
    final lesson = _parse(page);
    final formula = lesson.blocks.singleWhere(
      (block) => block.spans.any(
        (span) => span.expression is MathTextbookVerticalArithmetic,
      ),
    );
    final expression =
        formula.spans.single.expression! as MathTextbookVerticalArithmetic;
    expect(expression.rows, ['36', '19', '17']);
    expect(expression.annotations, isEmpty);
    expect(formula.sourceLayout, isTrue);
    expect(formula.sources.single.top, lessThan(.291));
    expect(formula.sources.single.right, greaterThan(.537));
    final reading = mathTextbookReadingBlocks(
      organizeMathTextbookLesson(lesson).blocks,
    );
    expect(reading.single.sourceLayout, isTrue);
    expect(reading.single.sources.single.top, lessThan(.291));
  });

  test('分步进位写在两位数字之间，保留实际进位数位和结果空位', () {
    final page = _vertical('+', ['35', '37', ' 2'])
      ..text('1', .54, .38, width: .006, height: .01);
    final expression = _expressions(_parse(page))
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(expression.rows, ['35', '37', ' 2']);
    expect(expression.annotations.single.toJson(), {
      'value': '1',
      'row': 2,
      'columnFromRight': 1,
    });
    expect(expression.readable, isNot(contains('= 2')));
  });

  test('小数点作为独立数位保留，不能把3.5读成35', () {
    final expression = _expressions(
      _parse(_vertical('+', ['3.5', '2.7', '6.2'])),
    ).whereType<MathTextbookVerticalArithmetic>().single;
    expect(expression.rows, ['3.5', '2.7', '6.2']);
    expect(expression.latex, contains('3&.&5'));
  });

  test('公式与配图合并后仍保留结构，分步结果不会在课时整理中丢失', () {
    final page = _vertical('+', ['35', ' 2', ' 7']);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .48,
        top: .28,
        right: .63,
        bottom: .44,
      ),
    );
    final lesson = _parse(page, organized: true);
    final formula = _expressions(lesson)
        .whereType<MathTextbookVerticalArithmetic>()
        .single;
    expect(formula.rows, ['35', ' 2', ' 7']);
    final block = mathTextbookReadingBlocks(lesson.blocks).single;
    expect(block.sourceLayout, isTrue);
    expect(block.sources.single.top, lessThan(.28));
    expect(block.sources.single.bottom, greaterThan(.44));
    expect(
      _expressions(
        organizeMathTextbookLesson(_parse(page), legacyLayout: true),
      ),
      isEmpty,
    );
  });

  test('三行乘法可结构化，多行积保留全图不把部分积当结果', () {
    final ordinary = _expressions(_parse(_vertical('×', ['12', ' 3', '36'])));
    expect(
      ordinary.whereType<MathTextbookVerticalArithmetic>().single.operation,
      '×',
    );
    final multiple = _vertical('×', ['12', '13', '36'])
      ..text('12', .49, .45, width: .014, height: .02, step: .03)
      ..text('156', .49, .50, width: .014, height: .02, step: .03);
    multiple.lines.add(
      const MathTextbookLine(left: .49, right: .62, y: .49, dark: true),
    );
    final lesson = _parse(multiple, organized: true);
    expect(
      _expressions(lesson).whereType<MathTextbookVerticalArithmetic>(),
      isEmpty,
    );
    final reading = mathTextbookReadingBlocks(lesson.blocks);
    expect(reading.any((block) => block.needsSource), isTrue);
    expect(
      reading
          .map((block) => block.sources.single.bottom)
          .reduce((a, b) => a > b ? a : b),
      greaterThan(.52),
    );
  });

  test('缺少第二条横线证据的多行积仍保留全图，不把部分积当结果', () {
    final page = _vertical('×', ['12', '13', '36'])
      ..text('12', .49, .45, width: .014, height: .02, step: .03)
      ..text('156', .49, .50, width: .014, height: .02, step: .03);
    final lesson = _parse(page, organized: true);
    expect(
      _expressions(lesson).whereType<MathTextbookVerticalArithmetic>(),
      isEmpty,
    );
    final reading = mathTextbookReadingBlocks(lesson.blocks);
    expect(reading.any((block) => block.needsSource), isTrue);
    expect(reading.single.sources.single.bottom, greaterThan(.52));
  });

  test('三个加数的竖式保留所有行，不将最后两个加数拼成完整等式', () {
    final page = MathPageFixture(1)
      ..text('12', .52, .26, width: .014, height: .02, step: .03)
      ..text('23', .52, .30, width: .014, height: .02, step: .03)
      ..text('34', .52, .35, width: .014, height: .02, step: .03)
      ..text('+', .49, .35, width: .014, height: .02)
      ..text('69', .52, .405, width: .014, height: .02, step: .03);
    page.lines.add(
      const MathTextbookLine(left: .49, right: .62, y: .395, dark: true),
    );
    final lesson = _parse(page, organized: true);
    expect(
      _expressions(lesson).whereType<MathTextbookVerticalAddition>(),
      isEmpty,
    );
    final reading = mathTextbookReadingBlocks(lesson.blocks);
    expect(reading.single.sourceLayout, isTrue);
    expect(reading.single.sources.single.top, lessThan(.26));
    expect(reading.single.sources.single.bottom, greaterThan(.425));
  });

  test('中文中的算式和待填答案独立排版，题号不拼入第一个操作数', () {
    final page = MathPageFixture(1)
      ..text('1. 共有12+3=15个，请填写2+3=□。', .1, .2, width: .017, step: .019);
    final lesson = _parse(page);
    final question = lesson.blocks.firstWhere(
      (block) => block.exerciseNumber == '1',
    );
    final equations = question.spans
        .map((span) => span.expression)
        .whereType<MathTextbookSequence>();
    expect(equations.map((equation) => equation.readable), [
      '12+3=15',
      '2+3=□',
    ]);
    expect(equations.last.latex, contains(r'\square'));
    expect(question.text, contains('共有12+3=15个'));
  });

  test('日期、ISBN及图上孤立数字不伪造公式，未知公式保留原页', () {
    final page = MathPageFixture(1)
      ..text('2026-11-15', .1, .2)
      ..text('ISBN 978-7-1234-5678-9', .1, .3)
      ..text('1', .1, .4)
      ..text('∫f(x)dx', .1, .5);
    final lesson = _parse(page);
    expect(_expressions(lesson), isEmpty);
    expect(
      lesson.blocks.where((block) => block.exerciseNumber != null),
      isEmpty,
    );
    expect(lesson.blocks.map((block) => block.text).join(), contains('∫'));
    expect(lesson.blocks.last.kind, MathTextbookBlockKind.sourcePage);
  });
}
