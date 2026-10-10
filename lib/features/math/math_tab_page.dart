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
import 'package:poemath/core/widgets/app_widgets.dart';
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
    final isWide = MediaQuery.sizeOf(context).width >= 420;
    final gradeLabel =
        GradePresets.get(selectedGrade, selectedSemester).label;

    return Scaffold(
      appBar: AppBar(
        title: const Text('口算练习'),
        automaticallyImplyLeading: false,
        leadingWidth: mistakeCount > 0
            ? (isWide ? 160.0 : 96.0)
            : null,
        leading: mistakeCount > 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isWide)
                    TextButton.icon(
                      onPressed: () =>
                          context.push(AppRoutes.mathMistake),
                      icon: const Icon(Icons.error_outline, size: 18),
                      label: Text('错题 $mistakeCount'),
                    )
                  else
                    IconButton(
                      onPressed: () =>
                          context.push(AppRoutes.mathMistake),
                      icon: Badge(
                        label: Text('$mistakeCount'),
                        child: const Icon(Icons.error_outline),
                      ),
                      tooltip: '错题 $mistakeCount',
                    ),
                  IconButton(
                    onPressed: () =>
                        context.push(AppRoutes.studyHub),
                    icon: const Icon(Icons.auto_stories_outlined),
                    tooltip: '公式知识库',
                  ),
                ],
              )
            : IconButton(
                onPressed: () => context.push(AppRoutes.studyHub),
                icon: const Icon(Icons.auto_stories_outlined),
                tooltip: '公式知识库',
              ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.mathHistory),
            icon: const Icon(Icons.history_outlined),
            tooltip: '练习记录',
          ),
          if (isWide)
            TextButton.icon(
              onPressed: () =>
                  _showSemesterPicker(context, ref, selectedSemester),
              icon: const Icon(Icons.filter_list, size: 18),
              label: Text(
                _semesterLabels[selectedSemester] ?? selectedSemester,
              ),
            )
          else
            IconButton(
              onPressed: () =>
                  _showSemesterPicker(context, ref, selectedSemester),
              icon: const Icon(Icons.filter_list),
              tooltip: _semesterLabels[selectedSemester] ??
                  selectedSemester,
            ),
        ],
      ),
      body: Column(
        children: [
          // 可滚动内容区（统计概览 + 年级网格）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 按 ~180px 每列计算列数，最少 2 列，最多 6 列
                final gridWidth =
                    constraints.maxWidth - SpacingTokens.md * 2;
                final columns =
                    (gridWidth / 180).floor().clamp(2, 6);
                const totalItems = 6;
                final rows = (totalItems / columns).ceil();

                return SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    bottom: SpacingTokens.md,
                  ),
                  child: Column(
                    children: [
                      // 统计概览
                      if (totalProblems > 0)
                        StatOverviewCard(
                          items: [
                            StatOverviewItem(
                              value: '$totalProblems',
                              label: '已做题',
                            ),
                            StatOverviewItem(
                              value:
                                  '${(accuracy * 100).toStringAsFixed(0)}%',
                              label: '正确率',
                            ),
                            StatOverviewItem(
                              value: '$mistakeCount',
                              label: '错题',
                            ),
                          ],
                        ),

                      // 年级网格
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.md,
                        ),
                        child: Column(
                          children: [
                            for (int row = 0; row < rows;
                                row++) ...[
                              if (row > 0)
                                const SizedBox(
                                  height: SpacingTokens.sm,
                                ),
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (int col = 0;
                                        col < columns;
                                        col++) ...[
                                      if (col > 0)
                                        const SizedBox(
                                          width: SpacingTokens.sm,
                                        ),
                                      Expanded(
                                        child: row * columns +
                                                    col <
                                                totalItems
                                            ? _buildGradeCard(
                                                ref,
                                                grade:
                                                    row * columns +
                                                        col +
                                                        1,
                                                selectedGrade:
                                                    selectedGrade,
                                                selectedSemester:
                                                    selectedSemester,
                                                animIndex:
                                                    row * columns +
                                                        col,
                                              )
                                            : const SizedBox
                                                .shrink(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 开始练习按钮 + 限时挑战
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            context.push(AppRoutes.mathPractice),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          isWide
                              ? '开始练习 · $gradeLabel'
                              : '练习 · ${gradeLabel.replaceAll('年级', '')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                    const SizedBox(width: SpacingTokens.sm),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          context.push(AppRoutes.wordProblemLibrary),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('应用题'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
