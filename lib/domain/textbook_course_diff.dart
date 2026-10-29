import 'package:poemath/domain/textbook_text_display.dart';

/// 一课“当前版本”与“生成版本”的可见差异。
class TextbookCourseDifference {
  const TextbookCourseDifference({
    required this.categories,
    required this.currentParagraphs,
    required this.generatedParagraphs,
    required this.currentAnnotatedParagraphs,
    required this.generatedAnnotatedParagraphs,
  });

  final List<TextbookCategoryDifference> categories;
  final int currentParagraphs;
  final int generatedParagraphs;
  final int currentAnnotatedParagraphs;
  final int generatedAnnotatedParagraphs;

  /// 两个版本的可见文字完全一致，且注音完整度相同。
  bool get isSame => categories.every((c) => c.isSame) && !hasPinyinDifference;

  bool get hasPinyinDifference =>
      currentAnnotatedParagraphs != generatedAnnotatedParagraphs;
}

/// 单个内容类别的差异；[added] 只在生成版本出现，[removed] 只在当前版本出现。
class TextbookCategoryDifference {
  const TextbookCategoryDifference({
    required this.category,
    required this.currentCount,
    required this.generatedCount,
    required this.added,
    required this.removed,
    required this.currentText,
    required this.generatedText,
  });

  final String category;
  final int currentCount;
  final int generatedCount;
  final List<String> added;
  final List<String> removed;

  /// 两侧完整文字，用来定位第一个差异位置。
  final String currentText;
  final String generatedText;

  bool get isSame => added.isEmpty && removed.isEmpty;

  /// 两侧文字的第一个差异片段；文字一致时为 null。
  ({String current, String generated})? get window =>
      textbookDifferenceWindow(currentText, generatedText);
}

