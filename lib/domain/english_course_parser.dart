import 'dart:math' as math;

import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';

final _han = RegExp(r'[\u3400-\u9fff]');
final _unit = RegExp(r'^Unit\s+(\d+)\s+(.+)$', caseSensitive: false);
final _heading = RegExp(
  r'^(Lesson\s+\d+|Story\s+Time|Review\s*&\s*Rewards|Revision\s+\d+|Starter)$',
  caseSensitive: false,
);
final _instruction = RegExp(
  r"^(?:[A-D]\s+)?(?:Look,|Listen|Let[’']s|Role-play|Show and|Choose,|Choose and|Make and|Do and|Act and|Read and|Write|Match|Sing|Chant|Point|Circle|Tick)",
  caseSensitive: false,
);

/// 一条可见行；将同一基线的大间隙分为独立栏／气泡，保留词间空格。
class EnglishTextLine {
  const EnglishTextLine(this.text, this.source);
  final String text;
  final EnglishSource source;
}

List<EnglishTextLine> englishPageLines(TextbookPageText page) {
  if (page.glyphs.isEmpty) {
    return page.text
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => EnglishTextLine(s, EnglishSource(page.page)))
        .toList();
  }
  final sorted =
      page.glyphs
          .where((g) => g.text.trim().isNotEmpty && g.height > 0)
          .toList()
        ..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<TextbookPageGlyph>>[];
  for (final g in sorted) {
    final row = rows
        .where(
          (r) => r.any(
            (other) =>
                math.min(other.bottom, g.bottom) - math.max(other.top, g.top) >
                math.min(other.height, g.height) * .45,
          ),
        )
        .lastOrNull;
    (row ?? (rows..add([])).last).add(g);
  }
  final result = <EnglishTextLine>[];
  for (final row in rows) {
    row.sort((a, b) => a.left.compareTo(b.left));
    var group = <TextbookPageGlyph>[];
    void finish() {
      if (group.isEmpty) return;
      final buffer = StringBuffer();
      TextbookPageGlyph? previous;
      for (final g in group) {
        final p = previous;
        if (p != null) {
          final gap = g.left - p.right;
          // Explicit source whitespace is more reliable than kerning.
          final between = page.text.runes
              .skip(p.index + 1)
              .take(math.max(0, g.index - p.index - 1));
          if (g.index > p.index &&
                  between.any((r) => String.fromCharCode(r).trim().isEmpty) ||
              g.index <= p.index && gap > math.max(p.width, g.width) * .6) {
            buffer.write(' ');
          }
        }
        buffer.write(g.text);
        previous = g;
      }
      final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) {
        result.add(
          EnglishTextLine(
            text,
            EnglishSource(
              page.page,
              left: group.map((g) => g.left).reduce(math.min).clamp(0, .999),
              top: group.map((g) => g.top).reduce(math.min).clamp(0, .999),
              right: group.map((g) => g.right).reduce(math.max).clamp(.001, 1),
              bottom: group
                  .map((g) => g.bottom)
                  .reduce(math.max)
                  .clamp(.001, 1),
            ),
          ),
        );
      }
      group = [];
    }

    for (final g in row) {
      if (group.isNotEmpty &&
          g.left - group.last.right > math.max(.025, g.height * 1.8)) {
        finish();
      }
      group.add(g);
    }
    finish();
  }
  result.sort((a, b) {
    final y = a.source.top.compareTo(b.source.top);
    return y == 0 ? a.source.left.compareTo(b.source.left) : y;
  });
  return result;
}

