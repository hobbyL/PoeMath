import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_layout.dart';

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
}
