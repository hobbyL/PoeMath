// lib/core/widgets/animated_favorite_button.dart
//
// 层级：core/widgets
// 职责：带弹跳缩放 + 粒子爆发动画的收藏/书签按钮。
//       点击收藏时图标弹跳放大，同时粒子从中心向外炸开并淡出。
//       取消收藏仅切换图标，无特效。

import 'dart:math';

import 'package:flutter/material.dart';

/// 带弹跳 + 粒子爆发动画的收藏按钮。
///
/// 收藏时触发 scale 弹跳（1.0 → 1.4 → 1.0）和粒子爆发。
/// 同时支持诗词的爱心样式和公式的书签样式。
class AnimatedFavoriteButton extends StatefulWidget {
  const AnimatedFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onToggle,
    this.activeIcon = Icons.favorite,
    this.inactiveIcon = Icons.favorite_border,
    this.activeColor,
    this.tooltip,
  });

  /// 当前是否已收藏。
  final bool isFavorite;

  /// 点击回调（外部负责切换状态和 invalidate）。
  final VoidCallback onToggle;

  /// 收藏状态图标，默认实心爱心。
  final IconData activeIcon;

  /// 未收藏状态图标，默认空心爱心。
  final IconData inactiveIcon;

  /// 收藏时的图标颜色，默认 `colorScheme.secondary`。
  final Color? activeColor;

  /// 按钮 tooltip。
  final String? tooltip;

  @override
  State<AnimatedFavoriteButton> createState() => _AnimatedFavoriteButtonState();
}

class _AnimatedFavoriteButtonState extends State<AnimatedFavoriteButton>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;
  late final AnimationController _particleController;

  /// 记录上一次的收藏状态，用于检测「从未收藏 → 收藏」的变化。
  bool _wasFavorite = false;

  /// 预生成的粒子参数（角度 + 速度 + 大小比例）。
  late final List<_ParticleData> _particles;

  static const _particleCount = 12;

  @override
  void initState() {
    super.initState();
    _wasFavorite = widget.isFavorite;

    // 弹跳动画
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 0.9)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
    ]).animate(_scaleController);

    // 粒子爆发动画
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 预生成随机粒子参数
    final rng = Random();
    _particles = List.generate(_particleCount, (_) {
      return _ParticleData(
        angle: rng.nextDouble() * 2 * pi,
        speedFactor: 0.7 + rng.nextDouble() * 0.6, // 0.7 ~ 1.3
        sizeFactor: 0.5 + rng.nextDouble() * 0.5, // 0.5 ~ 1.0
        isHeart: rng.nextDouble() < 0.35, // 35% 概率是小爱心
      );
    });
  }

  @override
  void didUpdateWidget(AnimatedFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 从未收藏变为收藏时播放动画
    if (!_wasFavorite && widget.isFavorite) {
      _scaleController.forward(from: 0);
      _particleController.forward(from: 0);
    }
    _wasFavorite = widget.isFavorite;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isFavorite
        ? (widget.activeColor ?? theme.colorScheme.secondary)
        : null;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 粒子层（在图标之下，但 overflow 可见）
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) {
                if (!_particleController.isAnimating &&
                    _particleController.value == 0) {
                  return const SizedBox.shrink();
                }
                return CustomPaint(
                  painter: _ParticleBurstPainter(
                    progress: _particleController.value,
                    color: widget.activeColor ??
                        theme.colorScheme.secondary,
                    particles: _particles,
                  ),
                );
              },
            ),
          ),

          // 图标按钮
          IconButton(
            tooltip: widget.tooltip,
            onPressed: widget.onToggle,
            icon: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                );
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Icon(
                  widget.isFavorite
                      ? widget.activeIcon
                      : widget.inactiveIcon,
                  key: ValueKey(widget.isFavorite),
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个粒子的预生成参数。
class _ParticleData {
  final double angle;
  final double speedFactor;
  final double sizeFactor;
  final bool isHeart;

  const _ParticleData({
    required this.angle,
    required this.speedFactor,
    required this.sizeFactor,
    required this.isHeart,
  });
}

/// 粒子爆发绘制器。
///
/// [progress] 0.0 → 1.0：粒子从中心向外飞散并淡出。
/// 前 60% 阶段粒子飞出，后 40% 只淡出。
class _ParticleBurstPainter extends CustomPainter {
  final double progress;
  final Color color;
  final List<_ParticleData> particles;

  _ParticleBurstPainter({
    required this.progress,
    required this.color,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 1.2; // 粒子飞出距离

    for (final p in particles) {
      // 飞出距离：先快后慢
      final distanceCurve = Curves.easeOutCubic.transform(progress);
      final distance = maxRadius * distanceCurve * p.speedFactor;

      // 透明度：前 50% 保持，后 50% 淡出
      final opacity = progress < 0.5
          ? 1.0
          : (1.0 - (progress - 0.5) * 2).clamp(0.0, 1.0);

      // 大小：先略增再缩小
      final sizeCurve = progress < 0.3
          ? 1.0 + progress * 0.5
          : (1.0 - (progress - 0.3) * 1.2).clamp(0.0, 1.5);
      final particleSize = 3.5 * p.sizeFactor * sizeCurve;

      if (opacity <= 0 || particleSize <= 0) continue;

      final dx = center.dx + cos(p.angle) * distance;
      final dy = center.dy + sin(p.angle) * distance;

      // 颜色变化：从原色到偏亮
      final particleColor = Color.lerp(
        color,
        color.withValues(alpha: 0.6),
        progress * 0.5,
      )!
          .withValues(alpha: opacity);

      final paint = Paint()
        ..color = particleColor
        ..style = PaintingStyle.fill;

      if (p.isHeart) {
        // 小爱心形状
        _drawHeart(canvas, Offset(dx, dy), particleSize * 1.2, paint);
      } else {
        // 圆形粒子
        canvas.drawCircle(Offset(dx, dy), particleSize, paint);
      }
    }
  }

  /// 绘制一个简易小爱心。
  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final x = center.dx;
    final y = center.dy;
    final s = size;

    path.moveTo(x, y + s * 0.3);
    path.cubicTo(x - s, y - s * 0.5, x - s * 0.5, y - s, x, y - s * 0.3);
    path.cubicTo(x + s * 0.5, y - s, x + s, y - s * 0.5, x, y + s * 0.3);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ParticleBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
