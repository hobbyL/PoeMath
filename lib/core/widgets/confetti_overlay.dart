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
  CelebrationController({this.duration = const Duration(milliseconds: 2500)});

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
    Color(0xFFFF9800), // 橙色
    Color(0xFFE91E63), // 粉色
    Color(0xFF4CAF50), // 绿色
    Color(0xFF2196F3), // 蓝色
    Color(0xFF9C27B0), // 紫色
    Color(0xFFFF5252), // 红色
    Color(0xFF00BCD4), // 青色
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
    final durationSec = widget.controller.duration.inMilliseconds / 1000.0;

    _particles = List.generate(80, (_) {
      // 从屏幕中下方两个发射点喷出（左右各一个，模拟烟花）
      final isLeft = _random.nextBool();
      final startX = isLeft
          ? 0.15 + _random.nextDouble() * 0.15 // 左侧 15%-30%
          : 0.55 + _random.nextDouble() * 0.15; // 右侧 55%-70%

      // 向上喷射的速度
      final upSpeed = 300 + _random.nextDouble() * 350;
      // 水平散开的速度（左侧偏右、右侧偏左，形成交叉）
      final spreadAngle = isLeft
          ? 0.3 + _random.nextDouble() * 1.0 // 向右偏
          : -0.3 - _random.nextDouble() * 1.0; // 向左偏
      final hSpeed = spreadAngle * (80 + _random.nextDouble() * 120);

      // 延迟出发：0 ~ 25% 的动画时长内交错发射
      final delay = _random.nextDouble() * 0.25;

      // 左右飘摆的频率和幅度
      final swayFreq = 1.5 + _random.nextDouble() * 2.5;
      final swayAmp = 15 + _random.nextDouble() * 30;

      return _Particle(
        startX: startX,
        startY: 0.65 + _random.nextDouble() * 0.1, // 从 65%-75% 高度发射
        vx: hSpeed,
        vy: -upSpeed, // 向上（负值）
        size: 4.0 + _random.nextDouble() * 7,
        color: _colors[_random.nextInt(_colors.length)],
        rotation: _random.nextDouble() * 2 * pi,
        rotationSpeed: (_random.nextDouble() - 0.5) * 8,
        shape: _random.nextInt(3),
        delay: delay,
        swayFreq: swayFreq,
        swayAmp: swayAmp,
        durationSec: durationSec,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
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
      ),
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
    required this.delay,
    required this.swayFreq,
    required this.swayAmp,
    required this.durationSec,
  });

  final double startX; // 0~1 比例
  final double startY;
  final double vx; // 像素/秒
  final double vy; // 负值 = 向上
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;
  final int shape; // 0=圆, 1=方, 2=星
  final double delay; // 0~1 延迟发射比例
  final double swayFreq; // 左右摇摆频率 (Hz)
  final double swayAmp; // 左右摇摆幅度 (px)
  final double durationSec;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_Particle> particles;
  final double progress;

  // 较轻的重力，让粒子飘得更久
  static const _gravity = 280.0; // 像素/秒²

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // 尚未发射
      if (progress < p.delay) continue;

      // 粒子自身时间（减去延迟）
      final localProgress = (progress - p.delay) / (1.0 - p.delay);
      final t = localProgress * p.durationSec;

      // 抛物线运动 + 正弦摇摆
      final x = p.startX * size.width + p.vx * t + p.swayAmp * sin(p.swayFreq * t * 2 * pi);
      final y = p.startY * size.height + p.vy * t + 0.5 * _gravity * t * t;

      // 超出画布则跳过
      if (y > size.height + 20 || x < -20 || x > size.width + 20) continue;

      // 淡入（前 10%）+ 淡出（后 35%）
      double opacity;
      if (localProgress < 0.1) {
        opacity = localProgress / 0.1;
      } else if (localProgress > 0.65) {
        opacity = ((1.0 - localProgress) / 0.35).clamp(0.0, 1.0);
      } else {
        opacity = 1.0;
      }

      // 尺寸缩小：后 40% 逐渐缩小
      final scale = localProgress > 0.6
          ? 1.0 - (localProgress - 0.6) / 0.4 * 0.5
          : 1.0;

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + p.rotationSpeed * t);
      canvas.scale(scale);

      switch (p.shape) {
        case 0: // 圆形
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
        case 1: // 长条纸片（旋转的矩形）
          final rect = Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.4,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(p.size * 0.1)),
            paint,
          );
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