/// 两个版本第一个差异位置附近的片段，便于在摘要里直接看出改了哪里。
({String current, String generated})? textbookDifferenceWindow(
  String current,
  String generated, {
  int context = 12,
}) {
  if (current == generated) return null;
  final currentRunes = current.runes.toList();
  final generatedRunes = generated.runes.toList();
  var prefix = 0;
  while (prefix < currentRunes.length &&
      prefix < generatedRunes.length &&
      currentRunes[prefix] == generatedRunes[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < currentRunes.length - prefix &&
      suffix < generatedRunes.length - prefix &&
      currentRunes[currentRunes.length - 1 - suffix] ==
          generatedRunes[generatedRunes.length - 1 - suffix]) {
    suffix++;
  }
  String window(List<int> runes) {
    final start = (prefix - context).clamp(0, runes.length);
    final end = (runes.length - suffix + context).clamp(start, runes.length);
    final text = String.fromCharCodes(runes.sublist(start, end));
    return '${start > 0 ? '…' : ''}$text${end < runes.length ? '…' : ''}';
  }

  return (current: window(currentRunes), generated: window(generatedRunes));
}

/// 课目内容里一条记录可用于展示的文字。
String textbookCourseTargetText(Map<dynamic, dynamic> target) =>
    target['text'] as String? ??
    target['prompt'] as String? ??
    target['instruction'] as String? ??
    '';

/// 把一类课目内容排成可直接显示的连续文字。
///
/// 段落按原书分段，段首缩进两格；非段落的视觉换行全部移除，交给屏幕宽度
/// 决定折行。会认字、会写字按单字排列，词语用顿号分隔。
String textbookCategoryContent(String category, List<Object?> targets) {
  final texts = [
    for (final target in targets)
      category == 'paragraphs'
          ? textbookContinuousText(textbookCourseTargetText(target as Map))
          : _flowText(textbookCourseTargetText(target as Map)),
  ];
  if (category == 'paragraphs') {
    return [for (final text in texts) '　　$text'].join('\n');
  }
  if (category == 'recognitionCharacters' || category == 'writingCharacters') {
    return texts.join(' ');
  }
  if (category == 'words') return texts.join('、');
  return texts.join('\n');
}

/// 移除非段落内容的视觉换行，保留行内原有的空格。
String _flowText(String text) {
  final lines = [
    for (final line in text.split(RegExp(r'\r?\n')))
      line.replaceAll('\t', ' ').trim(),
  ].where((line) => line.isNotEmpty).toList();
  final buffer = StringBuffer();
  int? previous;
  var previousLine = '';
  for (final line in lines) {
    final first = line.runes.first;
    final separated = previous != null &&
        !_endsWithChinesePunctuation(previousLine) &&
        (_isAsciiWord(previous) ||
            _isAsciiWord(first) ||
            !_startsWithChinesePunctuation(line));
    if (separated) buffer.write(' ');
    buffer.write(line);
    previous = line.runes.last;
    previousLine = line;
  }
  return buffer.toString();
}

bool _endsWithChinesePunctuation(String line) =>
    RegExp(r'[，。！？；：、…）】》」』”’]$').hasMatch(line);

bool _startsWithChinesePunctuation(String line) =>
    RegExp(r'^[，。！？；：、…）】》」』”’]').hasMatch(line);

bool _isAsciiWord(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5a) ||
    (rune >= 0x61 && rune <= 0x7a);

/// 比较一课的两个版本，找出每个类别的增删和注音完整度。
TextbookCourseDifference textbookCourseDiff({
  required Map<String, dynamic> current,
  required Map<String, dynamic> generated,
  required Iterable<String> categories,
}) {
  final differences = <TextbookCategoryDifference>[];
  for (final category in categories) {
    final currentItems = _items(current, category);
    final generatedItems = _items(generated, category);
    final generatedBudget = <String, int>{};
    for (final item in generatedItems) {
      generatedBudget[item.signature] =
          (generatedBudget[item.signature] ?? 0) + 1;
    }
    final removed = <String>[];
    for (final item in currentItems) {
      final remaining = generatedBudget[item.signature] ?? 0;
      if (remaining > 0) {
        generatedBudget[item.signature] = remaining - 1;
      } else {
        removed.add(item.text);
      }
    }
    final currentBudget = <String, int>{};
    for (final item in currentItems) {
      currentBudget[item.signature] = (currentBudget[item.signature] ?? 0) + 1;
    }
    final added = <String>[];
    for (final item in generatedItems) {
      final remaining = currentBudget[item.signature] ?? 0;
      if (remaining > 0) {
        currentBudget[item.signature] = remaining - 1;
      } else {
        added.add(item.text);
      }
    }
    differences.add(
      TextbookCategoryDifference(
        category: category,
        currentCount: currentItems.length,
        generatedCount: generatedItems.length,
        added: added,
        removed: removed,
        currentText: [for (final item in currentItems) item.text].join('\n'),
        generatedText:
            [for (final item in generatedItems) item.text].join('\n'),
      ),
    );
  }
  final currentParagraphs = _items(current, 'paragraphs');
  final generatedParagraphs = _items(generated, 'paragraphs');
  return TextbookCourseDifference(
    categories: differences,
    currentParagraphs: currentParagraphs.length,
    generatedParagraphs: generatedParagraphs.length,
    currentAnnotatedParagraphs: _annotated(current),
    generatedAnnotatedParagraphs: _annotated(generated),
  );
}

typedef _Item = ({String text, String signature});

List<_Item> _items(Map<String, dynamic> lesson, String category) {
  final raw = lesson[category];
  if (raw is! List) return const [];
  return [
    for (final target in raw)
      if (target is Map)
        (
          text: category == 'paragraphs'
              ? textbookContinuousText(textbookCourseTargetText(target))
              : _flowText(textbookCourseTargetText(target)),
          signature: category == 'paragraphs'
              ? _signature(target)
              : _flowText(textbookCourseTargetText(target)),
        ),
  ];
}

String _signature(Map<dynamic, dynamic> target) => textbookContinuousText(
      textbookCourseTargetText(target),
    );

int _annotated(Map<String, dynamic> lesson) {
  final paragraphs = lesson['paragraphs'];
  if (paragraphs is! List) return 0;
  return paragraphs
      .where(
        (p) =>
            p is Map && p['pinyin'] is List && (p['pinyin'] as List).isNotEmpty,
      )
      .length;
}
