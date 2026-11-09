import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 星空、星云与间歇流星；固定星图与周期运动使循环首尾自然衔接。
class HeroStarlightPainter extends CustomPainter {
  HeroStarlightPainter({
    required this.base,
    required this.depth,
    required this.foreground,
    required this.glow,
    required this.motion,
    required this.pull,
  }) : super(repaint: motion);

  final Color base;
  final Color depth;
  final Color foreground;
  final Color glow;
  final Animation<double> motion;
  final double pull;

  // 先限制光晕自身亮度，再做透明叠加，保证相遇时也不会冲淡文字。
  late final _light = _readableGlow(Color.lerp(glow, foreground, .18)!);
  late final _coolLight = _readableGlow(
    Color.lerp(ColorTokens.mathPurple, foreground, .12)!,
  );
  late final _starLight = _readableGlow(foreground);

  Color _readableGlow(Color candidate) =>
      _readableHeroLight(depth, foreground, candidate);

  // 只生成一次，不在每帧取随机数，避免闪烁变成整片星图跳动。
  static final _stars = _createStars();

  static const _meteorPaths = [
    (from: Offset(.32, .12), to: Offset(.04, .62)),
    (from: Offset(.95, .42), to: Offset(.74, .8)),
    (from: Offset(.24, .45), to: Offset(.035, .82)),
    (from: Offset(.82, .13), to: Offset(.64, .45)),
    (from: Offset(.3, .25), to: Offset(.04, .7)),
    (from: Offset(.95, .59), to: Offset(.76, .94)),
    (from: Offset(.27, .62), to: Offset(.08, .94)),
    (from: Offset(.86, .28), to: Offset(.69, .56)),
  ];

  static List<({double x, double y, double seed, double radius})>
  _createStars() {
    final random = math.Random(37);
    return List.generate(
      144,
      (_) => (
        x: .025 + random.nextDouble() * .95,
        y: .07 + random.nextDouble() * .86,
        seed: random.nextDouble() * math.pi * 2,
        radius: .55 + random.nextDouble(),
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final phase = motion.value * math.pi * 2;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, depth],
        ).createShader(bounds),
    );

    // 星云八秒流动一轮，光轨十六秒环绕一周；渐变代替离屏模糊。
    for (var layer = 0; layer < 2; layer++) {
      final travel = phase * 2 + layer * math.pi;
      final center = Offset(
        size.width *
            (.5 + (layer == 0 ? math.cos(travel) : math.sin(travel)) * .42),
        size.height * (.25 + layer * .37 + math.sin(travel + layer) * .22),
      );
      final radius =
          math.min(size.width * .52, size.height * 1.25) * (1 + pull * .15);
      final tint = layer == 0 ? _light : _coolLight;
      final strength =
          (layer == 0 ? .92 : .5) * (.8 + .2 * (1 + math.sin(travel + .6)) / 2);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              tint.withValues(alpha: strength),
              tint.withValues(alpha: strength * .6),
              tint.withValues(alpha: 0),
            ],
            stops: const [0, .42, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    final count = (size.width / 6).round().clamp(56, _stars.length);
    for (var i = 0; i < count; i++) {
      final star = _stars[i];
      final twinkle = (1 + math.sin(phase * (2 + i % 3) + star.seed)) / 2;
      final point = Offset(
        star.x * size.width + math.sin(phase + star.seed) * 1.4,
        star.y * size.height + math.cos(phase + star.seed) * 1.4,
      );
      // 等级与星星数字附近降低装饰密度，外围保留清晰闪烁。
      final quiet = (star.x - .5).abs() < .23 && star.y > .5 ? .28 : 1.0;
      final paint = Paint()
        ..color = _starLight.withValues(
          alpha: (.24 + twinkle * twinkle * .76) * quiet,
        );
      if (i % 9 == 0) {
        final radius = 1.8 + twinkle * 2.4;
        canvas.drawCircle(
          point,
          radius * 2,
          Paint()
            ..shader = RadialGradient(
              colors: [
                _light.withValues(alpha: .4 * twinkle * quiet),
                _light.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: point, radius: radius * 2)),
        );
        final sparkle = Path()
          ..moveTo(point.dx, point.dy - radius)
          ..quadraticBezierTo(
            point.dx + radius * .2,
            point.dy - radius * .2,
            point.dx + radius,
            point.dy,
          )
          ..quadraticBezierTo(
            point.dx + radius * .2,
            point.dy + radius * .2,
            point.dx,
            point.dy + radius,
          )
          ..quadraticBezierTo(
            point.dx - radius * .2,
            point.dy + radius * .2,
            point.dx - radius,
            point.dy,
          )
          ..quadraticBezierTo(
            point.dx - radius * .2,
            point.dy - radius * .2,
            point.dx,
            point.dy - radius,
          )
          ..close();
        canvas.drawPath(sparkle, paint);
      } else {
        canvas.drawCircle(point, star.radius * (.8 + twinkle * .3), paint);
      }
    }

    // 每轮八颗流星交错划过两侧，约两秒一颗；相位零点无流星，
    // 系统减少动态效果时呈现完整静态星空，不留半条悬停的拖尾。
    for (var i = 0; i < _meteorPaths.length; i++) {
      final path = _meteorPaths[i];
      _paintMeteor(
        canvas,
        size,
        start: .025 + i / _meteorPaths.length,
        from: path.from,
        to: path.to,
      );
    }
    canvas.restore();
  }

