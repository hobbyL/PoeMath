import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 主题的几何背景：绘本云朵和星空轨道。沿用页头的可见性与减弱动态时钟。
class PlayfulHeroPainter extends CustomPainter {
  PlayfulHeroPainter({
    required this.space,
    required this.base,
    required this.depth,
    required this.foreground,
    required this.motion,
  }) : super(repaint: motion);

  final bool space;
  final Color base;
  final Color depth;
  final Color foreground;
  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = base);
    final phase = motion.value * math.pi * 2;
    if (space) {
      final orbit = Paint()
        ..color = foreground.withValues(alpha: .06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final center = Offset(size.width * .82, size.height * .42);
      for (final scale in [.6, 1.05, 1.5]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: size.width * scale,
            height: size.height * scale * .7,
          ),
          orbit,
        );
      }
      final star = Paint()
        ..color = ColorTokens.spaceSecondaryLight.withValues(alpha: .12);
      for (var i = 0; i < 22; i++) {
        final point = Offset(
          ((i * 67 + 29) % 337) / 337 * size.width,
          ((i * 43 + 17) % 191) / 191 * size.height,
        );
        final radius = i % 4 == 0 ? 1.7 : 1.0;
        canvas.drawCircle(
          point + Offset(0, math.sin(phase + i) * 1.5),
          radius,
          star,
        );
      }
      // 右下角的轨道圆盘延续舱面构图，不与左侧操作争夺注意。
      canvas.drawCircle(
        Offset(size.width * .91, size.height * 1.18),
        size.height * .45,
        Paint()..color = depth,
      );
    } else {
      final cloud = Paint()..color = Color.lerp(base, foreground, .035)!;
      final radius = size.width / 7;
      for (var i = -1; i < 8; i++) {
        canvas.drawCircle(
          Offset(
            i * radius * 1.6,
            size.height + radius * .45 + math.sin(phase + i) * 2,
          ),
          radius,
          cloud,
        );
      }
      // 云朵只占背景下缘，插画和正文保留完整的干净阅读区。
      canvas.drawOval(
        Rect.fromLTWH(
          -size.width * .25,
          -size.height * .35,
          size.width * .9,
          size.height * .8,
        ),
        Paint()..color = depth.withValues(alpha: .25),
      );
    }
  }

  @override
  bool shouldRepaint(PlayfulHeroPainter oldDelegate) =>
      oldDelegate.space != space ||
      oldDelegate.base != base ||
      oldDelegate.depth != depth ||
      oldDelegate.foreground != foreground ||
      oldDelegate.motion != motion;
}
