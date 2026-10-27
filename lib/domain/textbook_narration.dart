import 'package:poemath/data/models/textbook_course.dart';

/// 原始正文的 Unicode 码点区间；与背诵范围采用同一种坐标。
class TextbookNarrationSpan {
  const TextbookNarrationSpan(this.paragraphId, this.start, this.end);
  final String paragraphId;
  final int start;
  final int end;
  bool contains(int index) => start <= index && index < end;
}

class TextbookNarrationSegment {
  const TextbookNarrationSegment({
    required this.lessonId,
    required this.text,
    required this.spans,
  });
  final String lessonId;
  final String text;
  final List<TextbookNarrationSpan> spans;
}

typedef _Character = ({String text, String? paragraphId, int index});
final _sentenceEnd = RegExp(r'[。！？!?…]');
final _clauseEnd = RegExp(r'[。！？!?…，,、；;：:]');
final _closingTail = RegExp(r'[”’」』）》】]');
int _spokenLength(String text) =>
    text.replaceAll(RegExp(r'\s'), '').runes.length;

bool _isAsciiWord(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A);

bool _isSpace(int rune) => String.fromCharCode(rune).trim().isEmpty;

/// 合成文本不保留换行与中文间空格：系统 TTS 会把这些空白读成额外停顿，
/// 听起来像句子中途卡住。仅保留西文单词之间的必要空格。
String _speechText(List<_Character> characters) {
  final runes = <int>[];
  var pendingSpace = false;
  for (final character in characters) {
    for (final rune in character.text.runes) {
      if (_isSpace(rune)) {
        pendingSpace = true;
        continue;
      }
      if (pendingSpace &&
          runes.isNotEmpty &&
          (_isAsciiWord(runes.last) || _isAsciiWord(rune))) {
        runes.add(0x20);
      }
      pendingSpace = false;
      runes.add(rune);
    }
  }
  return String.fromCharCodes(runes).trim();
}

/// 以标点切分：默认句号、问号、感叹号、逗号、顿号、分号、冒号、省略号
/// 都是停顿点；[sentenceOnly] 只保留完整句末标点，供需要整句展示的场景。
List<List<_Character>> _splitUnits(
  List<_Character> characters, {
  required bool sentenceOnly,
}) {
  final pattern = sentenceOnly ? _sentenceEnd : _clauseEnd;
  final units = <List<_Character>>[];
  var unit = <_Character>[];
  for (var i = 0; i < characters.length; i++) {
    final character = characters[i];
    unit.add(character);
    if (!pattern.hasMatch(character.text)) continue;
    while (i + 1 < characters.length) {
      final next = characters[i + 1].text;
      final repeated = (character.text == '…' || character.text == '—') &&
          next == character.text;
      if (!repeated && !_closingTail.hasMatch(next)) break;
      unit.add(characters[++i]);
    }
    units.add(unit);
    unit = [];
  }
  if (unit.isNotEmpty) units.add(unit);
  return units;
}

/// 仅取正文，绝不从注音/无障碍标签拼装合成文本。
/// 模型段落可能是 PDF 的分页断点，换行本身不产生分段。
///
/// 默认在每个标点后允许分段，因此音频边界始终落在标点处；长句可以在
/// 逗号处拆成多个片段。需要整句展示的场景（如认一认的「课文词句」）
/// 传 [sentenceOnly] 只在句末标点分段。
List<TextbookNarrationSegment> buildTextbookNarration(
  Iterable<TextbookCourseLesson> lessons, {
  int firstTarget = 50,
  int target = 80,
  int softLimit = 120,
  bool sentenceOnly = false,
}) {
  final result = <TextbookNarrationSegment>[];
  for (final lesson in lessons) {
    final characters = <_Character>[];
    for (final paragraph in lesson.paragraphs) {
      final runes = paragraph.text.runes.toList();
      var start = 0;
      var end = runes.length;
      while (start < end && String.fromCharCode(runes[start]).trim().isEmpty) {
        start++;
      }
      while (
          end > start && String.fromCharCode(runes[end - 1]).trim().isEmpty) {
        end--;
      }
      if (start == end) continue;
      if (characters.isNotEmpty) {
        // 段落断点只作源码范围标记，合成时不会读成停顿。
        characters.add((text: '\n', paragraphId: null, index: -1));
      }
      for (var index = start; index < end; index++) {
        characters.add(
          (
            text: String.fromCharCode(runes[index]),
            paragraphId: paragraph.id,
            index: index,
          ),
        );
      }
    }
    final units = _splitUnits(characters, sentenceOnly: sentenceOnly);
    final groups = <List<_Character>>[];
    var group = <_Character>[];
    var length = 0;
    for (final unit in units) {
      final count = _spokenLength(unit.map((c) => c.text).join());
      if (count == 0) continue;
      if (group.isNotEmpty && length + count > softLimit) {
        groups.add(group);
        group = [];
        length = 0;
      }
      group.addAll(unit);
      length += count;
      if (length >= (groups.isEmpty ? firstTarget : target)) {
        groups.add(group);
        group = [];
        length = 0;
      }
    }
    if (group.isNotEmpty) {
      if (groups.isNotEmpty &&
          length < firstTarget &&
          _spokenLength(groups.last.map((c) => c.text).join()) + length <=
              softLimit) {
        groups.last.addAll(group);
      } else {
        groups.add(group);
      }
    }
    for (final group in groups) {
      final spans = <TextbookNarrationSpan>[];
      for (final c in group) {
        final id = c.paragraphId;
        if (id == null) continue;
        if (spans.isNotEmpty &&
            spans.last.paragraphId == id &&
            spans.last.end == c.index) {
          final prior = spans.removeLast();
          spans.add(TextbookNarrationSpan(id, prior.start, c.index + 1));
        } else {
          spans.add(TextbookNarrationSpan(id, c.index, c.index + 1));
        }
      }
      final text = _speechText(group);
      if (text.isNotEmpty) {
        result.add(
          TextbookNarrationSegment(
            lessonId: lesson.id,
            text: text,
            spans: List.unmodifiable(spans),
          ),
        );
      }
    }
  }
  return List.unmodifiable(result);
}
