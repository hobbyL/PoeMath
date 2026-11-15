import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';
import 'package:poemath/features/textbook/writing/writing_path.dart';

/// 只展示已保存作品，不能在历史笔迹上继续书写。
class WritingAttemptPreview extends StatelessWidget {
  const WritingAttemptPreview({
    super.key,
    required this.attempt,
    this.showPieceBorders = false,
  });

  final WritingAttempt attempt;
  final bool showPieceBorders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final availableHeight =
            media.size.height -
            media.viewPadding.vertical -
            kToolbarHeight -
            SpacingTokens.md * 2;
        final side = math.min(
          constraints.maxWidth,
          math.max(
            SpacingTokens.minTapTarget,
            math.min(
              media.size.shortestSide - SpacingTokens.md * 2,
              availableHeight,
            ),
          ),
        );
        return Center(
          child: Semantics(
            image: true,
            label: attempt.kind == WritingAttemptKind.puzzle
                ? '已保存的拼装作品'
                : '已保存的笔迹，共 ${attempt.strokes.length} 笔',
            child: SizedBox.square(
              dimension: side,
              child: ClipRect(
                child: CustomPaint(
                  key: const ValueKey('writing-attempt-artwork'),
                  painter: attempt.kind == WritingAttemptKind.puzzle
                      ? WritingPuzzleResultPainter(
                          attempt: attempt,
                          showPieceBorders: showPieceBorders,
                          paper: scheme.surfaceContainerHigh,
                          ink: scheme.onSurface,
                          edge: scheme.outline,
                        )
                      : TianziGridPainter(
                          gridColor: scheme.outline,
                          referenceStrokes: attempt.referenceStrokes,
                          traceOpacity: attempt.kind == WritingAttemptKind.trace
                              ? 0.16
                              : 0,
                          userStrokes: [
                            for (final stroke in attempt.strokes)
                              [
                                for (final p in stroke)
                                  Offset(p.x * side, p.y * side),
                              ],
                          ],
                          strokeWidth: attempt.strokeWidth * side,
                          strokeColor: scheme.onSurface,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class WritingPuzzleResultPainter extends CustomPainter {
  WritingPuzzleResultPainter({
    required this.attempt,
    required this.showPieceBorders,
    required this.paper,
    required this.ink,
    required this.edge,
  }) : glyph = puzzleCharacterOutline(attempt.referenceStrokes);

  final WritingAttempt attempt;
  final bool showPieceBorders;
  final Color paper, ink, edge;
  final Path? glyph;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    canvas.save();
    canvas.scale(size.width, size.height);
    if (glyph case final path?) canvas.drawPath(path, Paint()..color = ink);
    if (showPieceBorders) {
      final paint = Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / size.shortestSide;
      for (final points in attempt.puzzle!.pieces) {
        final path = Path()..moveTo(points.first.x, points.first.y);
        for (final point in points.skip(1)) {
          path.lineTo(point.x, point.y);
        }
        canvas.drawPath(path..close(), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WritingPuzzleResultPainter old) =>
      old.attempt != attempt ||
      old.showPieceBorders != showPieceBorders ||
      old.paper != paper ||
      old.ink != ink ||
      old.edge != edge;
}
