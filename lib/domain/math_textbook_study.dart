import 'dart:math' as math;

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';

final _exampleTitleSuffix = RegExp(r'\s*·\s*例\s*[^·]+$');

class MathTextbookWorkedExample {
  const MathTextbookWorkedExample({
    required this.id,
    required this.title,
    required this.blocks,
  });

  final String id, title;
  final List<MathTextbookBlock> blocks;
}

List<MathTextbookWorkedExample> mathTextbookWorkedExamples(
  MathTextbookLesson lesson,
) {
  final examples = <MathTextbookWorkedExample>[];
  final sections = mathTextbookExampleSections(lesson);
  var collecting = false;
  for (final block in lesson.blocks) {
    if (block.kind == MathTextbookBlockKind.sourcePage ||
        isMathTextbookFooter(block)) {
      continue;
    }
    if (block.kind == MathTextbookBlockKind.example) {
      final point = lesson.learning?.knowledgePoints
          .where((point) => point.blockIds.contains(block.id))
          .firstOrNull;
      final pointTitle = point?.title.trim() ?? '';
      final exampleTitle = mathTextbookSectionTitle(block);
      final hasPointTitle = isReadableMathTextbookDisplayTitle(
        pointTitle.replaceFirst(_exampleTitleSuffix, '').trim(),
      );
      final section = sections[block.id] ?? '';
      final title = hasPointTitle
          ? pointTitle
          : section.isEmpty
          ? exampleTitle
          : '$section · $exampleTitle';
      examples.add(
        MathTextbookWorkedExample(id: block.id, title: title, blocks: [block]),
      );
      collecting = true;
    } else if (block.kind == MathTextbookBlockKind.heading &&
        !isMathTextbookExampleStepHeading(block.text)) {
      collecting = false;
    } else if (block.kind == MathTextbookBlockKind.exercise) {
      collecting = false;
    } else if (collecting) {
      final previous = examples.removeLast();
      examples.add(
        MathTextbookWorkedExample(
          id: previous.id,
          title: previous.title,
          blocks: [...previous.blocks, block],
        ),
      );
    }
  }
  return examples;
}

/// Printed practice headers bound example previews. Use the actual glyphs:
/// organized source crops may overlap a heading or a neighbouring drawing.
MathTextbookRegion mathTextbookExampleRegion(
  MathTextbookRegion source,
  TextbookPageText page,
) {
  if (page.page != source.page) return source;
  final glyphs = page.glyphs.where((g) => g.text.trim().isNotEmpty).toList();
  var bottom = source.bottom;
  for (final first in glyphs) {
    if (!const {'做', '想', '说', '试', '练'}.contains(first.text) ||
        first.height <= 0 ||
        first.top <= source.top ||
        first.top >= bottom ||
        first.right < source.left ||
        first.left > source.right) {
      continue;
    }
    final row =
        glyphs
            .where(
              (glyph) =>
                  (glyph.top - first.top).abs() < first.height * .5 &&
                  (glyph.bottom - first.bottom).abs() < first.height * .5,
            )
            .toList()
          ..sort((a, b) => a.left.compareTo(b.left));
    final start = row.indexOf(first);
    bool adjacent(TextbookPageGlyph a, TextbookPageGlyph b) =>
        b.left - a.right <= math.max(a.width, b.width) * 2;
    if (start > 0 && adjacent(row[start - 1], first)) continue;
    var end = start;
    while (end + 1 < row.length && adjacent(row[end], row[end + 1])) {
      end++;
    }
    final heading = row.sublist(start, end + 1);
    if (!isMathTextbookPracticeHeading(heading.map((g) => g.text).join())) {
      continue;
    }
    // Match a standalone heading, never an instruction such as “想一想：…”.
    final top = heading.map((g) => g.top).reduce(math.min);
    final boundary = top - first.height * .35;
    // Some books put an example's final speech bubble beside this banner.
    // A horizontal crop must not cut through that explanation.
    if (glyphs.any(
      (glyph) =>
          !heading.contains(glyph) &&
          glyph.left < source.right &&
          glyph.right > source.left &&
          glyph.top < top &&
          glyph.bottom > boundary,
    )) {
      continue;
    }
    if (boundary > source.top) bottom = math.min(bottom, boundary);
  }
  if (bottom == source.bottom) return source;
  return MathTextbookRegion(
    page: source.page,
    left: source.left,
    top: source.top,
    right: source.right,
    bottom: bottom,
    printedPage: source.printedPage,
  );
}
