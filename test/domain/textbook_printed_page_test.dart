import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_page_numbers.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_printed_page.dart';

import '../helpers/textbook_page_number_fixture.dart';

void main() {
  test('实际左右页脚合并乱序的单、双、三位数字，不使用 PDF 页序', () {
    expect(printedTextbookPage(printedPageFixture(7, 2)), 2);
    expect(
      printedTextbookPage(printedPageFixture(31, 26, reverseGlyphs: true)),
      26,
    );
    expect(
      printedTextbookPage(
        printedPageFixture(8, 123, left: 0.88, reverseGlyphs: true),
      ),
      123,
    );
  });

  test('正文、中央数字、年份、页面外内容与没有字框不能提供书页', () {
    expect(printedTextbookPage(printedPageFixture(7, 2, top: 0.5)), isNull);
    expect(printedTextbookPage(printedPageFixture(7, 2, left: 0.5)), isNull);
    expect(printedTextbookPage(printedPageFixture(7, 2022)), isNull);
    expect(printedTextbookPage(printedPageFixture(7, 2, left: 1.1)), isNull);
    expect(
      printedTextbookPage(
        const TextbookPageText(page: 7, text: '2', width: 500, height: 700),
      ),
      isNull,
    );
    expect(printedTextbookPage(printedPageFixture(7, null)), isNull);
  });

  test('两个可见页脚数字冲突时不默选，脚注圈号不覆盖真正页码', () {
    final left = printedPageFixture(6, 1);
    final right = printedPageFixture(6, 2, left: 0.9);
    final conflict = TextbookPageText(
      page: 6,
      text: '12',
      width: left.width,
      height: left.height,
      glyphs: [
        ...left.glyphs,
        for (final glyph in right.glyphs)
          TextbookPageGlyph(
            text: glyph.text,
            index: glyph.index + 1,
            left: glyph.left,
            right: glyph.right,
            top: glyph.top,
            bottom: glyph.bottom,
          ),
      ],
    );
    expect(printedTextbookPage(conflict), isNull);
    final page = printedPageFixture(6, 1, left: 0.909);
    final footnote = TextbookPageText(
      page: 6,
      text: '1①',
      width: page.width,
      height: page.height,
      glyphs: [
        ...page.glyphs,
        const TextbookPageGlyph(
          text: '①',
          index: 1,
          left: 0.12,
          right: 0.14,
          top: 0.8704,
          bottom: 0.8841,
        ),
      ],
    );
    expect(printedTextbookPage(footnote), 1);
  });

  test('已完成无编号与未读取不同，对开只有连续书页合成区间', () {
    final numbers = TextbookPageNumbers(
      pageCount: 9,
      pages: {1: null, 6: 1, 7: 2, 8: 9, 9: 2},
    );
    expect(numbers.label(1), '未标页码');
    expect(numbers.label(3), '正在读取页码');
    expect(numbers.labelForPages([6, 7]), '第 1–2 页');
    expect(numbers.labelForPages([7, 8]), '第 2 页 · 第 9 页');
    expect(numbers.labelForPages([1, 6]), '未标页码 · 第 1 页');
    expect(numbers.targets(2), [7, 9]);
    expect(numbers.complete, isFalse);
  });
}
