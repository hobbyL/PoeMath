import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/data/models/textbook_toc.dart';

/// 复用阅读器已打开的文档；库坐标在此转换，识别服务不持有 PDF。
TextbookTocService textbookPdfTocService(
  PdfDocument document, {
  required bool Function() isAvailable,
  TextbookContentCache? cache,
}) {
  void checkAvailable() {
    if (!isAvailable()) {
      throw StateError('PDF is no longer available');
    }
  }

  return TextbookTocService(
    pageCount: document.pages.length,
    cache: cache,
    loadOutline: () async {
      checkAvailable();
      final nodes = await document.loadOutline();
      checkAvailable();
      final entries = <TextbookTocEntry>[];
      void visit(List<PdfOutlineNode> nodes, int level) {
        for (final node in nodes) {
          entries.add(
            TextbookTocEntry(
              title: node.title,
              page: node.dest?.pageNumber,
              level: level,
            ),
          );
          visit(node.children, level + 1);
        }
      }

      visit(nodes, 0);
      return entries;
    },
    loadPage: (number) async {
      final page = await loadTextbookPdfPage(
        document: document,
        number: number,
        cache: cache,
        checkAvailable: checkAvailable,
      );
      return TextbookTocPage.fromPageText(page);
    },
  );
}
