/// 教材 PDF 拼音字体的字形解码。
///
/// 部分人教教材 PDF 的拼音字体把带调元音映射成键盘位置上的 ASCII 大写
/// 字母，文本层因此输出 `chI`、`tWng`、`lJ` 这类“乱码”。实际字形与
/// 字母含义无关，例如 `chI` 在原书显示为 `chí`。
///
/// 映射由字体字形逐个渲染核对得到；该字体没有 B/N/X/Z 以及 ǖ/ǘ 的字形，
/// 遇到这些字母说明不是可安全还原的注音。
const Map<String, String> _toneGlyphs = {
  'Q': 'ā',
  'W': 'á',
  'A': 'ǎ',
  'S': 'à',
  'E': 'ē',
  'R': 'é',
  'D': 'ě',
  'F': 'è',
  'T': 'ō',
  'Y': 'ó',
  'G': 'ǒ',
  'H': 'ò',
  'U': 'ī',
  'I': 'í',
  'J': 'ǐ',
  'K': 'ì',
  'O': 'ū',
  'P': 'ú',
  'L': 'ǔ',
  'M': 'ù',
  'C': 'ǜ',
  'V': 'ǚ',
};

final RegExp _textbookPinyinPattern = RegExp(
  r'^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜêńňǹḿ]+[1-5]?$',
);

/// 是否为课程模型接受的完整注音（带调或数字声调，不含大写编码）。
bool isTextbookPinyin(String text) => _textbookPinyinPattern.hasMatch(text);

/// 把拼音字体的 ASCII 大写编码还原为带调拼音。
///
/// 返回 `null` 表示文本含有该字体未定义的声调字母，不能安全还原；
/// 调用方应把该字形当作“字体编码待核对”，不要显示成拼音。
String? decodeTextbookPinyinFont(String raw) {
  final decoded = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0x41 && rune <= 0x5a) {
      final tone = _toneGlyphs[String.fromCharCode(rune)];
      if (tone == null) return null;
      decoded.write(tone);
    } else {
      decoded.writeCharCode(rune);
    }
  }
  return decoded.toString();
}
