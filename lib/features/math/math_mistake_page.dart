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
      color: mistake.isResolved
          ? theme.semantic.success
          : theme.colorScheme.error,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题目行
          Row(
            children: [
              Expanded(
                child: Text(
                  mistake.problemText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    decoration: mistake.isResolved
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (mistake.isResolved)
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.semantic.success,
                ),
              const SizedBox(width: SpacingTokens.xs),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
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
                  color: theme.semantic.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // 错因标签
          if (mistake.errorType != null) ...[
            const SizedBox(height: SpacingTokens.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(SpacingTokens.radiusSmall),
              ),
              child: Text(
                _errorTypeLabels[mistake.errorType] ?? mistake.errorType!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
