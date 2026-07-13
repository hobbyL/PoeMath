// lib/core/widgets/celebration_dialog.dart
//
// 庆祝弹窗：打卡成功、成就解锁、等级提升时显示。
// 支持 Lottie 动画文件（assets/lottie/），未找到时自动降级为内置动画。

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 庆祝弹窗类型。
enum CelebrationType {
  checkIn(
    title: '打卡成功！',
    lottieAsset: 'assets/lottie/checkin.json',
    icon: Icons.check_circle_rounded,
    color: Color(0xFF4CAF50),
  ),
  achievement(
    title: '成就解锁！',
    lottieAsset: 'assets/lottie/achievement.json',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFFFFC107),
  ),
  levelUp(
    title: '等级提升！',
    lottieAsset: 'assets/lottie/levelup.json',
    icon: Icons.arrow_upward_rounded,
    color: Color(0xFF2196F3),
  );

  const CelebrationType({
    required this.title,
    required this.lottieAsset,
    required this.icon,
    required this.color,
  });

  final String title;
  final String lottieAsset;
  final IconData icon;
  final Color color;
}

/// 显示庆祝弹窗。
///
/// [subtitle] 可选的副标题（如成就名称、新等级名）。
/// 自动在 1.5 秒后关闭。
Future<void> showCelebration(
  BuildContext context, {
  required CelebrationType type,
  String? subtitle,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black38,
    builder: (ctx) => _CelebrationDialogContent(
      type: type,
      subtitle: subtitle,
    ),
  );
}

class _CelebrationDialogContent extends StatefulWidget {
  const _CelebrationDialogContent({
    required this.type,
    this.subtitle,
  });

  final CelebrationType type;
  final String? subtitle;

  @override
  State<_CelebrationDialogContent> createState() =>
      _CelebrationDialogContentState();
}

class _CelebrationDialogContentState extends State<_CelebrationDialogContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  bool _hasLottie = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _animController.forward();

    // 自动关闭
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.type;

    return Center(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(SpacingTokens.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius:
                  BorderRadius.circular(SpacingTokens.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: type.color.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lottie 动画或降级图标
                SizedBox(
                  height: 100,
                  width: 100,
                  child: _buildAnimation(type),
                ),
                const SizedBox(height: SpacingTokens.md),
                Text(
                  type.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: type.color,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimation(CelebrationType type) {
    if (_hasLottie) {
      return Lottie.asset(
        type.lottieAsset,
        repeat: false,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(type),
      );
    }

    // 尝试加载 Lottie，失败则用降级图标
    return Lottie.asset(
      type.lottieAsset,
      repeat: false,
      errorBuilder: (_, __, ___) => _buildFallbackIcon(type),
      onLoaded: (_) {
        if (mounted) setState(() => _hasLottie = true);
      },
    );
  }

  Widget _buildFallbackIcon(CelebrationType type) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: type.color.withValues(alpha: 0.15),
        ),
        child: Icon(
          type.icon,
          size: 60,
          color: type.color,
        ),
      ),
    );
  }
}
