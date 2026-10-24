import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
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
      final revision = cache?.revision;
      checkAvailable();
      final page = await document.pages[number - 1].waitForLoaded(
        timeout: const Duration(seconds: 15),
      );
      checkAvailable();
      if (page == null) throw StateError('PDF page loading timed out');
      final raw = await page.loadText();
      checkAvailable();
      await cache?.rememberText(
        number,
        raw?.fullText ?? '',
        generation: revision,
      );
      checkAvailable();
      if (raw == null) return const TextbookTocPage('');
      final glyphs = <TextbookTocGlyph>[];
      for (var i = 0;
          i < raw.fullText.length && i < raw.charRects.length;
          i++) {
        final text = raw.fullText.substring(i, i + 1);
        if (text.trim().isEmpty) continue;
        final rect = raw.charRects[i].toRect(page: page);
        if (rect.isEmpty || !rect.isFinite) continue;
        glyphs.add(
          TextbookTocGlyph(
            text: text,
            left: rect.left / page.width,
            top: rect.top / page.height,
            right: rect.right / page.width,
            height: rect.height / page.height,
          ),
        );
      }
      return TextbookTocPage(raw.fullText, glyphs: glyphs);
    },
  );
}