/// Numbered picture panels (1–4) provide a stronger reading order than their
/// vertical position. The number badges sit near each panel's upper-right;
/// assign a sentence to the nearest badge after confirming a 2×2 label layout.
int? englishNumberedCardForSource(
  EnglishSource source,
  List<EnglishTextLine> lines,
) {
  final labels = <int, EnglishSource>{};
  for (final line in lines) {
    final number = int.tryParse(line.text.trim());
    if (number == null || number < 1 || number > 4 || line.source.top > .9) {
      continue;
    }
    if (labels.containsKey(number)) return null;
    labels[number] = line.source;
  }
  if (labels.length != 4) return null;
  final labelCenters = labels.values
      .map(
        (label) =>
            ((label.left + label.right) / 2, (label.top + label.bottom) / 2),
      )
      .toList();
  final xSpread =
      labelCenters.map((center) => center.$1).reduce(math.max) -
      labelCenters.map((center) => center.$1).reduce(math.min);
  final ySpread =
      labelCenters.map((center) => center.$2).reduce(math.max) -
      labelCenters.map((center) => center.$2).reduce(math.min);
  if (xSpread < .18 || ySpread < .12) return null;

  final centerX = (source.left + source.right) / 2;
  final centerY = (source.top + source.bottom) / 2;
  var nearestNumber = 0, nearestDistance = double.infinity;
  for (final entry in labels.entries) {
    final labelX = (entry.value.left + entry.value.right) / 2;
    final labelY = (entry.value.top + entry.value.bottom) / 2;
    final dx = centerX - labelX, dy = centerY - labelY;
    final distance = dx * dx + dy * dy;
    if (distance < nearestDistance) {
      nearestNumber = entry.key;
      nearestDistance = distance;
    }
  }
  return nearestNumber;
}

/// Order source items top-to-bottom by visual rows, then left-to-right inside
/// each row. This keeps small baseline differences from splitting one row.
List<EnglishTarget> englishTargetsInSourceRowOrder(
  List<EnglishTarget> targets,
  Map<String, EnglishSource> sourceByTarget, {
  Map<String, int> originalOrder = const {},
}) {
  final ordered = [...targets]
    ..sort((a, b) {
      final first = sourceByTarget[a.id]!, second = sourceByTarget[b.id]!;
      final vertical = first.top.compareTo(second.top);
      if (vertical != 0) return vertical;
      final horizontal = first.left.compareTo(second.left);
      if (horizontal != 0) return horizontal;
      return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
    });
  final rows = <List<EnglishTarget>>[];
  for (final target in ordered) {
    final source = sourceByTarget[target.id]!;
    final row = rows
        .where(
          (values) => values.any((value) {
            final other = sourceByTarget[value.id]!;
            final overlap =
                math.min(source.bottom, other.bottom) -
                math.max(source.top, other.top);
            final smallerHeight = math.min(
              source.bottom - source.top,
              other.bottom - other.top,
            );
            return overlap > smallerHeight * .35;
          }),
        )
        .firstOrNull;
    (row ?? (rows..add([])).last).add(target);
  }
  rows.sort((a, b) {
    final firstTop = a
        .map((target) => sourceByTarget[target.id]!.top)
        .reduce(math.min);
    final secondTop = b
        .map((target) => sourceByTarget[target.id]!.top)
        .reduce(math.min);
    return firstTop.compareTo(secondTop);
  });
  for (final row in rows) {
    row.sort((a, b) {
      final horizontal = sourceByTarget[a.id]!.left.compareTo(
        sourceByTarget[b.id]!.left,
      );
      return horizontal == 0
          ? (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0)
          : horizontal;
    });
  }
  return rows.expand((row) => row).toList();
}

typedef EnglishVocabularyEntry = ({
  String word,
  String meaning,
  int unit,
  EnglishSource source,
  int? printedPage,
});

class EnglishCourseParser {
  static const version = 1;

