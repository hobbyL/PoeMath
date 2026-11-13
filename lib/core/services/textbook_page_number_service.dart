import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/data/models/textbook_page_numbers.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_printed_page.dart';

/// 本机按需页码提取；加载器可复用当前阅读器，服务不依赖 PDF 库。
class TextbookPageNumberService {
  TextbookPageNumberService({
    required this.pageCount,
    required this.loadPage,
    this.cache,
    this.checkAvailable,
  }) : _numbers = TextbookPageNumbers(pageCount: pageCount) {
    if (cache != null && cache!.book.pageCount != pageCount) {
      throw const FormatException('书页索引与 PDF 页数不符');
    }
  }

  final int pageCount;
  final Future<TextbookPageText> Function(int page) loadPage;
  final TextbookContentCache? cache;
  final void Function()? checkAvailable;
  TextbookPageNumbers _numbers;
  final _pending = <int, Future<int?>>{};

  TextbookPageNumbers get numbers => cache?.pageNumbers ?? _numbers;

  Future<int?> page(int number) {
    RangeError.checkValueInInterval(number, 1, pageCount, 'page');
    checkAvailable?.call();
    final cached = cache;
    if (cached != null) {
      return cached
          .pageNumber(number, () async {
            checkAvailable?.call();
            final text = await loadPage(number);
            checkAvailable?.call();
            _checkPage(text, number);
            return printedTextbookPage(text);
          })
          .then((printed) {
            checkAvailable?.call();
            return printed;
          });
    }
    if (_numbers.pages.containsKey(number)) {
      return Future.value(_numbers.pages[number]);
    }
    final pending = _pending[number];
    if (pending != null) return pending;
    late final Future<int?> result;
    result = (() async {
      try {
        final text = await Future<TextbookPageText>.sync(
          () => loadPage(number),
        );
        checkAvailable?.call();
        _checkPage(text, number);
        final printed = printedTextbookPage(text);
        _numbers = _numbers.withPage(number, printed);
        return printed;
      } finally {
        if (identical(_pending[number], result)) _pending.remove(number);
      }
    })();
    _pending[number] = result;
    return result;
  }

  Future<TextbookPageNumbers> load(Iterable<int> pages) async {
    final revision = cache?.revision;
    await Future.wait(pages.map(page));
    _check(revision);
    return numbers;
  }

  /// 只有完整扫描后，调用方才可把一个候选视为唯一书页。
  Stream<TextbookPageNumberProgress> scan() async* {
    final revision = cache?.revision;
    for (var number = 1; number <= pageCount; number++) {
      _check(revision);
      await page(number);
      _check(revision);
      yield TextbookPageNumberProgress(
        scanned: number,
        total: pageCount,
        numbers: numbers,
      );
    }
  }

  void _check(int? revision) {
    checkAvailable?.call();
    if (cache?.revision != revision) throw StateError('页码缓存已失效，请重试');
  }

  void _checkPage(TextbookPageText page, int number) {
    if (page.page != number) throw const FormatException('原书页码不一致');
  }
}
