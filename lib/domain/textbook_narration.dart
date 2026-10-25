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
final _sentenceEnd = RegExp(r'[。！？!?]');
final _sentenceTail = RegExp(r'[。！？!?”’」』）》】]');
int _spokenLength(String text) =>
    text.replaceAll(RegExp(r'\s'), '').runes.length;

/// 仅取正文，绝不从注音/无障碍标签拼装合成文本。
/// 模型段落可能是 PDF 的分页断点，未完句允许跨同课段落。
List<TextbookNarrationSegment> buildTextbookNarration(
  Iterable<TextbookCourseLesson> lessons, {
  int firstTarget = 50,
  int target = 80,
  int softLimit = 120,
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
    final hasSentences = characters.any((c) => _sentenceEnd.hasMatch(c.text));
    final units = <List<_Character>>[];
    var unit = <_Character>[];
    for (var i = 0; i < characters.length; i++) {
      final c = characters[i];
      unit.add(c);
      if (hasSentences && _sentenceEnd.hasMatch(c.text)) {
        while (i + 1 < characters.length &&
            _sentenceTail.hasMatch(characters[i + 1].text)) {
          unit.add(characters[++i]);
        }
        units.add(unit);
        unit = [];
      } else if (!hasSentences && c.paragraphId == null) {
        units.add(unit);
        unit = [];
      }
    }
    if (unit.isNotEmpty) units.add(unit);
    final groups = <List<_Character>>[];
    var group = <_Character>[];
    var length = 0;
    for (final sentence in units) {
      final count = _spokenLength(sentence.map((c) => c.text).join());
      if (count == 0) continue;
      if (group.isNotEmpty && length + count > softLimit) {
        groups.add(group);
        group = [];
        length = 0;
      }
      group.addAll(sentence);
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
      final text = group.map((c) => c.text).join().trim();
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
