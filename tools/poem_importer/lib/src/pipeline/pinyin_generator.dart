import 'package:lpinyin/lpinyin.dart';

/// Chinese punctuation and formatting characters that should NOT be turned into
/// pinyin syllables. They are kept in-place in the output for readability.
const Set<String> _punctuation = <String>{
  '，', '。', '？', '！', '；', '：', '、',
  '（', '）', '「', '」', '『', '』',
  '“', '”', // “ ”
  '‘', '’', // ‘ ’
  '《', '》', '——', '…', '·',
  ',', '.', '?', '!', ';', ':', '(', ')', '"', '\'',
  '\n', '\r', '\t',
};

/// Multi-character punctuation kept as-is when scanning.
const Set<String> _multiCharPunctuation = <String>{'——', '…'};

/// Word-level pinyin overrides for common polyphonic characters where the
/// context matters. Applied BEFORE the character-level dictionary.
///
/// Each key is a Chinese phrase, value is the space-separated pinyin with tone
/// marks. Downstream we substitute matched phrases prior to running lpinyin.
const Map<String, String> _wordOverrides = <String, String>{
  // "远上寒山石径斜" - 杜牧《山行》"斜" 古音 xiá
  '石径斜': 'shí jìng xiá',
  '径斜': 'jìng xiá',
  // "少小离家老大回，乡音无改鬓毛衰" - 贺知章 "衰" 古音 cuī
  '鬓毛衰': 'bìn máo cuī',
  '毛衰': 'máo cuī',
  // "远看山有色" 无需
  // "路人借问遥招手" 无需
  // "一骑红尘妃子笑" - "骑" 古音 jì
  '一骑红尘': 'yī jì hóng chén',
  // "床前明月光" - 无
  // "白日依山尽" - 无
};

/// Character-level overrides for polyphonic pronunciations that differ from
/// lpinyin's default choice inside a classical-poetry context.
const Map<String, String> _charOverrides = <String, String>{
  // 常见误读：
  '朝': 'zhāo', // 朝辞白帝彩云间
  '还': 'huán', // 千里江陵一日还
  '重': 'chóng', // 两岸猿声啼不住 vs "重" default zhòng
  '磨': 'mó',
};

/// Generates a space-separated pinyin string with tone marks for [text].
///
/// - Chinese characters -> pinyin syllables
/// - Punctuation -> kept as-is with surrounding spaces trimmed
/// - Newlines -> preserved so downstream can align rows
///
/// Word overrides take priority, then character overrides, then lpinyin.
String generatePinyin(String text) {
  // 1) Apply word-level overrides by inserting sentinels.
  // We use a simple substitute-then-scan approach: for each matched phrase we
  // record its start index and pinyin, then when scanning that range we emit
  // the pre-baked pinyin.
  final overrides = <_Range>[];
  for (final entry in _wordOverrides.entries) {
    var idx = 0;
    while (true) {
      final found = text.indexOf(entry.key, idx);
      if (found < 0) break;
      overrides.add(_Range(found, found + entry.key.length, entry.value));
      idx = found + entry.key.length;
    }
  }
  overrides.sort((a, b) => a.start.compareTo(b.start));

  final buffer = StringBuffer();
  var i = 0;
  var overrideIdx = 0;
  while (i < text.length) {
    // Skip overrides whose range has already been passed.
    while (overrideIdx < overrides.length && overrides[overrideIdx].end <= i) {
      overrideIdx++;
    }
    if (overrideIdx < overrides.length && overrides[overrideIdx].start == i) {
      final r = overrides[overrideIdx];
      _appendWithSpace(buffer, r.pinyin);
      i = r.end;
      overrideIdx++;
      continue;
    }

    // Check for multi-char punctuation like ——, …
    var matchedMulti = false;
    for (final punc in _multiCharPunctuation) {
      if (i + punc.length <= text.length &&
          text.substring(i, i + punc.length) == punc) {
        _appendWithSpace(buffer, punc);
        i += punc.length;
        matchedMulti = true;
        break;
      }
    }
    if (matchedMulti) continue;

    final ch = text[i];

    // Newline -> preserve as-is (no surrounding space) so alignment stays.
    if (ch == '\n') {
      // Trim any trailing space before newline.
      final current = buffer.toString();
      if (current.endsWith(' ')) {
        final trimmed = current.substring(0, current.length - 1);
        buffer
          ..clear()
          ..write(trimmed);
      }
      buffer.write('\n');
      i++;
      continue;
    }

    if (_punctuation.contains(ch)) {
      _appendWithSpace(buffer, ch);
      i++;
      continue;
    }

    if (_isChinese(ch)) {
      final override = _charOverrides[ch];
      final syllable = override ??
          PinyinHelper.getPinyinE(ch, defPinyin: ch, format: PinyinFormat.WITH_TONE_MARK);
      _appendWithSpace(buffer, syllable);
      i++;
      continue;
    }

    // ASCII / other -> keep as-is, separated by space if letter/digit.
    if (RegExp(r'\s').hasMatch(ch)) {
      // collapse whitespace into single space
      if (!buffer.toString().endsWith(' ')) buffer.write(' ');
    } else {
      _appendWithSpace(buffer, ch);
    }
    i++;
  }
  return buffer.toString().trim();
}

void _appendWithSpace(StringBuffer buffer, String token) {
  final current = buffer.toString();
  if (current.isNotEmpty && !current.endsWith(' ') && !current.endsWith('\n')) {
    buffer.write(' ');
  }
  buffer.write(token);
}

bool _isChinese(String ch) {
  if (ch.isEmpty) return false;
  final code = ch.codeUnitAt(0);
  // CJK Unified Ideographs U+4E00..U+9FFF
  return code >= 0x4E00 && code <= 0x9FFF;
}

class _Range {
  const _Range(this.start, this.end, this.pinyin);
  final int start;
  final int end;
  final String pinyin;
}
