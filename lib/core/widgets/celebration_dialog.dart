// lib/core/widgets/celebration_dialog.dart
//
// 庆祝弹窗：打卡成功、成就解锁、等级提升时显示。
// 使用 flutter_animate 实现弹入 + 光泽动画。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 庆祝弹窗类型。
enum CelebrationType {
  checkIn(
    title: '打卡成功！',
    icon: Icons.check_circle_rounded,
    color: Color(0xFF4CAF50),
  ),
  achievement(
    title: '成就解锁！',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFFFFC107),
  ),
  levelUp(
    title: '等级提升！',
    icon: Icons.arrow_upward_rounded,
    color: Color(0xFF2196F3),
  );

  const CelebrationType({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
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

class _CelebrationDialogContentState extends State<_CelebrationDialogContent> {
  @override
  void initState() {
    super.initState();
    // 自动关闭
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.type;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(SpacingTokens.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
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
              // 动画图标
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: type.color.withValues(alpha: 0.15),
                ),
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Icon(type.icon, size: 60, color: type.color),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0, 0),
                    end: const Offset(1, 1),
                    duration: 600.ms,
                    curve: Curves.elasticOut,
                  )
                  .shimmer(
                    delay: 400.ms,
                    duration: 800.ms,
                    color: type.color.withValues(alpha: 0.3),
                  ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                type.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: type.color,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
              if (widget.subtitle != null) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 400.ms, duration: 300.ms),
              ],
            ],
          ),
        ),
      )
          .animate()
          .scale(
            begin: const Offset(0.5, 0.5),
            end: const Offset(1, 1),
            duration: 400.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 300.ms),
    );
  }
}
