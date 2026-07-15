// lib/features/math/widgets/session_result_dialog.dart
//
// 练习结束弹窗：展示成绩、星星、正确率。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

class SessionResultDialog extends StatelessWidget {
  const SessionResultDialog({
    super.key,
    required this.totalProblems,
    required this.correctCount,
    required this.durationSeconds,
    required this.starsEarned,
  });

  final int totalProblems;
  final int correctCount;
  final int durationSeconds;
  final int starsEarned;

  double get accuracy =>
      totalProblems > 0 ? correctCount / totalProblems : 0.0;

  String get _durationText {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes > 0) return '$minutes 分 $seconds 秒';
    return '$seconds 秒';
  }

  String get _gradeText {
    if (accuracy >= 1.0) return '太棒了！🌟';
    if (accuracy >= 0.9) return '不错哦！👍';
    if (accuracy >= 0.7) return '继续加油！💪';
    return '多多练习！📚';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
      ),
      title: Center(
        child: Text(
          _gradeText,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 星星
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              return Icon(
                i < starsEarned ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 40,
                color: i < starsEarned
                    ? theme.semantic.caution
                    : theme.colorScheme.onSurfaceVariant,
              );
            }),
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 统计行
          _buildStatRow(context, '答对', '$correctCount / $totalProblems'),
          const SizedBox(height: SpacingTokens.sm),
          _buildStatRow(
            context,
            '正确率',
            '${(accuracy * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: SpacingTokens.sm),
          _buildStatRow(context, '用时', _durationText),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('review'),
          child: const Text('查看错题'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('done'),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
