import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';

/// 引导与设置共用的学习背景表单；修改仅通过回调交给调用方保存。
class LearningBackgroundFields extends StatelessWidget {
  const LearningBackgroundFields({
    super.key,
    required this.grade,
    required this.semester,
    required this.onChanged,
  });

  final int grade;
  final String semester;
  final void Function(int grade, String semester) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正在学习哪一册？', style: theme.textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.md),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            children: [
              for (var value = 1; value <= 6; value++)
                ChoiceChip(
                  label: Text('$value 年级'),
                  selected: grade == value,
                  onSelected: (_) => onChanged(value, semester),
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.sm,
            children: [
              for (final value in const ['上', '下'])
                ChoiceChip(
                  label: Text('$value学期'),
                  selected: semester == value,
                  onSelected: (_) => onChanged(grade, value),
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            '用于诗词、口算和每日推荐。临时浏览其他年级不会修改这里的选择，之后也可在设置中调整。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
