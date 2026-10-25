import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook_course.dart';

const _readingObservation = '我发现这些加点的词是表示动作的。';

/// 原书习题的词组行与加点标记；纯文字题目仍可直接选择和复制。
class TextbookExercisePrompt extends StatelessWidget {
  const TextbookExercisePrompt({
    super.key,
    required this.exercise,
    this.showHeading = true,
  });
  final TextbookCourseExercise exercise;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall;
    if (exercise.promptLayout.isEmpty) {
      final prompt = !showHeading && exercise.promptHeading != null
          ? exercise.prompt.substring(exercise.prompt.indexOf('\n') + 1)
          : exercise.prompt;
      final visiblePrompt = prompt
          .split('\n')
          .where((line) => line.trim() != _readingObservation)
          .join('\n');
      return SelectableText(visiblePrompt, style: style);
    }
    final rows = (!showHeading && exercise.promptHeading != null
            ? exercise.promptLayout.skip(1)
            : exercise.promptLayout)
        .where(
          (row) =>
              row.length != 1 || row.single.text.trim() != _readingObservation,
        )
        .toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = rows.map((r) => r.length).reduce(math.max);
        final widths = List.filled(columns, 0.0);
        for (final row in rows.where((r) => r.length > 1)) {
          for (final (i, cell) in row.indexed) {
            final painter = TextPainter(
              text: TextSpan(text: cell.text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              locale: Localizations.maybeLocaleOf(context),
            )..layout();
            // SelectableText 为光标保留额外宽度，避免恰好等宽时把末字挤到下一行。
            widths[i] = math.max(widths[i], painter.width + SpacingTokens.xs);
            painter.dispose();
          }
        }
        final gap = SpacingTokens.md;
        final total = widths.fold(0.0, (a, b) => a + b);
        final available =
            math.max(0.0, constraints.maxWidth - gap * (columns - 1));
        if (total > available) {
          for (var i = 0; i < widths.length; i++) {
            widths[i] *= available / total;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (r, row) in rows.indexed)
              Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : SpacingTokens.md),
                child: row.length == 1
                    ? _cell(row.single, style, TextAlign.center)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var c = 0; c < columns; c++) ...[
                            if (c > 0) SizedBox(width: gap),
                            SizedBox(
                              width: widths[c],
                              child: c < row.length
                                  ? _cell(row[c], style, TextAlign.start)
                                  : null,
                            ),
                          ],
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(TextbookExerciseCell cell, TextStyle? style, TextAlign align) {
    if (cell.emphasis.isEmpty) {
      return SelectableText(cell.text, style: style, textAlign: align);
    }
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final (i, rune) in cell.text.runes.indexed)
            if (cell.emphasis.contains(i))
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(String.fromCharCode(rune), style: style),
                    const ExcludeSemantics(
                      child: SizedBox(
                        height: SpacingTokens.xs,
                        child: Icon(Icons.circle, size: SpacingTokens.xs),
                      ),
                    ),
                  ],
                ),
              )
            else
              TextSpan(text: String.fromCharCode(rune)),
        ],
      ),
      style: style,
      textAlign: align,
    );
  }
}
