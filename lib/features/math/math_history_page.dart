// lib/features/math/math_history_page.dart
//
// 层级：features/math
// 职责：练习记录回顾 — 展示所有历史会话的成绩和统计。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

class MathHistoryPage extends ConsumerWidget {
  const MathHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mathSessionRepoProvider);
    final sessions = repo.getAll();
    final theme = Theme.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _responsiveColumns(constraints.maxWidth);

          return sessions.isEmpty
              ? CustomScrollView(
                  slivers: [
                    const SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('练习记录'),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: SpacingTokens.md),
                            Text(
                              '暂无练习记录',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: SpacingTokens.xs),
                            Text(
                              '完成一次口算练习后即可查看记录',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
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
                    const SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('练习记录'),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.md,
                        vertical: SpacingTokens.sm,
                      ),
                      sliver: SliverList.builder(
                        itemCount:
                            (sessions.length + columns - 1) ~/ columns,
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
                            if (idx < sessions.length) {
                              final session = sessions[idx];
                              rowWidgets.add(
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => context.push(
                                      AppRoutes.mathSessionDetail,
                                      extra: session,
                                    ),
                                    child:
                                        _SessionCard(session: session),
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
                              rowWidgets
                                  .add(const Expanded(child: SizedBox()));
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final MathSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = session.accuracy;
    final accuracyPct = (accuracy * 100).toStringAsFixed(0);

    // 颜色映射
    final accuracyColor = accuracy >= 0.9
        ? ColorTokens.success
        : accuracy >= 0.7
            ? ColorTokens.poemGold
            : theme.colorScheme.error;

    // 星星
    final stars = session.starsEarned;

    // 难度标签
    final difficultyLabel = switch (session.difficulty) {
      'easy' => '简单',
      'hard' => '困难',
      _ => '中等',
    };

    // 学期标签
    final semesterLabel = session.semester == '下' ? '下学期' : '上学期';

    // 时间格式化
    final time = session.startedAt;
    final timeStr =
        '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    // 用时格式化
    final dur = session.durationSeconds;
    final durStr = dur >= 60
        ? '${dur ~/ 60}分${dur % 60}秒'
        : '$dur秒';

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行：年级 + 时间
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm,
                    vertical: SpacingTokens.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      SpacingTokens.radiusSmall,
                    ),
                  ),
                  child: Text(
                    '${session.grade}年级$semesterLabel',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: SpacingTokens.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm,
                    vertical: SpacingTokens.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      SpacingTokens.radiusSmall,
                    ),
                  ),
                  child: Text(
                    difficultyLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  timeStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 统计行
            Row(
              children: [
                // 正确率
                _StatItem(
                  label: '正确率',
                  value: '$accuracyPct%',
                  color: accuracyColor,
                ),
                const SizedBox(width: SpacingTokens.lg),

                // 做题数
                _StatItem(
                  label: '题数',
                  value:
                      '${session.correctCount}/${session.totalProblems}',
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: SpacingTokens.lg),

                // 用时
                _StatItem(
                  label: '用时',
                  value: durStr,
                  color: theme.colorScheme.secondary,
                ),

                const Spacer(),

                // 星星
                if (stars > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      return Icon(
                        i < stars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: i < stars
                            ? ColorTokens.poemGold
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                      );
                    }),
                  ),
              ],
            ),
          ],
        ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
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
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
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
