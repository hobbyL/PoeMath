// lib/core/widgets/confetti_overlay.dart
//
// 答题正确时的撒花粒子效果叠加层（自绘实现，无第三方依赖）。
// 用法：在页面 Stack 中放入此 Widget，调用 controller.play() 触发。

import 'dart:math';

import 'package:flutter/material.dart';

/// 撒花动画控制器。
///
/// 创建后调用 [play] 触发一次撒花，动画结束后自动停止。
class CelebrationController extends ChangeNotifier {
  CelebrationController({this.duration = const Duration(seconds: 2)});

  final Duration duration;
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  void play() {
    _isPlaying = true;
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    notifyListeners();
  }

  void _onComplete() {
    _isPlaying = false;
    // 不 notifyListeners，避免不必要的重建
  }
}

/// 撒花叠加层 Widget。
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.controller});

  final CelebrationController controller;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  List<_Particle> _particles = [];
  final _random = Random();

  static const _colors = [
    Color(0xFFFFC107), // 金色
    Color(0xFFFF5722), // 橙色
    Color(0xFF4CAF50), // 绿色
    Color(0xFF2196F3), // 蓝色
    Color(0xFFE91E63), // 粉色
    Color(0xFF9C27B0), // 紫色
    Color(0xFFFFEB3B), // 黄色
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: widget.controller.duration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.controller._onComplete();
        }
      });

    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _anim.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (widget.controller.isPlaying) {
      _spawnParticles();
      _anim.forward(from: 0);
    } else {
      _anim.stop();
    }
  }

  void _spawnParticles() {
    _particles = List.generate(60, (_) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 200 + _random.nextDouble() * 400;
      final size = 4.0 + _random.nextDouble() * 8;
      final rotationSpeed = (_random.nextDouble() - 0.5) * 10;
      return _Particle(
        // 从顶部中央区域发射
        startX: 0.3 + _random.nextDouble() * 0.4,
        startY: -0.05,
        vx: cos(angle) * speed * 0.5,
        vy: sin(angle).abs() * speed, // 向下
        size: size,
        color: _colors[_random.nextInt(_colors.length)],
        rotation: _random.nextDouble() * 2 * pi,
        rotationSpeed: rotationSpeed,
        shape: _random.nextInt(3), // 0=圆, 1=方, 2=星
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        if (!_anim.isAnimating && _anim.value == 0) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _anim.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  _Particle({
    required this.startX,
    required this.startY,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.shape,
  });

  final double startX; // 0~1 比例
  final double startY;
  final double vx; // 像素/秒
  final double vy;
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;
  final int shape; // 0=圆, 1=方, 2=星
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_Particle> particles;
  final double progress;

  static const _gravity = 800.0; // 像素/秒²

  @override
  void paint(Canvas canvas, Size size) {
    final duration = 2.0; // 秒
    final t = progress * duration;

    for (final p in particles) {
      final x = p.startX * size.width + p.vx * t;
      final y = p.startY * size.height + p.vy * t + 0.5 * _gravity * t * t;

      // 超出画布则跳过
      if (y > size.height + 20 || x < -20 || x > size.width + 20) continue;

      // 淡出：最后 30% 时间逐渐消失
      final opacity = progress > 0.7
          ? ((1.0 - progress) / 0.3).clamp(0.0, 1.0)
          : 1.0;

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + p.rotationSpeed * t);

      switch (p.shape) {
        case 0: // 圆形
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
        case 1: // 方形（菱形旋转）
          final rect = Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          );
          canvas.drawRect(rect, paint);
        default: // 星形
          _drawStar(canvas, p.size / 2, paint);
      }

      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, double radius, Paint paint) {
    final path = Path();
    final innerR = radius * 0.4;
    for (var i = 0; i < 10; i++) {
      final angle = (i * pi / 5) - (pi / 2);
      final r = i.isEven ? radius : innerR;
      final x = r * cos(angle);
      final y = r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
