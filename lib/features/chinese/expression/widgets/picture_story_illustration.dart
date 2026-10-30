import 'package:flutter/material.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';

class PictureStoryIllustration extends StatelessWidget {
  const PictureStoryIllustration({
    super.key,
    required this.kind,
    this.borderRadius,
  });

  final String kind;

  /// 默认使用卡片圆角；贴边嵌入外层卡片时可设为零，由外层统一裁切。
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius:
            borderRadius ?? BorderRadius.circular(SpacingTokens.radiusMedium),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: CustomPaint(
            painter: _ScenePainter(kind: kind, scheme: theme.colorScheme),
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter({required this.kind, required this.scheme});

  final String kind;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()..color = scheme.surfaceContainerHighest;
    final ground = Paint()..color = scheme.secondaryContainer;
    canvas.drawRect(Offset.zero & size, sky);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * .66, size.width, size.height * .34),
      ground,
    );
    switch (kind) {
      case 'umbrella':
        _paintUmbrella(canvas, size);
      case 'toys':
        _paintToys(canvas, size);
      default:
        _paintKite(canvas, size);
    }
  }

  void _paintKite(Canvas canvas, Size size) {
    final person = Paint()..color = scheme.primary;
    canvas.drawCircle(
      Offset(size.width * .35, size.height * .45),
      size.width * .06,
      person,
    );
    canvas.drawLine(
      Offset(size.width * .35, size.height * .51),
      Offset(size.width * .35, size.height * .72),
      person..strokeWidth = 7,
    );
    canvas.drawLine(
      Offset(size.width * .35, size.height * .58),
      Offset(size.width * .22, size.height * .67),
      person..strokeWidth = 5,
    );
    canvas.drawLine(
      Offset(size.width * .35, size.height * .58),
      Offset(size.width * .48, size.height * .66),
      person..strokeWidth = 5,
    );
    final kite = Paint()..color = scheme.tertiary;
    final path = Path()
      ..moveTo(size.width * .72, size.height * .18)
      ..lineTo(size.width * .84, size.height * .31)
      ..lineTo(size.width * .72, size.height * .44)
      ..lineTo(size.width * .60, size.height * .31)
      ..close();
    canvas.drawPath(path, kite);
    canvas.drawLine(
      Offset(size.width * .72, size.height * .44),
      Offset(size.width * .42, size.height * .63),
      Paint()
        ..color = scheme.onSurfaceVariant
        ..strokeWidth = 2,
    );
  }

  void _paintUmbrella(Canvas canvas, Size size) {
    final rain = Paint()
      ..color = scheme.primary.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    for (var i = 0; i < 10; i++) {
      final x = size.width * (.08 + i * .095);
      canvas.drawLine(
        Offset(x, size.height * .08),
        Offset(x - 10, size.height * .28),
        rain,
      );
    }
    final umbrella = Paint()..color = scheme.primary;
    final center = Offset(size.width * .42, size.height * .42);
    canvas.drawArc(
      Rect.fromCenter(
        center: center,
        width: size.width * .54,
        height: size.height * .42,
      ),
      3.14,
      3.14,
      true,
      umbrella,
    );
    canvas.drawLine(
      center,
      Offset(size.width * .42, size.height * .72),
      umbrella..strokeWidth = 5,
    );
    canvas.drawCircle(Offset(size.width * .42, size.height * .72), 9, umbrella);
    final door = Paint()..color = scheme.tertiaryContainer;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .68,
        size.height * .45,
        size.width * .20,
        size.height * .35,
      ),
      door,
    );
    canvas.drawCircle(
      Offset(size.width * .35, size.height * .75),
      size.width * .045,
      Paint()..color = scheme.secondary,
    );
  }

  void _paintToys(Canvas canvas, Size size) {
    final box = Paint()..color = scheme.tertiaryContainer;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .56,
          size.height * .52,
          size.width * .26,
          size.height * .25,
        ),
        const Radius.circular(12),
      ),
      box,
    );
    final ball = Paint()..color = scheme.tertiary;
    canvas.drawCircle(
      Offset(size.width * .25, size.height * .62),
      size.width * .08,
      ball,
    );
    final cube = Paint()..color = scheme.primary;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .36,
        size.height * .61,
        size.width * .12,
        size.width * .12,
      ),
      cube,
    );
    final child = Paint()..color = scheme.secondary;
    canvas.drawCircle(
      Offset(size.width * .28, size.height * .38),
      size.width * .055,
      child,
    );
    canvas.drawLine(
      Offset(size.width * .28, size.height * .44),
      Offset(size.width * .36, size.height * .63),
      child..strokeWidth = 6,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.scheme != scheme;
}
