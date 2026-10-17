import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 练习和挑战共用的方案选择，开放范围以引擎白名单为准。
///
/// 用分段按钮而非 ChoiceChip：普通/竖式是**互斥的二选一**，分段按钮的
/// 连体外观能直接表达"同一维度的两个取值"，而 chip 组看起来像可多选。
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
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            // 竖式不可用时只留「普通」一段：段数随可用性变化，用户一眼
            // 看出这册次/难度下没有竖式可选，无需先点再被告知。
            segments: [
              const ButtonSegment<bool>(value: false, label: Text('普通')),
              if (available)
                const ButtonSegment<bool>(value: true, label: Text('竖式')),
            ],
            selected: {selectedVertical},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
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
