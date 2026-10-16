import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 练习和挑战共用的方案选择，开放范围以引擎白名单为准。
class PracticeSchemeSelector extends StatelessWidget {
  const PracticeSchemeSelector({
    super.key,
    required this.grade,
    required this.semester,
    required this.difficulty,
    required this.vertical,
    required this.onChanged,
  });

  final int grade;
  final String semester;
  final DifficultyLevel difficulty;
  final bool vertical;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = MathEngine.supportedModes(
      grade: grade,
      semester: semester,
      difficulty: difficulty,
    ).contains(ProblemMode.vertical);
    final selectedVertical = vertical && available;
    final semesterSupportsVertical = MathEngine.supportedModes(
      grade: grade,
      semester: semester,
    ).contains(ProblemMode.vertical);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('计算方案', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: [
            ChoiceChip(
              label: const Text('普通'),
              selected: !selectedVertical,
              onSelected: (_) => onChanged(false),
            ),
            if (available)
              ChoiceChip(
                label: const Text('竖式'),
                selected: selectedVertical,
                onSelected: (_) => onChanged(true),
              ),
          ],
        ),
        const SizedBox(height: SpacingTokens.sm),
        Text(
          !available
              ? (semesterSupportsVertical
                  ? '当前简单难度仅提供普通方案；中等、困难难度可选择竖式。'
                  : '当前年级学期的题库暂不提供竖式方案。')
              : selectedVertical
                  ? '按当前年级学期出加减乘竖式。两位数整数加减法逐列填写并判分，其余题目填写结果。'
                  : '使用普通题型，遵循当前年级、学期和难度，不混入竖式。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
