// lib/features/math/math_tab_page.dart
//
// 层级：features/math
// 职责：口算 Tab 主页 — 年级学期选择 + 最近练习 + 错题入口。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
        leadingWidth: mistakeCount > 0 ? 100 : null,
        leading: mistakeCount > 0
            ? TextButton.icon(
                onPressed: () => context.push(AppRoutes.mathMistake),
                icon: const Icon(Icons.error_outline, size: 18),
                label: Text('错题 $mistakeCount'),
              )
            : null,
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.mathHistory),
            icon: const Icon(Icons.history_outlined),
            tooltip: '练习记录',
          ),
          TextButton.icon(
            onPressed: () =>
                _showSemesterPicker(context, ref, selectedSemester),
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(
              _semesterLabels[selectedSemester] ?? selectedSemester,
            ),
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
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),

          // 年级列表（自适应列数，高度自动撑开）
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 按 ~180px 每列计算列数，最少 2 列，最多 6 列
                  final columns = (constraints.maxWidth / 180)
                      .floor()
                      .clamp(2, 6);
                  const totalItems = 6;
                  final rows = (totalItems / columns).ceil();

                  return Column(
                    children: [
                      for (int row = 0; row < rows; row++) ...[
                        if (row > 0)
                          const SizedBox(height: SpacingTokens.sm),
                        Expanded(
                          child: Row(
                            children: [
                              for (int col = 0; col < columns; col++) ...[
                                if (col > 0)
                                  const SizedBox(
                                    width: SpacingTokens.sm,
                                  ),
                                Expanded(
                                  child: row * columns + col < totalItems
                                      ? _buildGradeCard(
                                          ref,
                                          grade: row * columns + col + 1,
                                          selectedGrade: selectedGrade,
                                          selectedSemester:
                                              selectedSemester,
                                          animIndex: row * columns + col,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),

          // 练习模式选择（比大小 / 竖式）
          _buildModeSelector(context, ref),

          // 开始练习按钮 + 限时挑战
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          context.push(AppRoutes.mathPractice),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        '开始练习 · ${GradePresets.get(selectedGrade, selectedSemester).label}',
                      ),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.push(AppRoutes.mathChallenge),
                    icon: const Icon(Icons.timer_rounded),
                    label: const Text('挑战'),
                  ),
                ],
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

  Widget _buildGradeCard(
    WidgetRef ref, {
    required int grade,
    required int selectedGrade,
    required String selectedSemester,
    required int animIndex,
  }) {
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
    )
        .animate()
        .fadeIn(
          delay: (80 * animIndex).ms,
          duration: 300.ms,
        )
        .slideX(
          begin: 0.1,
          end: 0,
          delay: (80 * animIndex).ms,
          duration: 300.ms,
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

  Widget _buildModeSelector(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedMode = ref.watch(mathPracticeModeProvider);
    final gradeConfig = ref.watch(gradeConfigProvider);

    // 只有当前年级配置支持 compare/vertical 时才显示对应选项
    final hasCompare =
        gradeConfig.allowedModes.contains(ProblemMode.compare);
    final hasVertical =
        gradeConfig.allowedModes.contains(ProblemMode.vertical);

    if (!hasCompare && !hasVertical) return const SizedBox.shrink();

    final modes = <(ProblemMode?, String, IconData)>[
      (null, '综合', Icons.shuffle_rounded),
      if (hasCompare)
        (ProblemMode.compare, '比大小', Icons.compare_arrows_rounded),
      if (hasVertical)
        (ProblemMode.vertical, '竖式', Icons.view_column_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
      child: Row(
        children: [
          Text(
            '模式',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Wrap(
              spacing: SpacingTokens.xs,
              children: modes.map((m) {
                final (mode, label, icon) = m;
                final isActive = selectedMode == mode;
                return ChoiceChip(
                  avatar: Icon(icon, size: 16),
                  label: Text(label),
                  selected: isActive,
                  onSelected: (_) {
                    ref.read(mathPracticeModeProvider.notifier).state = mode;
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
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
