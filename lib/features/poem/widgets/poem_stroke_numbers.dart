import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';

typedef _StrokeNumberPlacement = ({int number, Offset anchor, Rect bounds});

/// 错笔序号覆盖层。键是原始笔迹下标，值是核对说明中的一基笔号。
class PoemStrokeNumbers extends StatelessWidget {
  const PoemStrokeNumbers({
    super.key,
    required this.strokes,
    required this.numbers,
  });

  final List<List<Offset>> strokes;
  final Map<int, int> numbers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final style = theme.textTheme.labelSmall!.copyWith(
      fontSize: TypographyTokens.fsLabel,
      fontWeight: FontWeight.w700,
      height: 1,
      color: theme.colorScheme.onError,
    );
    var diameter = SpacingTokens.lg;
    for (final number in numbers.values) {
      final text = TextPainter(
        text: TextSpan(text: '$number', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      diameter = math.max(
        diameter,
        math.max(text.width, text.height) + SpacingTokens.sm,
      );
      text.dispose();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final available = size.shortestSide - SpacingTokens.xs * 2;
          if (available <= 0) return const SizedBox.shrink();
          final placements = _placeNumbers(size, math.min(diameter, available));
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _StrokeNumberLeaders(
                    placements: placements,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              for (final placement in placements)
                Positioned.fromRect(
                  rect: placement.bounds,
                  child: Semantics(
                    key: ValueKey('poem-stroke-number-${placement.number}'),
                    label: '第 ${placement.number} 笔有问题',
                    excludeSemantics: true,
                    child: Material(
                      color: theme.colorScheme.error,
                      shape: const CircleBorder(),
                      child: Center(
                        child: Text('${placement.number}', style: style),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<_StrokeNumberPlacement> _placeNumbers(Size size, double diameter) {
    final radius = diameter / 2;
    final inset = radius + SpacingTokens.xs;
    final inkBounds = [
      for (final stroke in strokes)
        for (var i = 1; i < stroke.length; i++)
          Rect.fromPoints(
            stroke[i - 1],
            stroke[i],
          ).inflate(SpacingTokens.xs / 2),
    ];
    final placements = <_StrokeNumberPlacement>[];
    for (final entry in numbers.entries) {
      if (entry.key < 0 || entry.key >= strokes.length) continue;
      final stroke = strokes[entry.key];
      if (stroke.isEmpty) continue;
      _StrokeNumberPlacement? best;
      var bestOverlaps = placements.length + 1;
      var bestInk = inkBounds.length + 1;
      var bestDistance = double.infinity;
      // 优先错开已有序号，再避开笔迹，最后选择离笔画最近的位置。
      for (final point in [
        stroke.first,
        stroke[stroke.length ~/ 2],
        stroke.last,
      ]) {
        final anchor = Offset(
          point.dx.clamp(0, size.width),
          point.dy.clamp(0, size.height),
        );
        for (final gap in [
          SpacingTokens.sm,
          diameter + SpacingTokens.sm,
          diameter * 2 + SpacingTokens.sm,
        ]) {
          for (final direction in const [
            Offset(1, -1),
            Offset(-1, -1),
            Offset(1, 1),
            Offset(-1, 1),
            Offset(0, -1),
            Offset(1, 0),
            Offset(-1, 0),
            Offset(0, 1),
          ]) {
            final candidate = anchor + direction * (radius + gap);
            final center = Offset(
              candidate.dx.clamp(inset, size.width - inset),
              candidate.dy.clamp(inset, size.height - inset),
            );
            final bounds = Rect.fromCircle(center: center, radius: radius);
            final overlaps = placements
                .where(
                  (p) => bounds.overlaps(p.bounds.inflate(SpacingTokens.xs)),
                )
                .length;
            final coveredInk = inkBounds.where(bounds.overlaps).length;
            final distance = (center - anchor).distanceSquared;
            if (overlaps < bestOverlaps ||
                (overlaps == bestOverlaps && coveredInk < bestInk) ||
                (overlaps == bestOverlaps &&
                    coveredInk == bestInk &&
                    distance < bestDistance)) {
              best = (number: entry.value, anchor: anchor, bounds: bounds);
              bestOverlaps = overlaps;
              bestInk = coveredInk;
              bestDistance = distance;
            }
          }
        }
      }
      if (best != null) placements.add(best);
    }
    return placements;
  }
}

class _StrokeNumberLeaders extends CustomPainter {
  const _StrokeNumberLeaders({required this.placements, required this.color});

  final List<_StrokeNumberPlacement> placements;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = SpacingTokens.imageIconOutline;
    for (final placement in placements) {
      final delta = placement.bounds.center - placement.anchor;
      final distance = delta.distance;
      final radius = placement.bounds.width / 2;
      if (distance <= radius) continue;
      canvas.drawLine(
        placement.anchor,
        placement.bounds.center - delta / distance * radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StrokeNumberLeaders oldDelegate) =>
      oldDelegate.placements != placements || oldDelegate.color != color;
}