  EnglishCourse outline(Textbook book, List<TextbookPageText> pages) {
    final lessons = <EnglishLesson>[];
    final coverage = <int, String>{};
    var unitId = 'front', unitTitle = '原书与待分类内容';
    var appendix = false;
    var starterInDirectory = false;
    for (final page in pages) {
      final lines = englishPageLines(page);
      final raw = page.text;
      final directory =
          raw.contains('目 录') ||
          raw.contains('目\r\n录') ||
          raw.replaceAll(RegExp(r'\s'), '').contains('目录');
      final appendixHeading = RegExp(r'附录[一二三四1234]').hasMatch(raw);
      if (directory && raw.contains('Starter')) starterInDirectory = true;
      if (appendixHeading && !directory) appendix = true;
      if (directory ||
          appendix ||
          lessons.isEmpty && !RegExp(r'Unit\s+1\s').hasMatch(raw)) {
        coverage[page.page] = directory
            ? '目录'
            : appendix
            ? '附录与词汇来源'
            : '封面与导读';
        continue;
      }
      final unitLine = lines
          .where((l) => _unit.hasMatch(l.text) && l.source.top < .45)
          .firstOrNull;
      final titleLine = lines
          .where((l) => _heading.hasMatch(l.text) && l.source.top < .4)
          .firstOrNull;
      String? title, kind;
      if (unitLine != null) {
        final m = _unit.firstMatch(unitLine.text)!;
        unitId = 'unit-${m[1]}';
        unitTitle = unitLine.text;
        title = '单元导入';
        kind = 'intro';
      } else if (titleLine != null) {
        title = titleLine.text;
        kind = title.startsWith('Revision')
            ? 'revision'
            : title.startsWith('Story')
            ? 'story'
            : title.startsWith('Review')
            ? 'review'
            : title == 'Starter'
            ? 'intro'
            : 'lesson';
        if (kind == 'revision') {
          unitId = 'revision-${page.page}';
          unitTitle = title;
        }
      }
      if (title != null ||
          lessons.isEmpty ||
          page.page - lessons.last.startPage >= 39) {
        lessons.add(
          EnglishLesson(
            id: '$unitId-p${page.page}',
            unitId: unitId,
            unitTitle: unitTitle,
            title: title ?? '待分类内容',
            kind: kind ?? 'unclassified',
            startPage: page.page,
            endPage: page.page,
            issues: starterInDirectory && unitId == 'unit-1' && kind == 'intro'
                ? ['目录列有 Starter，请对照原书确认它与 Unit 1 的页码和内容归属；此处保留为单元导入，不自动批准。']
                : const [],
          ),
        );
      } else {
        lessons[lessons.length - 1] = lessons.last.change({
          'endPage': page.page,
        });
      }
      coverage[page.page] = lessons.last.id;
    }
    // Unknown books remain editable instead of silently becoming an empty curriculum.
    if (lessons.isEmpty) {
      for (var p = 1; p <= book.pageCount; p += 20) {
        final end = math.min(p + 19, book.pageCount), id = 'unclassified-p$p';
        lessons.add(
          EnglishLesson(
            id: id,
            unitId: 'unclassified',
            unitTitle: '待分类内容',
            title: '原书 $p–$end 页',
            kind: 'unclassified',
            startPage: p,
            endPage: end,
          ),
        );
        for (var i = p; i <= end; i++) {
          coverage[i] = id;
        }
      }
    }
    return EnglishCourse(
      bookId: book.pdfSha256,
      editionId: book.learningEditionId,
      pageCount: book.pageCount,
      fileSize: book.fileSize,
      parserVersion: version,
      lessons: lessons,
      coverage: coverage,
    );
  }

