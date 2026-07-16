// lib/features/math/challenge_history_page.dart
//
// 层级：features/math
// 职责：挑战记录回顾 — 展示所有历史挑战的模式、成绩和统计。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/repositories/challenge_record_repository.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

class ChallengeHistoryPage extends ConsumerWidget {
  const ChallengeHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(challengeRecordRepoProvider);
    final records = repo.getAll();
    final theme = Theme.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _responsiveColumns(constraints.maxWidth);

          return records.isEmpty
              ? CustomScrollView(
                  slivers: [
                    const SliverAppBar(
                      floating: true,
                      snap: true,
                      title: Text('挑战记录'),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: SpacingTokens.md),
                            Text(
                              '暂无挑战记录',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: SpacingTokens.xs),
                            Text(
                              '完成一次限时挑战后即可查看记录',
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
                      title: Text('挑战记录'),
                    ),
                    // 最高分汇总
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.md,
                        ),
                        child: _buildBestScores(theme, repo),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.md,
                        vertical: SpacingTokens.sm,
                      ),
                      sliver: SliverList.builder(
                        itemCount:
                            (records.length + columns - 1) ~/ columns,
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
                            if (idx < records.length) {
                              final record = records[idx];
                              rowWidgets.add(
                                Expanded(
                                  child: _RecordCard(record: record)
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

  Widget _buildBestScores(
    ThemeData theme,
    ChallengeRecordRepository repo,
  ) {
    final fixedBest = repo.bestScore('fixed');
    final extendingBest = repo.bestScore('extending');

    if (fixedBest == null && extendingBest == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Row(
        children: [
          if (fixedBest != null)
            Expanded(
              child: ColoredCard(
                color: theme.colorScheme.secondary,
                child: Column(
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      size: 20,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      '$fixedBest',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    Text(
                      '固定时间最高分',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (fixedBest != null && extendingBest != null)
            const SizedBox(width: SpacingTokens.sm),
          if (extendingBest != null)
            Expanded(
              child: ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  children: [
                    Icon(
                      Icons.add_alarm_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      '$extendingBest',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      '续命模式最高分',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final ChallengeRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = record.accuracy;
    final accuracyPct = (accuracy * 100).toStringAsFixed(0);

    // 颜色映射
    final accuracyColor = accuracy >= 0.9
        ? theme.semantic.success
        : accuracy >= 0.7
            ? theme.semantic.caution
            : theme.colorScheme.error;

    // 模式颜色
    final modeColor = record.mode == 'fixed'
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;

    // 难度标签
    final difficultyLabel = switch (record.difficulty) {
      'easy' => '简单',
      'hard' => '困难',
      _ => '中等',
    };

    // 学期标签
    final semesterLabel = record.semester == '下' ? '下学期' : '上学期';

    // 时间格式化
    final time = record.createdAt;
    final timeStr =
        '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    // 用时格式化
    final dur = record.durationSeconds;
    final durStr = dur >= 60
        ? '${dur ~/ 60}分${dur % 60}秒'
        : '$dur秒';

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：模式 + 年级 + 难度 + 时间
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.sm,
                  vertical: SpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    SpacingTokens.radiusSmall,
                  ),
                ),
                child: Text(
                  record.modeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: modeColor,
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
                  color: theme.colorScheme.primary
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    SpacingTokens.radiusSmall,
                  ),
                ),
                child: Text(
                  '${record.grade}年级$semesterLabel',
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
              // 分数
              _StatItem(
                label: '得分',
                value: '${record.score}',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: SpacingTokens.lg),

              // 答题
              _StatItem(
                label: '答题',
                value:
                    '${record.correctCount}/${record.totalAnswered}',
                color: accuracyColor,
              ),
              const SizedBox(width: SpacingTokens.lg),

              // 正确率
              _StatItem(
                label: '正确率',
                value: '$accuracyPct%',
                color: accuracyColor,
              ),
              const SizedBox(width: SpacingTokens.lg),

              // 用时
              _StatItem(
                label: '用时',
                value: durStr,
                color: theme.colorScheme.secondary,
              ),

              const Spacer(),

              // 最佳连击
              if (record.bestCombo > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 18,
                          color: theme.semantic.caution,
                        ),
                        const SizedBox(width: SpacingTokens.xs),
                        Text(
                          '${record.bestCombo}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.semantic.caution,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '最佳连击',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
