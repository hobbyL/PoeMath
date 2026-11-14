import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

import '../helpers/math_textbook_fixture.dart';

List<MathTextbookExpression> _expressions(MathTextbookLesson lesson) => lesson
    .blocks
    .expand((b) => b.spans)
    .map((s) => s.expression)
    .whereType<MathTextbookExpression>()
    .toList();

void main() {
  const parser = MathTextbookDraftParser();
  MathTextbookLesson parse(MathPageFixture page, {bool complete = true}) =>
      parser.parse(
        title: '自有数学课',
        startPage: page.page,
        endPage: page.page,
        pages: [page.build(graphicsComplete: complete)],
      );

  test('从完整二维页面恢复中文行内分数，不读取人工选区', () {
    final lesson = mathLessonFixture();
    final paragraph = lesson.blocks.firstWhere(
      (b) => b.spans.any((s) => s.expression is MathTextbookFraction),
    );
    expect(paragraph.text, '其中的1/4 涂上颜色。');
    expect(paragraph.spans.map((s) => s.expression != null), [
      false,
      true,
      false,
    ]);
    expect(paragraph.sources.single.width, lessThan(1));
    expect(
      lesson.blocks.where((b) => b.kind == MathTextbookBlockKind.sourcePage),
      hasLength(2),
    );
  });

  test('带分数、面积体积上标与非 BMP 字符保留', () {
    final page = MathPageFixture(1);
    page.text('𠀀', .1, .08);
    page.text('2', .1, .18, width: .016, height: .025);
    page.fraction('1', '3', .123, .194);
    page.text('cm', .4, .3, width: .018, height: .025);
    page.text('2', .439, .287, width: .009, height: .012);
    page.text('dm', .4, .4, width: .018, height: .025);
    page.text('3', .439, .387, width: .009, height: .012);
    final lesson = parse(page);
    expect(
      _expressions(lesson).whereType<MathTextbookMixedNumber>().single.readable,
      '2 又 1/3',
    );
    expect(
      _expressions(lesson)
          .whereType<MathTextbookPower>()
          .map((e) => e.readable),
      ['cm²', 'dm³'],
    );
    expect(lesson.blocks.map((b) => b.text).join(), contains('𠀀'));
  });

  test('加法竖式按数位恢复三行与进位，不能先误判为分数', () {
    final page = MathPageFixture(1);
    page.text('541', .52, .30, width: .014, height: .020, step: .03);
    page.text('+', .49, .345, width: .014, height: .020);
    page.text('267', .52, .345, width: .014, height: .020, step: .03);
    page.text('808', .52, .398, width: .014, height: .020, step: .03);
    page.text('1', .557, .374, width: .007, height: .010);
    page.text('1', .527, .374, width: .007, height: .010);
    page.lines.add(
      const MathTextbookLine(left: .49, right: .61, y: .389, dark: true),
    );
    final expressions = _expressions(parse(page));
    final vertical = expressions
        .whereType<MathTextbookVerticalAddition>()
        .single;
    expect(vertical.rows, ['541', '267', '808']);
    expect(vertical.carries.map((c) => (c.value, c.columnFromRight)).toSet(), {
      (1, 1),
      (1, 2),
    });
    expect(expressions.whereType<MathTextbookFraction>(), isEmpty);
  });

  test('分数线缺失时保留二维区域，不把上下数字压成整数', () {
    final page = MathPageFixture(1)..fraction('1', '4', .2, .3);
    page.lines.clear();
    final lesson = parse(page, complete: false);
    expect(_expressions(lesson), isEmpty);
    expect(
      lesson.blocks.any(
        (b) =>
            b.kind == MathTextbookBlockKind.illustration &&
            b.warnings.isNotEmpty,
      ),
      isTrue,
    );
    expect(lesson.blocks.map((b) => b.text).join(), isNot(contains('14')));
    expect(lesson.blocks.last.warnings, contains('本页绘图证据未完整读取，已保留整页'));
  });

  test('相邻两行横式不是竖式，空格后的数字也不是题号', () {
    final page = MathPageFixture(1);
    page.text('71 + 52', .1, .2, width: .014, height: .02);
    page.text('54 + 38', .1, .25, width: .014, height: .02);
    final lesson = parse(page);
    expect(
      lesson.blocks.where((b) => b.kind == MathTextbookBlockKind.illustration),
      isEmpty,
    );
    expect(lesson.blocks.where((b) => b.exerciseNumber != null), isEmpty);
    final content = lesson.blocks.map((b) => b.text).join();
    expect(content.replaceAll(' ', ''), contains('71+52'));
    expect(content.replaceAll(' ', ''), contains('54+38'));
  });

  test('窄字形的数字 1 不会因可见边界较窄而被插入空格', () {
    final page = MathPageFixture(1)
      ..text('986+114', .1, .2, width: .014, height: .02, step: .019);
    final one = page.glyphs[4];
    page.glyphs[4] = TextbookPageGlyph(
      text: one.text,
      index: one.index,
      left: one.left,
      top: one.top,
      right: one.left + .001,
      bottom: one.bottom,
    );
    expect(parse(page).blocks.first.text, '986+114');
  });

  test('圆形题号先连接对应题干，不能按左栏先读完所有题号', () {
    final page = MathPageFixture(1);
    for (var i = 1; i <= 2; i++) {
      final y = i * .2;
      page.text('$i', .1, y, width: .014, height: .02);
      page.text('题干内容', .155, y, width: .02, height: .02);
      page.regions.add(
        MathTextbookRegion(
          page: 1,
          left: .092,
          top: y - .004,
          right: .132,
          bottom: y + .031,
        ),
      );
    }
    final exercises = parse(page).blocks
        .where((b) => b.exerciseNumber != null)
        .toList();
    expect(exercises.map((b) => b.text), ['1 题干内容', '2 题干内容']);
    expect(exercises.first.sources.single.right, greaterThan(.2));
  });

  test('引号、低标点和短字形归入正文行，窄栏间隔仍分栏', () {
    final page = MathPageFixture(1);
    page.text('“', .1, .2, width: .009, height: .005);
    page.text('整体', .12, .202, width: .02, height: .02);
    page.text('一', .162, .210, width: .02, height: .002);
    page.text('。', .19, .213, width: .005, height: .005);
    page.text('右侧正文', .26, .202, width: .02, height: .02);
    final texts = parse(page).blocks
        .where((b) => b.kind == MathTextbookBlockKind.text)
        .map((b) => b.text)
        .toList();
    expect(texts, ['“整体一。', '右侧正文']);
  });

  test('正文多栏按栏排序，原图和标注关系保留待核', () {
    final page = MathPageFixture(1);
    page.text('左甲', .1, .1);
    page.text('左乙', .1, .3);
    page.text('右甲', .65, .1);
    page.text('右乙', .65, .3);
    page.regions.add(
      const MathTextbookRegion(
        page: 1,
        left: .2,
        top: .65,
        right: .7,
        bottom: .8,
      ),
    );
    final lesson = parse(page);
    expect(
      lesson.blocks
          .where((b) => b.kind == MathTextbookBlockKind.text)
          .map((b) => b.text),
      ['左甲', '左乙', '右甲', '右乙'],
    );
    expect(
      lesson.blocks
          .where((b) => b.kind == MathTextbookBlockKind.illustration)
          .single
          .warnings,
      isNotEmpty,
    );
  });

  test('跨页只有明确续页语句才合并，缺页失败', () {
    final one = MathPageFixture(1)..text('上页题干', .1, .8);
    final two = MathPageFixture(2)..text('接上页继续观察', .1, .1);
    final continued = parser.parse(
      title: '跨页题',
      startPage: 1,
      endPage: 2,
      pages: [one.build(), two.build()],
    );
    expect(continued.blocks.first.sources.map((s) => s.page), [1, 2]);
    expect(
      continued.blocks.where((b) => b.kind == MathTextbookBlockKind.sourcePage),
      hasLength(2),
    );
    final unrelated = MathPageFixture(2)..text('另一题', .1, .1);
    final separate = parser.parse(
      title: '两页',
      startPage: 1,
      endPage: 2,
      pages: [one.build(), unrelated.build()],
    );
    expect(
      separate.blocks.where((b) => b.kind == MathTextbookBlockKind.text),
      hasLength(2),
    );
    expect(
      () => parser.parse(
        title: '缺页',
        startPage: 1,
        endPage: 2,
        pages: [one.build()],
      ),
      throwsFormatException,
    );
  });

  test('复杂或无字页面仍留下整页和待核原因', () {
    final empty = MathPageFixture(1);
    final lesson = parser.parse(
      title: '图形页',
      startPage: 1,
      endPage: 1,
      pages: [empty.build(status: 'no_text')],
    );
    expect(lesson.blocks.single.kind, MathTextbookBlockKind.sourcePage);
    expect(lesson.blocks.single.sources.single.toJson(), {
      'page': 1,
      'left': 0.0,
      'top': 0.0,
      'right': 1.0,
      'bottom': 1.0,
    });
    expect(lesson.blocks.single.warnings, hasLength(2));
    empty.lines.addAll(
      List.filled(
        2001,
        const MathTextbookLine(left: .1, right: .2, y: .3, dark: true),
      ),
    );
    expect(parse(empty).blocks.single.warnings.single, contains('较复杂'));
  });
}
