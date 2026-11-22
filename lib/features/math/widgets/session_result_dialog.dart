// lib/features/math/widgets/session_result_dialog.dart
//
// 练习结束弹窗：展示成绩、星星、正确率。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/adventure/adventure_artwork.dart';

class SessionResultDialog extends StatelessWidget {
  const SessionResultDialog({
    super.key,
    required this.totalProblems,
    required this.correctCount,
    required this.durationSeconds,
    required this.starsEarned,
    this.reviewLabel = '查看错题',
    this.adventureFeedback,
    this.adventureNode,
    this.adventureSouvenirs = const {},
  });

  final int totalProblems;
  final int correctCount;
  final int durationSeconds;
  final int starsEarned;
  final String reviewLabel;
  final String? adventureFeedback;
  final MathAdventureNode? adventureNode;
  final Set<MathAdventureRegion> adventureSouvenirs;

  double get accuracy => totalProblems > 0 ? correctCount / totalProblems : 0.0;

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

  bool get _allCorrect => totalProblems > 0 && correctCount == totalProblems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                Icon(_grade.icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  adventureFeedback == null
                      ? _grade.text
                      : _allCorrect
                      ? '这一站，全对通过！'
                      : '这一站还没通过',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (adventureNode case final node?) ...[
            Text(
              '${node.region.title} · ${node.skill.label}',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],
          if (_allCorrect && adventureSouvenirs.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: SpacingTokens.lg,
              runSpacing: SpacingTokens.sm,
              children: [
                for (final region in adventureSouvenirs)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdventureSouvenir(
                        region: region,
                        size: SpacingTokens.xxl * 2,
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text(region.souvenir, style: theme.textTheme.titleMedium),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
          if (adventureFeedback != null) ...[
            Text(adventureFeedback!, textAlign: TextAlign.center),
            const SizedBox(height: SpacingTokens.md),
          ],
          // 星星
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              return Icon(
                i < starsEarned
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
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

          // OverflowBar switches to a vertical layout when labels do not fit.
          OverflowBar(
            alignment: MainAxisAlignment.center,
            overflowAlignment: OverflowBarAlignment.center,
            spacing: SpacingTokens.sm,
            overflowSpacing: SpacingTokens.sm,
            children: [
              if (!_allCorrect)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop('review'),
                  child: Text(reviewLabel, textAlign: TextAlign.center),
                ),
              if (adventureFeedback != null) ...[
                if (_allCorrect) ...[
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop('retry'),
                    child: const Text('重玩这一站'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop('map'),
                    child: const Text('回到探险地图'),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('map'),
                    child: const Text('回到探险地图'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop('retry'),
                    child: const Text('再闯这一站'),
                  ),
                ],
              ] else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop('retry'),
                  child: const Text('再练一组', textAlign: TextAlign.center),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.xs,
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
