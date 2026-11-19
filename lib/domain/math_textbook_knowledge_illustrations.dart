import 'dart:math' as math;

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';

List<MathTextbookBlock> mathTextbookKnowledgeImageBlocks(
  MathTextbookLesson lesson,
  MathTextbookKnowledgePoint point,
) => lesson.blocks
    .where(
      (block) =>
          point.blockIds.contains(block.id) &&
          block.kind != MathTextbookBlockKind.exercise &&
          block.kind != MathTextbookBlockKind.sourcePage &&
          (block.needsSource ||
              block.spans.any((span) => span.expression != null)),
    )
    .toList();

String _compact(String text) => text.replaceAll(RegExp(r'[\s。！？!?，、；：]'), '');

/// Select the teaching diagram next to an actual knowledge statement. Parsing
/// the page before organizing it provides separate prompt, diagram and formula
/// bounds; the saved, whole-example crop is not a knowledge illustration.
List<MathTextbookRegion> mathTextbookKnowledgeIllustrationRegions({
  required MathTextbookKnowledgePoint point,
  required List<MathTextbookBlock> blocks,
  required MathTextbookLesson parsedPage,
}) {
  final result = <MathTextbookRegion>[];
  final statements = point.summary
      .split('\n')
      .map(_compact)
      .where((s) => s.length >= 6)
      .toList();
  final parts = parsedPage.blocks
      .where(
        (b) =>
            b.kind != MathTextbookBlockKind.sourcePage &&
            !isMathTextbookFooter(b),
      )
      .toList();
  for (final block in blocks) {
    for (final source in block.sources.where(
      (s) => s.page == parsedPage.startPage,
    )) {
      var start = source.top, end = source.bottom;
      if (block.kind == MathTextbookBlockKind.example) {
        final marker = parts.indexWhere(
          (part) =>
              part.kind == MathTextbookBlockKind.example &&
              part.exerciseNumber == block.exerciseNumber &&
              source.containsCenter(part.sources.single),
        );
        // Never fall back to displaying an entire example when its diagram
        // boundary cannot be recovered from this page's evidence.
        if (marker < 0) continue;
        start = parts[marker].sources.single.top;
        final next = parts
            .skip(marker + 1)
            .where(
              (part) =>
                  part.kind == MathTextbookBlockKind.example ||
                  part.kind == MathTextbookBlockKind.exercise ||
                  part.kind == MathTextbookBlockKind.heading &&
                      !isMathTextbookExampleStepHeading(part.text),
            )
            .firstOrNull;
        end = next?.sources.single.top ?? source.bottom;
      }
      final section = parts.where((part) {
        final region = part.sources.single;
        return region.bottom > start &&
            region.top < end &&
            region.centerX >= source.left &&
            region.centerX <= source.right;
      }).toList();
      final anchors = section.where((part) {
        if (block.kind == MathTextbookBlockKind.illustration &&
            part.kind == MathTextbookBlockKind.illustration) {
          return true;
        }
        final text = _compact(part.text).replaceFirst(RegExp(r'^\d+'), '');
        return text.length >= 6 &&
            statements.any((s) => text.contains(s) || s.contains(text));
      });
      final diagrams = section.where((part) {
        final region = part.sources.single;
        return (part.kind == MathTextbookBlockKind.illustration ||
                part.kind == MathTextbookBlockKind.formula) &&
            region.top >= start &&
            region.top < end &&
            !RegExp(r'[？?]|做一做|试一试|填一填').hasMatch(part.text);
      }).toList();
      for (final anchor in anchors) {
        final anchorRegion = anchor.sources.single;
        double gap(MathTextbookRegion region) => math.max(
          0,
          math.max(
            anchorRegion.top - region.bottom,
            region.top - anchorRegion.bottom,
          ),
        );
        final nearby = [...diagrams]
          ..sort(
            (a, b) => gap(a.sources.single).compareTo(gap(b.sources.single)),
          );
        if (nearby.isEmpty || gap(nearby.first.sources.single) > .10) continue;
        MathTextbookRegion withinSection(MathTextbookRegion region) =>
            MathTextbookRegion(
              page: region.page,
              left: region.left,
              right: region.right,
              top: math.max(start, region.top),
              bottom: math.min(end, region.bottom),
            );
        final nearest = withinSection(nearby.first.sources.single);
        var diagram = nearest;
        // A method may be a row of bundles, an arrow, and a vertical sum.
        // Preserve the whole row, with its labels, instead of one fragment.
        for (final part in nearby.skip(1)) {
          final region = withinSection(part.sources.single);
          final overlap =
              math.min(nearest.bottom, region.bottom) -
              math.max(nearest.top, region.top);
          if (overlap > math.min(nearest.height, region.height) * .35) {
            diagram = diagram.merge(region);
          }
        }
        // A crop cannot bring the example badge/prompt or a practice heading
        // back through a neighbouring illustration's overlapping bounds.
        if (section.any(
          (part) =>
              (part.kind == MathTextbookBlockKind.example ||
                  part.kind == MathTextbookBlockKind.exercise) &&
              diagram.containsCenter(part.sources.single),
        )) {
          continue;
        }
        final padded = MathTextbookRegion(
          page: source.page,
          left: math.max(0, diagram.left - .004),
          right: math.min(1, diagram.right + .004),
          top: math.max(start, diagram.top - .004),
          bottom: math.min(end, diagram.bottom + .004),
          printedPage: source.printedPage,
        );
        if (!result.any(
          (existing) =>
              existing.page == padded.page &&
              (existing.left - padded.left).abs() < .001 &&
              (existing.top - padded.top).abs() < .001 &&
              (existing.right - padded.right).abs() < .001 &&
              (existing.bottom - padded.bottom).abs() < .001,
        )) {
          result.add(padded);
        }
      }
    }
  }
  return result;
}
