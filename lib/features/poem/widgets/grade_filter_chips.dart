// lib/features/poem/widgets/grade_filter_chips.dart
//
// 年级筛选 chip 组。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class GradeFilterChips extends ConsumerWidget {
  const GradeFilterChips({super.key});

  static const _gradeLabels = {
    1: '一年级',
    2: '二年级',
    3: '三年级',
    4: '四年级',
    5: '五年级',
    6: '六年级',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedGradeProvider);
    final grades = ref.watch(availableGradesProvider);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: SpacingTokens.xs),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: selected == null,
              onSelected: (_) {
                ref.read(selectedGradeProvider.notifier).state = null;
              },
            ),
          ),
          ...grades.map((g) {
            return Padding(
              padding: const EdgeInsets.only(right: SpacingTokens.xs),
              child: ChoiceChip(
                label: Text(_gradeLabels[g] ?? '$g 年级'),
                selected: selected == g,
                onSelected: (_) {
                  ref.read(selectedGradeProvider.notifier).state =
                      selected == g ? null : g;
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
