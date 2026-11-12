import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

class LearningActivityBreakdown extends StatelessWidget {
  const LearningActivityBreakdown({super.key, required this.stats});

  final List<DailyStat> stats;

  bool get hasData => stats.any(
    (day) =>
        day.textbookRecognitionCount > 0 ||
        day.textbookWritingCount > 0 ||
        day.pictureStoryExpressionCount > 0,
  );

  @override
  Widget build(BuildContext context) {
    if (!hasData) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final rows = [
      (
        label: '认一认',
        icon: Icons.spellcheck_rounded,
        count: stats.fold<int>(
          0,
          (sum, day) => sum + day.textbookRecognitionCount,
        ),
        seconds: stats.fold<int>(
          0,
          (sum, day) => sum + day.textbookRecognitionDurationSeconds,
        ),
      ),
      (
        label: '写一写',
        icon: Icons.gesture_rounded,
        count: stats.fold<int>(0, (sum, day) => sum + day.textbookWritingCount),
        seconds: stats.fold<int>(
          0,
          (sum, day) => sum + day.textbookWritingDurationSeconds,
        ),
      ),
      (
        label: '看图表达',
        icon: Icons.record_voice_over_outlined,
        count: stats.fold<int>(
          0,
          (sum, day) => sum + day.pictureStoryExpressionCount,
        ),
        seconds: stats.fold<int>(
          0,
          (sum, day) => sum + day.pictureStoryExpressionDurationSeconds,
        ),
      ),
    ];

    return ColoredCard(
      color: theme.colorScheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '课本与表达',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
              child: Row(
                children: [
                  Icon(row.icon, size: 18, color: theme.colorScheme.secondary),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(child: Text(row.label)),
                  Text('${row.count} 次'),
                  const SizedBox(width: SpacingTokens.md),
                  Text('${_minutes(row.seconds)} 分钟'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  int _minutes(int seconds) => seconds == 0 ? 0 : (seconds / 60).ceil();
}
