enum TextbookReadingBreak { line, stanza }

/// 仅用于排版的原文 rune 边界，不改写课文、注音或背诵索引。
class TextbookReadingLayout {
  const TextbookReadingLayout({
    this.breaks = const {},
    this.retainLeadingIndent = true,
  });

  final Map<int, TextbookReadingBreak> breaks;
  final bool retainLeadingIndent;
}

TextbookReadingLayout textbookReadingLayoutForText(
  String text, {
  bool preserveLines = false,
}) {
  final breaks = <int, TextbookReadingBreak>{};
  final runes = text.runes.toList();
  var lineBreaks = 0;
  var hasText = false;
  for (final (index, rune) in runes.indexed) {
    if (rune == 0x0a ||
        rune == 0x0d &&
            (index + 1 == runes.length || runes[index + 1] != 0x0a)) {
      lineBreaks++;
    }
    if (String.fromCharCode(rune).trim().isEmpty) continue;
    if (hasText && lineBreaks > 0) {
      if (lineBreaks > 1) {
        breaks[index] = TextbookReadingBreak.stanza;
      } else if (preserveLines) {
        breaks[index] = TextbookReadingBreak.line;
      }
    }
    hasText = true;
    lineBreaks = 0;
  }
  return TextbookReadingLayout(breaks: Map.unmodifiable(breaks));
}

/// 把 PDF 文本层里的视觉换行和排版空格折叠成连续文本。
///
/// 教材 PDF 会把每个视觉行写成换行，直接展示时会出现“黑\n灰色”
/// “游来\n游去”；审核摘要把换行替换成空格后又会变成“黑 灰色”。
/// 这里按字符类型折叠空白：
/// - 汉字、中文标点之间不保留空白；
/// - ASCII 单词/数字之间保留一个空格；
/// - 汉字与 ASCII 单词之间保留一个空格（中英混排）。
String textbookContinuousText(String text) {
  final output = StringBuffer();
  var pendingWhitespace = false;
  int? previous;
  for (final rune in text.runes) {
    if (_isWhitespace(rune)) {
      pendingWhitespace = true;
      continue;
    }
    if (pendingWhitespace && previous != null && _keepsSpace(previous, rune)) {
      output.write(' ');
    }
    pendingWhitespace = false;
    output.writeCharCode(rune);
    previous = rune;
  }
  return output.toString();
}

bool _isWhitespace(int rune) =>
    rune == 0x20 ||
    rune == 0x09 ||
    rune == 0x0a ||
    rune == 0x0d ||
    rune == 0x00a0 ||
    rune == 0x3000;

bool _keepsSpace(int left, int right) {
  if (!_isWordLike(left) || !_isWordLike(right)) return false;
  return _isAsciiWord(left) || _isAsciiWord(right);
}

bool _isAsciiWord(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5a) ||
    (rune >= 0x61 && rune <= 0x7a);

bool _isWordLike(int rune) => _isAsciiWord(rune) || _isHan(rune);

bool _isHan(int rune) =>
    rune == 0x3007 ||
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0xf900 && rune <= 0xfaff) ||
    (rune >= 0x20000 && rune <= 0x323af);
