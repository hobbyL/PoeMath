import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';

import 'textbook_fixture.dart';

Textbook mathTextbookFixture({int pages = 3}) => textbookFixture(
  title: '自有数学测试教材',
  subject: TextbookSubject.math,
  pageCount: pages,
);

/// 自有二维排版，索引按码点递增；不含真实教材文字或图像。
class MathPageFixture {
  MathPageFixture(this.page);
  final int page;
  String _text = '';
  final glyphs = <TextbookPageGlyph>[];
  final lines = <MathTextbookLine>[];
  final regions = <MathTextbookRegion>[];

  void text(
    String value,
    double x,
    double y, {
    double width = .02,
    double height = .025,
    double? step,
  }) {
    var index = _text.runes.length;
    for (final rune in value.runes) {
      glyphs.add(
        TextbookPageGlyph(
          text: String.fromCharCode(rune),
          index: index++,
          left: x,
          top: y,
          right: x + width,
          bottom: y + height,
        ),
      );
      x += step ?? width * 1.05;
    }
    _text += '$value\n';
  }

  void fraction(String top, String bottom, double x, double y) {
    text(top, x, y - .025, width: .016, height: .018);
    text(bottom, x, y + .004, width: .016, height: .018);
    lines.add(
      MathTextbookLine(left: x - .002, right: x + .019, y: y, dark: true),
    );
  }

  MathTextbookPageLayout build({
    bool graphicsComplete = true,
    String status = 'text_extracted',
  }) => MathTextbookPageLayout(
    text: TextbookPageText(
      page: page,
      text: _text,
      width: 600,
      height: 800,
      glyphs: glyphs,
      status: status,
    ),
    graphics: MathTextbookGraphics(
      lines: lines,
      regions: regions,
      complete: graphicsComplete,
    ),
  );
}

MathTextbookLesson mathLessonFixture({
  int start = 1,
  int end = 2,
  String title = '自有分数课',
}) {
  final pages = <MathTextbookPageLayout>[];
  for (var page = start; page <= end; page++) {
    final layout = MathPageFixture(page);
    layout.text('观察自有图形', .1, .08);
    layout.text('其中的', .1, .18);
    layout.fraction('1', '4', .175, .194);
    layout.text('涂上颜色。', .21, .18);
    pages.add(layout.build());
  }
  return const MathTextbookDraftParser().parse(
    title: title,
    startPage: start,
    endPage: end,
    pages: pages,
  );
}