  List<EnglishVocabularyEntry> vocabulary(List<TextbookPageText> pages) {
    final result = <EnglishVocabularyEntry>[];
    var active = false, unit = 0;
    for (final page in pages) {
      final compact = page.text.replaceAll(RegExp(r'\s'), '');
      if (compact.contains('附录二单元词汇表')) active = true;
      if (compact.contains('附录三') || compact.contains('总词汇表')) active = false;
      if (!active) continue;
      final lines = englishPageLines(page);
      // Vocabulary appendices are two columns; read down each column.
      final ordered = <EnglishTextLine>[];
      for (final right in [false, true]) {
        final column = lines
            .where((l) => (l.source.left >= .5) == right)
            .toList();
        final rows = <List<EnglishTextLine>>[];
        for (final line in column) {
          final row = rows
              .where(
                (r) =>
                    (r.first.source.bottom - line.source.bottom).abs() < .012,
              )
              .lastOrNull;
          (row ?? (rows..add([])).last).add(line);
        }
        for (final row in rows) {
          row.sort((a, b) => a.source.left.compareTo(b.source.left));
          ordered.add(
            EnglishTextLine(row.map((l) => l.text).join(' '), row.first.source),
          );
        }
      }
      var pending = '';
      EnglishSource? pendingSource;
      for (final line in ordered) {
        final text = line.text.trim();
        final heading = RegExp(r'^Unit\s+(\d+)$').firstMatch(text);
        if (heading != null) {
          unit = int.parse(heading[1]!);
          pending = '';
          pendingSource = null;
          continue;
        }
        if (unit == 0 ||
            text.contains('附录') ||
            text.contains('重点词汇') ||
            RegExp(r'^\d+$').hasMatch(text)) {
          continue;
        }
        pendingSource ??= line.source;
        pending = '$pending $text'.trim();
        final end = RegExp(r'[（(]\s*(\d+)\s*[）)]\s*$').firstMatch(pending);
        if (end == null) continue;
        final match = RegExp(
          r'^([A-Za-z][A-Za-z ’\x27-]*?)\s*([\u3400-\u9fff（(].*)',
        ).firstMatch(pending.substring(0, end.start).trim());
        if (match != null) {
          result.add((
            word: match[1]!.trim(),
            meaning: match[2]!.trim(),
            unit: unit,
            source: pendingSource,
            printedPage: int.parse(end[1]!),
          ));
        }
        pending = '';
        pendingSource = null;
      }
    }
    // `ordered` already preserves source traversal: column one top-to-bottom,
    // then column two top-to-bottom. A global geometric sort here would
    // incorrectly interleave the two printed columns by row.
    return result;
  }

