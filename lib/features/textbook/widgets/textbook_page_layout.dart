import 'package:poemath/core/utils/responsive_layout.dart';

/// PDF 页码与展开页的换算。封面独立，内页按 2–3、4–5 配对。
class TextbookPageLayout {
  const TextbookPageLayout({this.doublePage = false});

  factory TextbookPageLayout.forWidth(double width) => TextbookPageLayout(
        doublePage: width >= ResponsiveLayout.mediumBreakpoint,
      );

  final bool doublePage;

  double get aspectRatio => doublePage ? 3 / 2 : 3 / 4;

  int spreadIndex(int page) => doublePage ? page ~/ 2 : page - 1;

  int spreadCount(int pageCount) => doublePage ? pageCount ~/ 2 + 1 : pageCount;

  int firstPage(int index) => doublePage && index > 0 ? index * 2 : index + 1;

  List<int> pages(int index, int pageCount) {
    final first = firstPage(index);
    return [
      first,
      if (doublePage && first > 1 && first < pageCount) first + 1,
    ];
  }

  int? previous(int page, int pageCount) {
    final index = spreadIndex(page.clamp(1, pageCount));
    return index > 0 ? firstPage(index - 1) : null;
  }

  int? next(int page, int pageCount) {
    final index = spreadIndex(page.clamp(1, pageCount));
    return index + 1 < spreadCount(pageCount) ? firstPage(index + 1) : null;
  }
}
