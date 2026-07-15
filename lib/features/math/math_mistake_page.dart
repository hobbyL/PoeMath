// lib/features/math/math_mistake_page.dart
//
// 错题本页面：展示错题列表，点击跳转详情页。
// 宽屏支持多列布局。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';

class MathMistakePage extends ConsumerWidget {
  const MathMistakePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mistakes = ref.watch(mathMistakesProvider);
    final theme = Theme.of(context);

    final resolvedCount = mistakes.where((m) => m.isResolved).length;
    final unresolvedCount = mistakes.length - resolvedCount;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _responsiveColumns(constraints.maxWidth);

          return mistakes.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('错题本（${mistakes.length}）'),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 64,
                              color:
                                  theme.semantic.success.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: SpacingTokens.md),
                            Text(
                              '暂无错题，继续保持！',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('错题本（${mistakes.length}）'),
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
                        child: ColoredCard(
                          color: theme.colorScheme.primary,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatBadge(
                                label: '总错题',
                                value: '${mistakes.length}',
                                color: theme.colorScheme.primary,
                              ),
                              _StatBadge(
                                label: '待复练',
                                value: '$unresolvedCount',
                                color: theme.colorScheme.error,
                              ),
                              _StatBadge(
                                label: '已掌握',
                                value: '$resolvedCount',
                                color: theme.semantic.success,
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.1, end: 0, duration: 400.ms),
                      ),
                    ),

                    // 错题重练按钮（有未掌握错题时显示）
                    if (unresolvedCount > 0)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            SpacingTokens.md,
                            SpacingTokens.sm,
                            SpacingTokens.md,
                            0,
                          ),
                          child: FilledButton.icon(
                            onPressed: () => _startBatchRepractice(
                              context,
                              ref,
                              mistakes
                                  .where((m) => !m.isResolved)
                                  .toList(),
                            ),
                            icon: const Icon(Icons.replay_rounded),
                            label: Text('重练全部未掌握（$unresolvedCount 题）'),
                            style: FilledButton.styleFrom(
                              minimumSize:
                                  const Size(double.infinity, 48),
                            ),
                          ),
                        ),
                      ),

                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.md,
                        vertical: SpacingTokens.sm,
                      ),
                      sliver: SliverList.builder(
                        itemCount:
                            (mistakes.length + columns - 1) ~/ columns,
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
                            if (idx < mistakes.length) {
                              final mistake = mistakes[idx];
                              rowWidgets.add(
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => context.push(
                                      AppRoutes.mathMistakeDetail,
                                      extra: mistake.id,
                                    ),
                                    child: _MistakeCard(mistake: mistake),
                                  )
                                      .animate()
                                      .fadeIn(
                                        delay: (80 * idx).ms,
                                        duration: 300.ms,
                                      )
                                      .slideX(
                                        begin: 0.1,
                                        end: 0,
                                        delay: (80 * idx).ms,
                                        duration: 300.ms,
                                      ),
                                ),
                              );
                            } else {
                              rowWidgets.add(const Expanded(child: SizedBox()));
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

  /// 根据可用宽度计算列数。
  static int _responsiveColumns(double width) {
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }

  /// 批量重练所有未掌握错题。
  Future<void> _startBatchRepractice(
    BuildContext context,
    WidgetRef ref,
    List<MathMistake> unresolved,
  ) async {
    var correctCount = 0;
    var totalDone = 0;

    for (final mistake in unresolved) {
      if (!context.mounted) break;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MistakeRepracticeDialog(
          problemText:
              '(${totalDone + 1}/${unresolved.length}) ${mistake.problemText}',
          correctAnswer: mistake.correctAnswer,
        ),
      );

      // 用户取消 → 退出重练
      if (result == null) break;

      totalDone++;
      if (result) {
        correctCount++;
        // 更新重练次数
        mistake.retryCount++;
        await mistake.save();
      }
    }

    if (totalDone > 0 && context.mounted) {
      ref.invalidate(mathMistakesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '重练完成：$totalDone 题中答对 $correctCount 题'
            '（正确率 ${(correctCount / totalDone * 100).round()}%）',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
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

  static const _errorTypeLabels = <String, String>{
    'carry_omission': '进位遗漏',
    'borrow_omission': '退位遗漏',
    'multiplication_table_error': '口诀错误',
    'order_of_operations_error': '运算顺序错误',
    'remainder_error': '余数错误',
    'decimal_alignment_error': '小数对位错误',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredCard(
      color: theme.colorScheme.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态标签行 — 参考 _SessionCard 的标签样式
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: SpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: (mistake.isResolved
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(SpacingTokens.radiusSmall),
                ),
                child: Text(
                  mistake.isResolved ? '已掌握' : '待复练',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: mistake.isResolved
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (mistake.errorType != null) ...[
                const SizedBox(width: SpacingTokens.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm,
                    vertical: SpacingTokens.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary
                        .withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(SpacingTokens.radiusSmall),
                  ),
                  child: Text(
                    _errorTypeLabels[mistake.errorType] ??
                        mistake.errorType!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),

          const SizedBox(height: SpacingTokens.sm),

          // 题目行
          Text(
            mistake.problemText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: SpacingTokens.xs),

          // 答案行
          Row(
            children: [
              Text(
                '你的答案：',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                mistake.userAnswer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Text(
                '正确答案：',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                mistake.correctAnswer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
