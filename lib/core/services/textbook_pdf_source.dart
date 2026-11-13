import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';

class TextbookDraftCancelled implements Exception {
  const TextbookDraftCancelled();
}

class TextbookDraftToken {
  TextbookDraftToken({this._authorize});
  final void Function()? _authorize;
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const TextbookDraftCancelled();
    _authorize?.call();
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
    final document = await PdfDocument.openFile(
      path,
      useProgressiveLoading: true,
    );
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
  Future<TextbookPageText> page(int number) => loadTextbookPdfPage(
    document: _document,
    number: number,
    cache: _cache,
    checkAvailable: check,
  );

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
      return TextbookTocPage.fromPageText(data);
    },
  ).scan(refresh: refresh);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _document.dispose();
  }
}
