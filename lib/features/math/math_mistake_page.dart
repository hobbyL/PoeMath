// lib/features/math/math_mistake_page.dart
//
// 错题本页面：展示错题列表，点击跳转详情页。
// 支持按年级/状态筛选，宽屏支持多列布局。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/mistake_consolidation_labels.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';
import 'package:poemath/math_engine/diagnostics/error_cause_labels.dart';
import 'package:poemath/core/utils/responsive_layout.dart';

class MathMistakePage extends ConsumerStatefulWidget {
  const MathMistakePage({super.key});

  @override
  ConsumerState<MathMistakePage> createState() => _MathMistakePageState();
}

class _MathMistakePageState extends ConsumerState<MathMistakePage> {
  bool _batchRunning = false;

  @override
  Widget build(BuildContext context) {
    final allMistakes = ref.watch(mathMistakesProvider);
    final filteredMistakes = ref.watch(filteredMistakesProvider);
    final gradeFilter = ref.watch(mistakeGradeFilterProvider);
    final statusFilter = ref.watch(mistakeStatusFilterProvider);
    final repracticeQueue = ref.watch(repracticeQueueProvider);
    final theme = Theme.of(context);

    final resolvedCount = allMistakes.where((m) => m.isResolved).length;
    final consolidatingCount = allMistakes
        .where((m) => m.isConsolidating)
        .length;
    final unmasteredCount = allMistakes.where((m) => m.isUnmastered).length;

    // 收集所有错题中出现的年级，用于筛选 chips
    final availableGrades = <int>{};
    for (final m in allMistakes) {
      availableGrades.add(m.grade);
    }
    final sortedGrades = availableGrades.toList()..sort();

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = ResponsiveLayout.columns(constraints.maxWidth);

          return allMistakes.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('错题本（${allMistakes.length}）'),
                    ),
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppEmptyState(
                        icon: Icons.check_circle_outline,
                        title: '暂无错题，继续保持！',
                        description: '练习中需要复习的错题会保存在这里。',
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('错题本（${allMistakes.length}）'),
                    ),

                    // 统计概览 — 使用 primary 色突出主题差异
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SpacingTokens.md,
                          SpacingTokens.sm,
                          SpacingTokens.md,
                          0,
                        ),
                        child:
                            ColoredCard(
                                  color: theme.colorScheme.primary,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _StatBadge(
                                        label: '总错题',
                                        value: '${allMistakes.length}',
                                        color: theme.colorScheme.primary,
                                      ),
                                      _StatBadge(
                                        label: '未掌握',
                                        value: '$unmasteredCount',
                                        color: theme.colorScheme.error,
                                      ),
                                      _StatBadge(
                                        label: '待巩固',
                                        value: '$consolidatingCount',
                                        color: theme.semantic.caution,
                                      ),
                                      _StatBadge(
                                        label: '已掌握',
                                        value: '$resolvedCount',
                                        color: theme.semantic.success,
                                      ),
                                    ],
                                  ),
                                )
                                .animatePage(context)
                                .fadeIn(duration: 400.ms)
                                .slideY(begin: 0.1, end: 0, duration: 400.ms),
                      ),
                    ),

                    // 筛选行
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SpacingTokens.md,
                          SpacingTokens.sm,
                          SpacingTokens.md,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 年级筛选
                            if (sortedGrades.length > 1)
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Text(
                                      '年级',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(width: SpacingTokens.sm),
                                    FilterChip(
                                      label: const Text('全部'),
                                      selected: gradeFilter == null,
                                      onSelected: (_) {
                                        ref
                                                .read(
                                                  mistakeGradeFilterProvider
                                                      .notifier,
                                                )
                                                .state =
                                            null;
                                      },
                                    ),
                                    for (final g in sortedGrades) ...[
                                      const SizedBox(width: SpacingTokens.xs),
                                      FilterChip(
                                        label: Text('$g年级'),
                                        selected: gradeFilter == g,
                                        onSelected: (_) {
                                          ref
                                              .read(
                                                mistakeGradeFilterProvider
                                                    .notifier,
                                              )
                                              .state = gradeFilter == g
                                              ? null
                                              : g;
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                            const SizedBox(height: SpacingTokens.xs),

                            // 状态筛选
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Text(
                                    '状态',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(width: SpacingTokens.sm),
                                  ChoiceChip(
                                    label: const Text('全部'),
                                    selected: statusFilter == null,
                                    onSelected: (_) {
                                      ref
                                              .read(
                                                mistakeStatusFilterProvider
                                                    .notifier,
                                              )
                                              .state =
                                          null;
                                    },
                                  ),
                                  for (final filter
                                      in MistakeStatusFilter.values) ...[
                                    const SizedBox(width: SpacingTokens.xs),
                                    ChoiceChip(
                                      label: Text(_statusFilterLabel(filter)),
                                      selected: statusFilter == filter,
                                      onSelected: (_) {
                                        ref
                                            .read(
                                              mistakeStatusFilterProvider
                                                  .notifier,
                                            )
                                            .state = statusFilter == filter
                                            ? null
                                            : filter;
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 重练按钮：未掌握 + 今日到期的巩固抽查
                    if (repracticeQueue.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            SpacingTokens.md,
                            SpacingTokens.sm,
                            SpacingTokens.md,
                            0,
                          ),
                          child: FilledButton.icon(
                            onPressed: _batchRunning
                                ? null
                                : () => _startBatchRepractice(repracticeQueue),
                            icon: const Icon(Icons.replay_rounded),
                            label: Text('开始重练（${repracticeQueue.length} 题）'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ),
                      ),

                    // 筛选结果为空提示
                    if (filteredMistakes.isEmpty && allMistakes.isNotEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppEmptyState(
                          icon: Icons.filter_alt_outlined,
                          title: '当前筛选条件下无错题',
                          description: '试试其他年级或掌握状态。',
                        ),
                      ),

                    if (filteredMistakes.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.md,
                          vertical: SpacingTokens.sm,
                        ),
                        sliver: SliverList.builder(
                          itemCount:
                              (filteredMistakes.length + columns - 1) ~/
                              columns,
                          itemBuilder: (context, rowIndex) {
                            final start = rowIndex * columns;
                            final rowWidgets = <Widget>[];
                            for (int col = 0; col < columns; col++) {
                              if (col > 0) {
                                rowWidgets.add(
                                  const SizedBox(width: SpacingTokens.sm),
                                );
                              }
                              final idx = start + col;
                              if (idx < filteredMistakes.length) {
                                final mistake = filteredMistakes[idx];
                                rowWidgets.add(
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => context.push(
                                        AppRoutes.mathMistakeDetail,
                                        extra: mistake.id,
                                      ),
                                      child: _MistakeCard(mistake: mistake),
                                    ).animateListItem(context, index: idx),
                                  ),
                                );
                              } else {
                                rowWidgets.add(
                                  const Expanded(child: SizedBox()),
                                );
                              }
                            }
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: SpacingTokens.sm,
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: rowWidgets,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
        },
      ),
    );
  }

  static String _statusFilterLabel(MistakeStatusFilter filter) =>
      mistakeStatusFilterLabel(filter);

  /// 批量重练：未掌握题与今日到期的巩固抽查混合，逐题走巩固状态机。
  Future<void> _startBatchRepractice(List<MathMistake> queue) async {
    if (_batchRunning) return;
    setState(() => _batchRunning = true);
    var correctCount = 0;
    var totalDone = 0;
    final repo = ref.read(mathMistakeRepoProvider);
    final batch = List<MathMistake>.of(queue);
    try {
      for (final mistake in batch) {
        if (!mounted) break;
        final result = await showMistakeRepractice(
          context,
          mistake,
          barrierDismissible: false,
          title: '再练一次 (${totalDone + 1}/${batch.length})',
        );
        if (result == null || !mounted) break;
        var saved = false;
        while (mounted && !saved) {
          try {
            final outcome = await repo.recordRepracticeResult(
              mistake.id,
              isCorrect: result,
            );
            if (outcome == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('这道错题已移除，本次重练已结束')),
                );
              }
              break;
            }
            saved = true;
            totalDone++;
            if (result) correctCount++;
            if (mounted) ref.invalidate(mathMistakesProvider);
          } on Object catch (error, stackTrace) {
            AppLogger.e(
              '批量重练结果保存失败',
              tag: 'MathMistake',
              error: error,
              stackTrace: stackTrace,
            );
            if (!mounted) break;
            final retry = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('重练结果未保存'),
                content: const Text('本题答案已保留，可以重试保存。退出将放弃本题结果，之前保存的题目不受影响。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('退出重练'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('重试保存'),
                  ),
                ],
              ),
            );
            if (retry != true) break;
          }
        }
        if (!saved) break;
      }
      if (mounted && totalDone > 0) {
        final label = totalDone == batch.length ? '重练完成' : '本次已保存';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label：$totalDone 题中答对 $correctCount 题'
              '（正确率 ${(correctCount / totalDone * 100).round()}%）',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        ref.invalidate(mathMistakesProvider);
        setState(() => _batchRunning = false);
      }
    }
  }
}