  void _paintMeteor(
    Canvas canvas,
    Size size, {
    required double start,
    required Offset from,
    required Offset to,
  }) {
    final progress = (motion.value - start) / .095;
    if (progress <= 0 || progress >= 1) return;
    final origin = Offset(from.dx * size.width, from.dy * size.height);
    final destination = Offset(to.dx * size.width, to.dy * size.height);
    final path = destination - origin;
    final direction = path / path.distance;
    final head = origin + path * progress;
    final opacity = math.sin(progress * math.pi);
    final tail = head - direction * math.min(path.distance * .5, 64) * opacity;
    final shader = ui.Gradient.linear(
      tail,
      head,
      [
        _light.withValues(alpha: 0),
        _light.withValues(alpha: opacity * .5),
        _starLight.withValues(alpha: opacity),
      ],
      [0, .7, 1],
    );
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..shader = ui.Gradient.linear(tail, head, [
          _light.withValues(alpha: 0),
          _light.withValues(alpha: opacity * .22),
        ])
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final edge = Offset(-direction.dy, direction.dx) * 1.6;
    canvas.drawPath(
      Path()
        ..moveTo(tail.dx, tail.dy)
        ..lineTo((head + edge).dx, (head + edge).dy)
        ..lineTo((head - edge).dx, (head - edge).dy)
        ..close(),
      Paint()..shader = shader,
    );
    canvas.drawCircle(
      head,
      2.1,
      Paint()..color = _starLight.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(HeroStarlightPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.depth != depth ||
      oldDelegate.foreground != foreground ||
      oldDelegate.glow != glow ||
      oldDelegate.pull != pull ||
      oldDelegate.motion != motion;
}

/// 第一版的两道倾斜椭圆光轨；柔光亮弧与星点沿轨道反向环绕。
/// 绘制区域由头像外的 OverflowBox 提供，避免改变前景的布局和间距。
class HeroAvatarHaloPainter extends CustomPainter {
  HeroAvatarHaloPainter({
    required this.base,
    required this.foreground,
    required this.glow,
    required this.motion,
  }) : super(repaint: motion);

  final Color base;
  final Color foreground;
  final Color glow;
  final Animation<double> motion;

  // 光轨可能经过文字后方；限制色值而不是仅限制透明度。
  late final _light = _readableHeroLight(base, foreground, foreground);
  late final _haloLight = _readableHeroLight(
    base,
    foreground,
    Color.lerp(glow, foreground, .25)!,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final phase = motion.value * math.pi * 2;
    final center = size.center(Offset.zero);
    final reach = math.min(size.width * .46, SpacingTokens.xxl * 4);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 四秒一轮的呼吸光，只有光晕的亮度与扩散范围变化，头像保持稳定。
    final pulse = (1 - math.cos(phase * 4)) / 2;
    final haloRadius =
        SpacingTokens.xl + SpacingTokens.md + SpacingTokens.xs * pulse;
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _haloLight.withValues(alpha: 0),
            _haloLight.withValues(alpha: .12 + pulse * .65),
            _haloLight.withValues(alpha: 0),
          ],
          stops: const [.5, .69, 1],
        ).createShader(Rect.fromCircle(center: center, radius: haloRadius)),
    );
    canvas.drawCircle(
      center,
      SpacingTokens.xl + SpacingTokens.xs / 2,
      Paint()
        ..color = _haloLight.withValues(alpha: .18 + pulse * .78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + pulse * .8,
    );

    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.2);
    for (var orbit = 0; orbit < 2; orbit++) {
      final rx = reach * (.66 + orbit * .3);
      final ry = rx * (.48 + orbit * .05);
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2,
        height: ry * 2,
      );
      final travel = phase * (orbit == 0 ? 1 : -1) + orbit * math.pi;
      canvas.drawOval(
        oval,
        Paint()
          ..color = _light.withValues(alpha: .18 - orbit * .04)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );
      canvas.drawArc(
        oval,
        travel - 1.3,
        1.3,
        false,
        Paint()
          ..shader = SweepGradient(
            transform: GradientRotation(travel - 1.3),
            startAngle: 0,
            endAngle: 1.3,
            colors: [_light.withValues(alpha: 0), _light.withValues(alpha: .8)],
          ).createShader(oval)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final spark = Offset(math.cos(travel) * rx, math.sin(travel) * ry);
      canvas.drawCircle(
        spark,
        SpacingTokens.xs,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  _light.withValues(alpha: .75),
                  _light.withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(center: spark, radius: SpacingTokens.xs),
              ),
      );
      canvas.drawCircle(
        spark,
        1.2,
        Paint()..color = _light.withValues(alpha: .9),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HeroAvatarHaloPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.foreground != foreground ||
      oldDelegate.glow != glow ||
      oldDelegate.motion != motion;
}

Color _readableHeroLight(Color depth, Color foreground, Color candidate) {
  final front = foreground.computeLuminance();
  var low = 0.0;
  var high = 1.0;
  for (var step = 0; step < 12; step++) {
    final mix = (low + high) / 2;
    final luminance = Color.lerp(depth, candidate, mix)!.computeLuminance();
    if ((front + .05) / (luminance + .05) >= 5.2) {
      low = mix;
    } else {
      high = mix;
    }
  }
  return Color.lerp(depth, candidate, low)!;
}
