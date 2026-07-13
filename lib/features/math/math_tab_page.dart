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
          TextButton.icon(
            onPressed: () =>
                _showSemesterPicker(context, ref, selectedSemester),
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(
              _semesterLabels[selectedSemester] ?? selectedSemester,
            ),
          ),
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
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                    theme.colorScheme.secondary.withValues(alpha: 0.1),
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

          // 年级列表（一行两个）
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: SpacingTokens.sm,
                mainAxisSpacing: SpacingTokens.sm,
                childAspectRatio: 2.2,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                final grade = index + 1;
                final config = GradePresets.get(grade, selectedSemester);
                final isSelected = selectedGrade == grade;

                return GradeSemesterCard(
                  grade: grade,
                  semester: selectedSemester,
                  label: config.label,
                  description: _configDescription(config),
                  isSelected: isSelected,
                  onTap: () {
                    ref.read(mathGradeProvider.notifier).state = grade;
                  },
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
            color: theme.colorScheme.primary,
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

  void _showSemesterPicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '选择学期',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<String>(
                      groupValue: current,
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(mathSemesterProvider.notifier).state = v;
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _semesterLabels.entries.map((entry) {
                          return RadioListTile<String>(
                            title: Text(entry.value),
                            value: entry.key,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }
}