/// 统计徽章。
class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 错题卡片（固定高度，不展开）。
class _MistakeCard extends StatelessWidget {
  const _MistakeCard({required this.mistake});

  final MathMistake mistake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 三态推导单一来源：模型的 isResolved / isConsolidating / isUnmastered。
    final statusLabel = mistakeStatusLabel(mistake);
    final statusColor = mistake.isResolved
        ? theme.semantic.success
        : mistake.isConsolidating
        ? theme.semantic.caution
        : theme.colorScheme.error;

    return ColoredCard(
      color: theme.colorScheme.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mistake.isConsolidationDue || mistake.errorType != null) ...[
            Wrap(
              spacing: SpacingTokens.xs,
              runSpacing: SpacingTokens.xs,
              children: [
                // 抽查到期角标
                if (mistake.isConsolidationDue)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm,
                      vertical: SpacingTokens.xs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        SpacingTokens.radiusSmall,
                      ),
                    ),
                    child: Text(
                      '今日可练',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (mistake.errorType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm,
                      vertical: SpacingTokens.xs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        SpacingTokens.radiusSmall,
                      ),
                    ),
                    child: Text(
                      // 标签单一来源：math_engine kErrorCauseLabels；
                      // 未收录键回退显示英文原键（守卫内 errorType 非空）。
                      errorCauseLabel(mistake.errorType)!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.semantic.secondaryForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],

          // 题目行
          Align(
            alignment: Alignment.centerLeft,
            child: MathText(
              mistake.problemText,
              textAlign: TextAlign.left,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: SpacingTokens.xs),

          // 答案行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.xs,
                  ),
                  child: Wrap(
                    spacing: SpacingTokens.md,
                    runSpacing: SpacingTokens.xs,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: '你的答案：',
                          children: [
                            TextSpan(
                              text: mistake.userAnswer,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: '正确答案：',
                          children: [
                            TextSpan(
                              text: mistake.correctAnswer,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: SpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    SpacingTokens.radiusSmall,
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: SpacingTokens.xs),
              Padding(
                padding: const EdgeInsets.only(top: SpacingTokens.xs),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
