import 'dart:math' as math;

typedef TextbookSearch = Stream<TextbookSearchPage> Function(String query);

/// 每扫描一页发出一次进度；命中页只保留短摘要，不保存整书文字。
class TextbookSearchPage {
  const TextbookSearchPage({
    required this.page,
    required this.hasText,
    this.matchCount = 0,
    this.snippet = '',
  });

  final int page;
  final bool hasText;
  final int matchCount;
  final String snippet;
}

final _spaces = RegExp(r'[\s\u200B\uFEFF]+');
final _chineseQuery = RegExp(r'^[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]+$');
final _pinyinLetters =
    RegExp(r'[A-Za-z\u00C0-\u024F\u0300-\u036F\u1E00-\u1EFF]+');

Stream<TextbookSearchPage> searchTextbookPages({
  required String query,
  required int pageCount,
  required Future<String> Function(int page) loadPageText,
}) async* {
  final needle = query.replaceAll(_spaces, '').toLowerCase();
  if (needle.isEmpty) return;
  final chinese = _chineseQuery.hasMatch(needle);
  for (var page = 1; page <= pageCount; page++) {
    final raw = await loadPageText(page);
    var text = raw.replaceAll(_spaces, '');
    final hasText = text.isNotEmpty;
    // 注音教材的拼音可能插在汉字之间；标点和数字仍是匹配边界。
    if (chinese) text = text.replaceAll(_pinyinLetters, '');
    final matches = needle.allMatches(text.toLowerCase());
    final first = matches.firstOrNull;
    var snippet = '';
    if (first != null) {
      final start = math.max(0, first.start - 20);
      final end = math.min(text.length, first.end + 40);
      snippet = '${start > 0 ? '…' : ''}${text.substring(start, end)}'
          '${end < text.length ? '…' : ''}';
    }
    yield TextbookSearchPage(
      page: page,
      hasText: hasText,
      matchCount: matches.length,
      snippet: snippet,
    );
  }
}
