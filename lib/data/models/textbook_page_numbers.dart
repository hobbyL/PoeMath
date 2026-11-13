/// 页码只改变书页展示；所有键和导航目标仍是 1 起始的物理 PDF 页序。
class TextbookPageNumbers {
  TextbookPageNumbers({
    required this.pageCount,
    Map<int, int?> pages = const {},
  }) : pages = Map.unmodifiable(pages) {
    if (pageCount < 1 ||
        pages.entries.any(
          (entry) =>
              entry.key < 1 ||
              entry.key > pageCount ||
              (entry.value != null && entry.value! < 1),
        )) {
      throw const FormatException('书页映射无效');
    }
  }

  final int pageCount;

  /// 缺少键表示未读取，null 表示已读取但没有可靠的印刷页码。
  final Map<int, int?> pages;

  bool get complete => pages.length == pageCount;

  List<int> targets(int printedPage) => [
    for (var page = 1; page <= pageCount; page++)
      if (pages[page] == printedPage) page,
  ];

  TextbookPageNumbers withPage(int pdfPage, int? printedPage) =>
      TextbookPageNumbers(
        pageCount: pageCount,
        pages: {...pages, pdfPage: printedPage},
      );

  String label(int pdfPage) => pages.containsKey(pdfPage)
      ? textbookPrintedPageLabel(pages[pdfPage])
      : '正在读取页码';

  String labelForPages(Iterable<int> pdfPages) {
    final visible = pdfPages.toList();
    if (visible.length == 2 &&
        pages[visible.first] != null &&
        pages[visible.last] == pages[visible.first]! + 1) {
      return '第 ${pages[visible.first]}–${pages[visible.last]} 页';
    }
    return visible.map(label).join(' · ');
  }
}

String textbookPrintedPageLabel(int? page) =>
    page == null ? '未标页码' : '第 $page 页';

class TextbookPageNumberProgress {
  const TextbookPageNumberProgress({
    required this.scanned,
    required this.total,
    required this.numbers,
  });

  final int scanned;
  final int total;
  final TextbookPageNumbers numbers;
}
