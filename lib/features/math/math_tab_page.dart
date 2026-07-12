// lib/features/math/math_tab_page.dart
//
// 层级：features/math
// 职责：口算 Tab 主页 — 年级学期选择 + 最近练习 + 错题入口。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/grade_semester_card.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class MathTabPage extends ConsumerWidget {
  const MathTabPage({super.key});

  static const _semesterLabels = {'上': '上学期', '下': '下学期'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGrade = ref.watch(mathGradeProvider);
    final selectedSemester = ref.watch(mathSemesterProvider);
    final totalProblems = ref.watch(totalProblemsCountProvider);
    final accuracy = ref.watch(overallAccuracyProvider);
    final mistakeCount = ref.watch(mistakeCountProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('口算练习'),
        actions: [
          if (mistakeCount > 0)
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.mathMistake),
              icon: const Icon(Icons.error_outline, size: 18),
              label: Text('错题 $mistakeCount'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 统计概览
          if (totalProblems > 0)
            Container(
              margin: const EdgeInsets.all(SpacingTokens.md),
              padding: const EdgeInsets.all(SpacingTokens.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ColorTokens.mathPurple.withValues(alpha: 0.15),
                    ColorTokens.mathBlue.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(SpacingTokens.radiusMedium),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(context, '$totalProblems', '已做题'),
                  Container(
                    width: 1,
                    height: 30,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.2),
                  ),
                  _buildStat(
                    context,
                    '${(accuracy * 100).toStringAsFixed(0)}%',
                    '正确率',
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.2),
                  ),
                  _buildStat(context, '$mistakeCount', '错题'),
                ],
              ),
            ),

          // 学期筛选 Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
            child: Row(
              children: _semesterLabels.entries.map((entry) {
                final isSelected = selectedSemester == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: SpacingTokens.sm),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: isSelected,
                    onSelected: (_) {
                      ref.read(mathSemesterProvider.notifier).state =
                          entry.key;
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),

          // 年级列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                final grade = index + 1;
                final config = GradePresets.get(grade, selectedSemester);
                final isSelected = selectedGrade == grade;

                return Padding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                  child: GradeSemesterCard(
                    grade: grade,
                    semester: selectedSemester,
                    label: config.label,
                    description: _configDescription(config),
                    isSelected: isSelected,
                    onTap: () {
                      ref.read(mathGradeProvider.notifier).state = grade;
                    },
                  ),
                );
              },
            ),
          ),

          // 开始练习按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.mathPractice),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    '开始练习 · ${GradePresets.get(selectedGrade, selectedSemester).label}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: ColorTokens.mathPurple,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _configDescription(GradeConfig config) {
    final parts = <String>[];
    final ops = config.allowedOperators
        .map((o) => o.symbol)
        .join(' ');
    parts.add(ops);
    if (config.allowDecimal) parts.add('小数');
    if (config.allowFraction) parts.add('分数');
    if (config.allowNegative) parts.add('正负数');
    if (config.allowRemainder) parts.add('有余数');
    return parts.join(' · ');
  }
}