  EnglishLesson prepare(
    EnglishLesson plan,
    List<TextbookPageText> pages,
    List<EnglishVocabularyEntry> vocabulary,
  ) {
    final targets = <EnglishTarget>[];
    final issues = [...plan.issues];
    final unitNumber = int.tryParse(plan.unitId.replaceFirst('unit-', ''));
    final printed = <int>{};
    for (final page in pages) {
      final footer = englishPageLines(page)
          .where(
            (l) => l.source.top > .85 && RegExp(r'^\d{1,3}$').hasMatch(l.text),
          )
          .lastOrNull;
      if (footer != null) printed.add(int.parse(footer.text));
    }
    final words = vocabulary
        .where((v) => v.unit == unitNumber && printed.contains(v.printedPage))
        .toList();
    for (final v in words) {
      final source = pages
          .expand((page) => englishPageLines(page))
          .where(
            (line) => line.text.toLowerCase().contains(v.word.toLowerCase()),
          )
          .firstOrNull
          ?.source;
      final sources = <EnglishSource>[
        source ?? v.source,
        if (source != null && source.page != v.source.page) v.source,
      ];
      targets.add(
        EnglishTarget(
          id: '${plan.id}-word-${targets.length}',
          kind: EnglishTargetKind.vocabulary,
          text: v.word,
          meaning: v.meaning,
          sources: sources,
        ),
      );
    }
    var sentenceIndex = 0, activityIndex = 0;
    for (final page in pages) {
      if (page.text.trim().isEmpty || page.status != 'text_extracted') {
        issues.add('PDF 第 ${page.page} 页有图形或提取缺失，请对照原书补齐。');
      }
      final lines = englishPageLines(page);
      final prose = <EnglishTextLine>[];
      for (final l in lines) {
        final text = l.text.replaceFirst(RegExp(r'^[A-D]\s+'), '').trim();
        if (_instruction.hasMatch(text)) {
          targets.add(
            EnglishTarget(
              id: '${plan.id}-activity-${activityIndex++}',
              kind: EnglishTargetKind.activity,
              text: text,
              sources: [l.source],
            ),
          );
          continue;
        }
        if (l.source.top < .05 ||
            l.source.bottom > .94 ||
            _heading.hasMatch(text) ||
            _unit.hasMatch(text) ||
            _han.hasMatch(text) ||
            !RegExp('[A-Za-z]').hasMatch(text) ||
            text.length < 3 ||
            words.any((w) => w.word.toLowerCase() == text.toLowerCase())) {
          continue;
        }
        prose.add(l);
      }
      final consumed = <int>{};
      for (var i = 0; i < prose.length; i++) {
        if (consumed.contains(i)) continue;
        var text = prose[i].text;
        final sources = [prose[i].source];
        consumed.add(i);
        // Join only a nearby line of the same speech bubble, never across columns/pages.
        while (!RegExp(r'[.!?…][”’\x27]?$').hasMatch(text)) {
          final last = sources.last;
          final next = prose.indexed
              .where(
                (e) =>
                    !consumed.contains(e.$1) &&
                    e.$2.source.top >= last.bottom - .005 &&
                    e.$2.source.top - last.bottom < .025 &&
                    (e.$2.source.left - last.left).abs() < .09,
              )
              .firstOrNull;
          if (next == null) break;
          consumed.add(next.$1);
          text += ' ${next.$2.text}';
          sources.add(next.$2.source);
        }
        if (text.length > 2 &&
            (text.contains(' ') || RegExp(r'[.!?]').hasMatch(text))) {
          targets.add(
            EnglishTarget(
              id: '${plan.id}-sentence-${sentenceIndex++}',
              kind: EnglishTargetKind.sentence,
              text: text,
              sources: sources,
            ),
          );
        }
      }
      if (page.text.toLowerCase().contains('write') ||
          plan.title.contains('Lesson 3')) {
        issues.add('PDF 第 ${page.page} 页：请核对字母与书写图形，文字层可能不含这些字形。');
      }
    }
    for (final page in pages) {
      final lines = englishPageLines(page);
      final indexes = [
        for (final (index, target) in targets.indexed)
          if (target.kind == EnglishTargetKind.sentence &&
              target.sources.any((source) => source.page == page.page))
            index,
      ];
      if (indexes.isEmpty) continue;
      final sourceByTarget = <String, EnglishSource>{};
      final cardNumberByTarget = <String, int>{};
      final originalOrder = <String, int>{};
      for (final index in indexes) {
        final target = targets[index];
        final source = target.sources
            .where((value) => value.page == page.page)
            .first;
        sourceByTarget[target.id] = source;
        originalOrder[target.id] = index;
        final cardNumber = englishNumberedCardForSource(source, lines);
        if (cardNumber != null) cardNumberByTarget[target.id] = cardNumber;
      }
      // Apply card ordering only when every sentence has an unambiguous card.
      // Otherwise preserve the existing geometry-based parser order.
      if (cardNumberByTarget.length != indexes.length) continue;
      final reordered = <EnglishTarget>[];
      for (final cardNumber
          in cardNumberByTarget.values.toSet().toList()..sort()) {
        final cardTargets = targets
            .where((target) => cardNumberByTarget[target.id] == cardNumber)
            .toList();
        reordered.addAll(
          englishTargetsInSourceRowOrder(
            cardTargets,
            sourceByTarget,
            originalOrder: originalOrder,
          ),
        );
      }
      for (final (slot, target) in indexes.indexed) {
        targets[target] = reordered[slot];
      }
    }
    if (targets.any((t) => t.kind == EnglishTargetKind.sentence)) {
      issues.add('请按原书图画核对对话顺序与角色，再启用听读。');
    }
    if (targets.isEmpty) issues.add('保留原书范围，可手动添加词句、字母或活动。');
    return plan.change({
      'prepared': true,
      'targets': targets.map((t) => t.toJson()).toList(),
      'issues': issues.toSet().toList(),
    });
  }
}
