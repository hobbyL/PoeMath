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

  ({String text, IconData icon}) get _grade {
    if (accuracy >= 1.0) {
      return (text: '太棒了！', icon: Icons.star_rounded);
    }
    if (accuracy >= 0.9) {
      return (text: '不错哦！', icon: Icons.thumb_up_rounded);
    }
    if (accuracy >= 0.7) {
      return (text: '继续加油！', icon: Icons.fitness_center_rounded);
    }
    return (text: '多多练习！', icon: Icons.menu_book_rounded);
  }

  bool get _allCorrect => correctCount == totalProblems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
      ),
      title: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_grade.icon, color: theme.colorScheme.primary, size: 28),
            const SizedBox(width: SpacingTokens.sm),
            Text(
              _grade.text,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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

          const SizedBox(height: SpacingTokens.lg),

          // 按钮行
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop('home'),
                  child: const Text('返回首页'),
                ),
              ),
              if (!_allCorrect) ...[
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop('review'),
                    child: const Text('查看错题'),
                  ),
                ),
              ],
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop('retry'),
                  child: const Text('再练一组'),
                ),
              ),
            ],
          ),
        ],
      ),
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
