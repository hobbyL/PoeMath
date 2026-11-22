import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/adventure/adventure_artwork.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// An illustrated terrain with live waypoints. Each path is laid out with its
/// waypoint, so longer labels and larger fonts also lengthen the connecting road.
class AdventureRegionScene extends StatelessWidget {
  const AdventureRegionScene({
    super.key,
    required this.region,
    required this.skills,
    required this.current,
    required this.completed,
    required this.collected,
    required this.busy,
    this.topInset = 0,
    this.leading,
    required this.foregroundClipper,
    required this.startIndex,
    required this.anchorFor,
    required this.onSelect,
    required this.onAlbum,
  });

  final MathAdventureRegion region;
  final List<MathSkill> skills;
  final MathSkill? current;
  final Set<String> completed;
  final bool collected, busy;
  final int startIndex;
  final double topInset;
  final Widget? leading;
  final CustomClipper<Rect> foregroundClipper;
  final Key Function(MathSkill skill) anchorFor;
  final ValueChanged<MathSkill> onSelect;
  final VoidCallback onAlbum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final night = theme.brightness == Brightness.dark;
    return ColoredCard(
      color: theme.scaffoldBackgroundColor,
      backgroundOpacity: 1,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final fade = (SpacingTokens.xxl / bounds.height).clamp(
                    0.0,
                    .25,
                  );
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surface.withValues(alpha: topInset > 0 ? 1 : 0),
                      scheme.surface,
                      scheme.surface,
                      scheme.surface.withValues(alpha: 0),
                    ],
                    stops: [0, fade, 1 - fade, 1],
                  ).createShader(bounds);
                },
                child: Image.asset(
                  theme.appearance.adventureTerrain(region.name),
                  fit: BoxFit.cover,
                  repeat: ImageRepeat.noRepeat,
                  alignment: Alignment.topCenter,
                  cacheWidth: 1024,
                  color: night ? scheme.surface.withValues(alpha: .48) : null,
                  colorBlendMode: night ? BlendMode.srcATop : null,
                ),
              ),
            ),
          ),
          ClipRect(
            clipper: foregroundClipper,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topInset + SpacingTokens.md),
                ?leading,
                for (final (index, skill) in skills.indexed)
                  _Waypoint(
                    key: anchorFor(skill),
                    skill: skill,
                    number: startIndex + index + 1,
                    right: index.isOdd,
                    first: index == 0,
                    completed: completed.contains(skill.id),
                    current: current == skill,
                    busy: busy,
                    onTap: () => onSelect(skill),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.lg,
                    0,
                    SpacingTokens.lg,
                    SpacingTokens.lg,
                  ),
                  child: Semantics(
                    button: true,
                    label: collected
                        ? '已收集${region.souvenir}，打开纪念册'
                        : '区域纪念物${region.souvenir}，走完${region.title}后解锁',
                    excludeSemantics: true,
                    child: ColoredCard(
                      color: scheme.primary,
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      onTap: onAlbum,
                      child: Row(
                        children: [
                          AdventureSouvenir(
                            region: region,
                            size: SpacingTokens.xxl + SpacingTokens.md,
                            collected: collected,
                          ),
                          const SizedBox(width: SpacingTokens.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  collected ? '这片风景的礼物' : '前方的小惊喜',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: SpacingTokens.xs),
                                Text(
                                  region.souvenir,
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: SpacingTokens.xs),
                                Text(
                                  collected ? '已收进你的纪念册' : '走完这片区域，就能带走它',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Waypoint extends StatelessWidget {
  const _Waypoint({
    super.key,
    required this.skill,
    required this.number,
    required this.right,
    required this.first,
    required this.completed,
    required this.current,
    required this.busy,
    required this.onTap,
  });

  final MathSkill skill;
  final int number;
  final bool right, first, completed, current, busy;
  final VoidCallback onTap;
  static const diameter = SpacingTokens.xxl + SpacingTokens.xl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = current || completed;
    final state = completed
        ? '已完成 · 再玩一组'
        : current
        ? '当前关卡 · 整组全对过关'
        : '未解锁 · 前一站全对后开启';
    final face = current
        ? scheme.primary
        : completed
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final ink = current
        ? scheme.onPrimary
        : completed
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final scaler = MediaQuery.textScalerOf(context);
    final appearance = theme.appearance;
    final nodeShape = appearance.space
        ? BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          )
        : appearance.ink
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(appearance.cardRadius),
          )
        : const CircleBorder();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final labelWidth = math.min(
          width - SpacingTokens.xl,
          (SpacingTokens.xxl * 4 + SpacingTokens.md) * scaler.scale(14) / 14,
        );
        final travel = math.min(
          width * .22,
          (width - labelWidth) / 2 - SpacingTokens.sm,
        );
        final center = width / 2 + (right ? travel : -travel);
        return CustomPaint(
          painter: _RoadPainter(
            center: center,
            first: first,
            completed: completed,
            current: current,
            style: appearance.visualStyle,
            road: scheme.surface,
            edge: scheme.outlineVariant,
            trail: scheme.primary,
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  center - labelWidth / 2,
                  SpacingTokens.sm,
                  width - center - labelWidth / 2,
                  SpacingTokens.lg,
                ),
                child: Semantics(
                  button: true,
                  enabled: available && !busy,
                  label: '第 $number 站，${skill.label}，$state',
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: available && !busy ? onTap : null,
                      borderRadius: BorderRadius.circular(
                        SpacingTokens.radiusLarge,
                      ),
                      child: Column(
                        children: [
                          SizedBox.square(
                            dimension: diameter,
                            child: Padding(
                              padding: const EdgeInsets.all(SpacingTokens.xs),
                              child: Material(
                                color: face,
                                elevation: appearance.storybook ? 2 : 0,
                                shadowColor: scheme.shadow.withValues(
                                  alpha: .3,
                                ),
                                shape: nodeShape.copyWith(
                                  side: BorderSide(
                                    color: current
                                        ? scheme.secondary
                                        : scheme.outlineVariant,
                                    width: current ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: completed
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: SpacingTokens.xl,
                                          color: ink,
                                        )
                                      : current
                                      ? Text(
                                          '$number',
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(
                                                color: ink,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        )
                                      : Icon(
                                          Icons.lock_outline_rounded,
                                          size: SpacingTokens.lg,
                                          color: ink,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: SpacingTokens.sm),
                          ColoredCard(
                            color: scheme.primary,
                            backgroundOpacity: current ? .07 : .02,
                            padding: const EdgeInsets.symmetric(
                              horizontal: SpacingTokens.sm,
                              vertical: SpacingTokens.sm,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  skill.label,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: SpacingTokens.xs),
                                Text(
                                  state,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: current
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (current &&
                  appearance.adventureGuide != null &&
                  width - labelWidth >= diameter + SpacingTokens.md)
                Positioned(
                  top: SpacingTokens.lg,
                  left: right ? SpacingTokens.sm : null,
                  right: right ? null : SpacingTokens.sm,
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: Image.asset(
                        appearance.adventureGuide!,
                        width: math.min(
                          SpacingTokens.xxl * 2,
                          width - labelWidth - SpacingTokens.md,
                        ),
                        cacheWidth: 320,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RoadPainter extends CustomPainter {
  const _RoadPainter({
    required this.center,
    required this.first,
    required this.completed,
    required this.current,
    required this.road,
    required this.edge,
    required this.trail,
    required this.style,
  });

  final double center;
  final bool first, completed, current;
  final Color road, edge, trail;
  final AppVisualStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    // Extend each tangent beyond the clip edge: rounded caps must stay outside
    // the section, otherwise each join bulges when the road meets diagonally.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    const nodeY = SpacingTokens.sm + _Waypoint.diameter / 2;
    final upper = Path()
      ..moveTo(size.width / 2 - (center - size.width / 2) / 2, -nodeY / 3)
      ..lineTo(size.width / 2, 0)
      ..cubicTo(
        (size.width / 2 + center) / 2,
        nodeY / 3,
        center,
        nodeY / 3,
        center,
        nodeY,
      );
    final lower = Path()
      ..moveTo(center, nodeY)
      ..cubicTo(
        center,
        nodeY + (size.height - nodeY) / 2,
        (size.width / 2 + center) / 2,
        size.height - nodeY / 3,
        size.width / 2,
        size.height,
      )
      ..lineTo(
        size.width / 2 + (size.width / 2 - center) / 2,
        size.height + nodeY / 3,
      );
    void draw(Path path, bool walked) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (style != AppVisualStyle.storybook) {
        final ink = style == AppVisualStyle.pine || style == AppVisualStyle.ink;
        canvas.drawPath(
          path,
          paint
            ..color = walked ? trail.withValues(alpha: .65) : edge
            ..strokeWidth = ink ? 2 : 1,
        );
        if (!ink) {
          paint
            ..color = walked ? trail : edge
            ..strokeWidth = 3;
          for (final metric in path.computeMetrics()) {
            for (double d = 0; d < metric.length; d += SpacingTokens.lg) {
              canvas.drawPath(
                metric.extractPath(
                  d,
                  math.min(d + SpacingTokens.sm, metric.length),
                ),
                paint,
              );
            }
          }
        }
        return;
      }
      canvas.drawPath(
        path,
        paint
          ..color = edge.withValues(alpha: .6)
          ..strokeWidth = SpacingTokens.md + SpacingTokens.xs,
      );
      canvas.drawPath(
        path,
        paint
          ..color = road
          ..strokeWidth = SpacingTokens.md,
      );
      paint
        ..color = walked ? trail : edge
        ..strokeWidth = SpacingTokens.xs;
      for (final metric in path.computeMetrics()) {
        for (double d = 0; d < metric.length; d += SpacingTokens.md) {
          canvas.drawPath(
            metric.extractPath(
              d,
              math.min(d + SpacingTokens.xs, metric.length),
            ),
            paint,
          );
        }
      }
    }

    if (!first) draw(upper, completed || current);
    draw(lower, completed);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoadPainter oldDelegate) =>
      center != oldDelegate.center ||
      first != oldDelegate.first ||
      completed != oldDelegate.completed ||
      current != oldDelegate.current ||
      style != oldDelegate.style ||
      road != oldDelegate.road ||
      edge != oldDelegate.edge ||
      trail != oldDelegate.trail;
}
