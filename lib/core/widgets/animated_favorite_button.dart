// lib/core/widgets/animated_favorite_button.dart
//
// 层级：core/widgets
// 职责：带弹跳缩放动画的收藏/书签按钮。
//       点击收藏时图标弹跳放大再回弹，取消时仅切换图标。

import 'package:flutter/material.dart';

/// 带弹跳动画的收藏按钮。
///
/// 收藏时触发 scale 弹跳（1.0 → 1.4 → 1.0），取消收藏仅切换图标。
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  /// 记录上一次的收藏状态，用于检测「从未收藏 → 收藏」的变化。
  bool _wasFavorite = false;

  @override
  void initState() {
    super.initState();
    _wasFavorite = widget.isFavorite;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // 弹跳曲线：快速放大后弹性回弹
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
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 从未收藏变为收藏时播放弹跳动画
    if (!_wasFavorite && widget.isFavorite) {
      _controller.forward(from: 0);
    }
    _wasFavorite = widget.isFavorite;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isFavorite
        ? (widget.activeColor ?? theme.colorScheme.secondary)
        : null;

    return IconButton(
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
            widget.isFavorite ? widget.activeIcon : widget.inactiveIcon,
            key: ValueKey(widget.isFavorite),
            color: color,
          ),
        ),
      ),
    );
  }
}
