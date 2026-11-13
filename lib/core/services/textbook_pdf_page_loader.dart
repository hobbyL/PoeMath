import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/data/models/textbook_page_text.dart';

/// 阅读、目录与课程共用可见布局，PDF 库坐标仅在此转换。
Future<TextbookPageText> loadTextbookPdfPage({
  required PdfDocument document,
  required int number,
  required void Function() checkAvailable,
  TextbookContentCache? cache,
}) async {
  RangeError.checkValueInInterval(number, 1, document.pages.length, 'page');
  checkAvailable();
  final revision = cache?.revision;
  Future<TextbookPageText> load() async {
    checkAvailable();
    final page = await document.pages[number - 1].waitForLoaded(
      timeout: const Duration(seconds: 15),
    );
    checkAvailable();
    if (page == null) throw StateError('原书页面读取超时');
    final raw = await page.loadText();
    checkAvailable();
    final text = raw?.fullText ?? '';
    final runes = text.runes.toList();
    final rects = raw?.charRects ?? const <PdfRect>[];
    final codepointIndexed = rects.length == runes.length;
    final utf16Indexed = rects.length == text.length;
    final glyphs = <TextbookPageGlyph>[];
    final visible = [
      for (final rune in runes)
        String.fromCharCode(rune).trim().isEmpty ? rune : 0x20,
    ];
    var utf16 = 0;
    if (codepointIndexed || utf16Indexed) {
      for (var i = 0; i < runes.length; i++) {
        final rune = runes[i];
        final index = codepointIndexed ? i : utf16;
        var rect = rects[index].toRect(page: page);
        if (!codepointIndexed && rune > 0xffff) {
          rect = rect.expandToInclude(rects[index + 1].toRect(page: page));
        }
        utf16 += rune > 0xffff ? 2 : 1;
        // PDFium may expose clipped neighbouring-page text. Preserve rune
        // indices while masking characters outside this physical page.
        if (rect.isFinite &&
            !rect.isEmpty &&
            rect.center.dx >= 0 &&
            rect.center.dx <= page.width &&
            rect.center.dy >= 0 &&
            rect.center.dy <= page.height) {
          visible[i] = rune;
          glyphs.add(
            TextbookPageGlyph(
              text: String.fromCharCode(rune),
              index: i,
              left: rect.left / page.width,
              top: rect.top / page.height,
              right: rect.right / page.width,
              bottom: rect.bottom / page.height,
            ),
          );
        }
      }
    }
    final visibleText = codepointIndexed || utf16Indexed
        ? String.fromCharCodes(visible)
        : text;
    final status = visibleText.trim().isEmpty
        ? 'no_text'
        : visibleText.contains('\uFFFD')
        ? 'replacement_characters'
        : RegExp(r'\(cid:\d+\)').hasMatch(visibleText)
        ? 'cid_placeholders'
        : !codepointIndexed && !utf16Indexed
        ? 'extraction_error'
        : 'text_extracted';
    return TextbookPageText(
      page: number,
      text: visibleText,
      width: page.width,
      height: page.height,
      glyphs: glyphs,
      status: status,
    );
  }

  final result = cache == null
      ? await load()
      : await cache.pageLayout(number, load);
  checkAvailable();
  if (cache?.revision != revision) throw StateError('原书缓存已失效');
  return result;
}

TextbookPageNumberService textbookPdfPageNumberService(
  PdfDocument document, {
  required void Function() checkAvailable,
  TextbookContentCache? cache,
}) => TextbookPageNumberService(
  pageCount: document.pages.length,
  cache: cache,
  checkAvailable: checkAvailable,
  loadPage: (number) => loadTextbookPdfPage(
    document: document,
    number: number,
    cache: cache,
    checkAvailable: checkAvailable,
  ),
);
