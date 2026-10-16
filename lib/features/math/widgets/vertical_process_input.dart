import 'package:flutter/material.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

/// 使用练习页数字键盘填写各列，避免唤起系统键盘挤压竖式。
class VerticalProcessInput extends StatelessWidget {
  const VerticalProcessInput(
      {super.key,
      required this.problem,
      required this.attempt,
      required this.selectedField,
      required this.onSelect,});
  final MathProblem problem;
  final VerticalAttempt attempt;
  final String selectedField;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final add = problem.operators.single == Operator.add;
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('逐列过程练习'),
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            alignment: WrapAlignment.center,
            children: [
              for (final (field, title) in [
                if (VerticalAttempt.needsHundreds(problem)) ('hundreds', '百位'),
                ('tens', '十位'),
                ('ones', '个位'),
                ('regroup', add ? '个位进位' : '十位借位'),
              ])
                ChoiceChip(
                  key: ValueKey('vertical_$field'),
                  label: Text(
                      '$title：${attempt.field(field).isEmpty ? '□' : attempt.field(field)}',),
                  selected: selectedField == field,
                  onSelected: (_) => onSelect(field),
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text('${add ? '进位' : '借位'}填 1，没有填 0；点选各列后用下方键盘填写。',
              style: theme.textTheme.bodySmall,),
        ],
      ),
    );
  }
}
