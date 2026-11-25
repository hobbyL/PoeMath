import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';

/// 封面上的清理标记：斜向扫帚、分开的刷毛和一颗小闪光。
/// 按钮负责点击与语义；这里只绘制随主题变化的矢量图形。
class TextbookCleanupIcon extends StatelessWidget {
  const TextbookCleanupIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconTheme = IconTheme.of(context);
    return CustomPaint(
      size: Size.square(iconTheme.size ?? SpacingTokens.lg),
      painter: _CleanupPainter(
        foreground: iconTheme.color ?? theme.colorScheme.onSurface,
        outline: theme.colorScheme.surface,
        accent: theme.colorScheme.primary,
      ),
    );
  }
}

class _CleanupPainter extends CustomPainter {
  const _CleanupPainter({
    required this.foreground,
    required this.outline,
    required this.accent,
  });

  final Color foreground;
  final Color outline;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // 图形坐标使用 24 × 24 的标准图标画布，不参与页面间距布局。
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final broom = Path()
      ..moveTo(12, 10)
      ..lineTo(18.5, 3.5)
      ..moveTo(10, 8)
      ..lineTo(14, 12)
      ..cubicTo(12.1, 13.9, 12.5, 16.4, 10.8, 19)
      ..cubicTo(7.1, 19.7, 3.7, 16.8, 3, 13.2)
      ..cubicTo(5.3, 13, 7.3, 11.1, 10, 8)
      ..close()
      ..moveTo(8.5, 9.6)
      ..lineTo(12.6, 13.6)
      ..moveTo(4.8, 16)
      ..lineTo(7, 13.8)
      ..moveTo(7.3, 18.2)
      ..lineTo(9.3, 15.6);
    final sparkle = Path()
      ..moveTo(18.2, 13.6)
      ..quadraticBezierTo(18.7, 15.6, 20.8, 16.2)
      ..quadraticBezierTo(18.7, 16.8, 18.2, 18.8)
      ..quadraticBezierTo(17.7, 16.8, 15.6, 16.2)
      ..quadraticBezierTo(17.7, 15.6, 18.2, 13.6)
      ..close();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 仅沿笔画加细轮廓，复杂封面上也能辨识，不遮盖整块图片。
    for (final path in [broom, sparkle]) {
      canvas.drawPath(
        path,
        stroke
          ..color = outline
          ..strokeWidth = 1.6 + SpacingTokens.imageIconOutline * 2,
      );
    }
    canvas.drawPath(
      broom,
      stroke
        ..color = foreground
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(
      sparkle,
      stroke
        ..color = accent
        ..strokeWidth = 1.4,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CleanupPainter oldDelegate) =>
      oldDelegate.foreground != foreground ||
      oldDelegate.outline != outline ||
      oldDelegate.accent != accent;
}
