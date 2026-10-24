import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';

class TextbookDraftCancelled implements Exception {
  const TextbookDraftCancelled();
}

class TextbookDraftToken {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const TextbookDraftCancelled();
  }
}

abstract class TextbookPdfSource {
  Future<TextbookPageText> page(int number);
  Stream<TextbookTocProgress> toc({bool refresh = false});
  void check();
  Future<void> close();
}

/// 独立文档不依赖阅读器路由；只提取文字，不渲染全书位图。
class NativeTextbookPdfSource implements TextbookPdfSource {
  NativeTextbookPdfSource._(
    this._document,
    this._cache,
    this._token,
    this._revision,
  );
  final PdfDocument _document;
  final TextbookContentCache _cache;
  final TextbookDraftToken _token;
  final int _revision;
  bool _closed = false;

  static Future<NativeTextbookPdfSource> open({
    required String path,
    required Textbook book,
    required TextbookContentCache cache,
    required TextbookDraftToken token,
  }) async {
    final revision = cache.revision;
    token.check();
    await pdfrxFlutterInitialize();
    token.check();
    final document =
        await PdfDocument.openFile(path, useProgressiveLoading: true);
    try {
      await document.loadPagesProgressively(
        onPageLoadProgress: (loaded, total, last) => !token.cancelled,
      );
      token.check();
      if (cache.revision != revision) throw const TextbookDraftCancelled();
      if (document.pages.length != book.pageCount) {
        throw const FormatException('原书页数与登记信息不符');
      }
      return NativeTextbookPdfSource._(document, cache, token, revision);
    } on Object {
      await document.dispose();
      rethrow;
    }
  }

  @override
  void check() {
    _token.check();
    if (_closed || _cache.revision != _revision) {
      throw const TextbookDraftCancelled();
    }
  }

  @override
  Future<TextbookPageText> page(int number) async {
    check();
    final result = await _cache.pageLayout(number, () async {
      check();
      final page = await _document.pages[number - 1]
          .waitForLoaded(timeout: const Duration(seconds: 15));
      check();
      if (page == null) throw StateError('原书页面读取超时');
      final raw = await page.loadText();
      check();
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
          // Some textbook PDFs retain text from a clipped neighbouring page.
          // PDFium exposes those characters too; they are not evidence on this page.
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
    });
    check();
    return result;
  }

  @override
  Stream<TextbookTocProgress> toc({bool refresh = false}) => TextbookTocService(
        pageCount: _document.pages.length,
        cache: _cache,
        loadOutline: () async {
          check();
          final raw = await _document.loadOutline();
          check();
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

          visit(raw, 0);
          return entries;
        },
        loadPage: (number) async {
          final data = await page(number);
          return TextbookTocPage(
            data.text,
            glyphs: [
              for (final g in data.glyphs)
                if (g.text.trim().isNotEmpty)
                  TextbookTocGlyph(
                    text: g.text,
                    left: g.left,
                    top: g.top,
                    right: g.right,
                    height: g.height,
                  ),
            ],
          );
        },
      ).scan(refresh: refresh);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _document.dispose();
  }
}
