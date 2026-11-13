import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';

const _footerTop = 0.88;
const _footerBottom = 0.9;
const _cornerWidth = 0.25;
const _maxFooterHeight = 0.045;
const _maxNumberWidth = 0.13;
const _gapHeightFactor = 1.5;
// 小学教材使用单至三位页码；四位年份等数字不能成为页脚证据。
final _pageDigits = RegExp(r'^[0-9]{1,3}$');

/// 只认当前可见页脚的独立数字，不从 PDF 页序或相邻页推算书页。
int? printedTextbookPage(TextbookPageText page) =>
    printedTextbookFooter(TextbookTocPage.fromPageText(page).glyphs);

int? printedTextbookFooter(Iterable<TextbookTocGlyph> pageGlyphs) {
  final glyphs =
      pageGlyphs
          .where(
            (g) =>
                g.text.trim().isNotEmpty &&
                g.left >= 0 &&
                g.right <= 1 &&
                g.top >= _footerTop &&
                g.top + g.height <= 1 &&
                g.right > g.left &&
                g.height > 0 &&
                g.height <= _maxFooterHeight,
          )
          .toList()
        ..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<TextbookTocGlyph>>[];
  for (final glyph in glyphs) {
    final row = rows.where((row) {
      final anchor = row.first;
      final height = anchor.height > glyph.height
          ? anchor.height
          : glyph.height;
      return ((anchor.top + anchor.height / 2) - (glyph.top + glyph.height / 2))
              .abs() <=
          height / 2;
    }).firstOrNull;
    if (row == null) {
      rows.add([glyph]);
    } else {
      row.add(glyph);
    }
  }

  final candidates = <int>[];
  for (final row in rows) {
    row.sort((a, b) => a.left.compareTo(b.left));
    final runs = <List<TextbookTocGlyph>>[];
    for (final glyph in row) {
      final prior = runs.lastOrNull?.last;
      final gap = prior == null ? double.infinity : glyph.left - prior.right;
      final height = prior == null || glyph.height > prior.height
          ? glyph.height
          : prior.height;
      if (prior == null || gap > height * _gapHeightFactor) runs.add([]);
      runs.last.add(glyph);
    }
    for (final run in runs) {
      final text = run.map((g) => g.text).join();
      if (!_pageDigits.hasMatch(text)) continue;
      final left = run.first.left;
      final right = run.last.right;
      final bottom = run
          .map((g) => g.top + g.height)
          .reduce((a, b) => a > b ? a : b);
      final number = int.parse(text);
      if (number > 0 &&
          bottom >= _footerBottom &&
          right - left <= _maxNumberWidth &&
          (right <= _cornerWidth || left >= 1 - _cornerWidth)) {
        candidates.add(number);
      }
    }
  }
  return candidates.length == 1 ? candidates.single : null;
}
