import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_layout.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

class _Page extends Fake implements PdfPage {
  _Page(this.width, this.height);

  @override
  final double width;
  @override
  final double height;
}

void main() {
  test('窄屏单页，600dp起对开；封面独立，最后一页不越界', () {
    final narrow = TextbookPageLayout.forWidth(599);
    expect(narrow.pages(narrow.spreadIndex(3), 5), [3]);
    expect(narrow.previous(3, 5), 2);
    expect(narrow.next(3, 5), 4);
    final wide = TextbookPageLayout.forWidth(600);
    expect(wide.pages(0, 6), [1]);
    expect(wide.pages(1, 6), [2, 3]);
    expect(wide.pages(2, 6), [4, 5]);
    expect(wide.pages(3, 6), [6]);
    expect(wide.spreadCount(6), 4);
    expect(wide.spreadCount(5), 3);
    expect(wide.next(1, 6), 2);
    expect(wide.next(2, 6), 4);
    expect(wide.next(3, 6), 4);
    expect(wide.previous(2, 6), 1);
    expect(wide.previous(5, 6), 2);
    expect(wide.next(6, 6), isNull);
    expect(wide.previous(1, 6), isNull);
    expect(wide.spreadIndex(3), wide.spreadIndex(2));
  });

  test('横向单页保留原尺寸，小尺寸页面居中且不与邻页重叠', () {
    final layout = textbookHorizontalPages([
      _Page(300, 400),
      _Page(200, 300),
      _Page(300, 400),
    ], const PdfViewerParams());
    expect(layout.pageLayouts, [
      const Rect.fromLTWH(8, 8, 300, 400),
      const Rect.fromLTWH(366, 58, 200, 300),
      const Rect.fromLTWH(624, 8, 300, 400),
    ]);
    expect(layout.documentSize, const Size(932, 416));
  });

  test('横向对开封面独立居中，偶数左页奇数右页，末页保留空白右侧', () {
    final layout = textbookHorizontalPages(
      [
        _Page(300, 400),
        _Page(200, 300),
        _Page(300, 400),
        _Page(300, 350),
        _Page(200, 400),
        _Page(200, 300),
      ],
      const PdfViewerParams(),
      doublePage: true,
    );
    expect(layout.pageLayouts, [
      const Rect.fromLTWH(162, 8, 300, 400),
      const Rect.fromLTWH(724, 58, 200, 300),
      const Rect.fromLTWH(932, 8, 300, 400),
      const Rect.fromLTWH(1240, 33, 300, 350),
      const Rect.fromLTWH(1548, 8, 200, 400),
      const Rect.fromLTWH(1956, 58, 200, 300),
    ]);
    expect(layout.documentSize, const Size(2472, 416));
  });
}
