// lib/features/math/math_session_detail_page.dart
//
// 层级：features/math
// 职责：练习组详情 — 展示某次练习的所有题目及作答情况。
//       错题行点击可跳转错题详情页查看错因和解题步骤。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

class MathSessionDetailPage extends ConsumerWidget {
  const MathSessionDetailPage({super.key, required this.session});

  final MathSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final records = session.problemRecords;
    final accuracy = session.accuracy;
    final accuracyPct = (accuracy * 100).toStringAsFixed(0);

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
        '${time.year}/${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    // 用时格式化
    final dur = session.durationSeconds;
    final durStr =
        dur >= 60 ? '${dur ~/ 60}分${dur % 60}秒' : '$dur秒';

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _responsiveColumns(constraints.maxWidth);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                title: Text(
                  '${session.grade}年级$semesterLabel · $difficultyLabel',
                ),
              ),

              // 概要卡片
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _SummaryItem(
                          label: '正确率',
                          value: '$accuracyPct%',
                          color: accuracy >= 0.9
                              ? theme.semantic.success
                              : accuracy >= 0.7
                                  ? theme.semantic.caution
                                  : theme.colorScheme.error,
                        ),
                        _SummaryItem(
                          label: '题数',
                          value:
                              '${session.correctCount}/${session.totalProblems}',
                          color: theme.colorScheme.primary,
                        ),
                        _SummaryItem(
                          label: '用时',
                          value: durStr,
                          color: theme.colorScheme.secondary,
                        ),
                        _SummaryItem(
                          label: '时间',
                          value: timeStr,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ).animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0, duration: 400.ms),
              ),

              // 题目列表
              if (records.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '该练习无题目详情记录',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
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
                              child: _ProblemRow(
                                index: idx,
                                record: record,
                                sessionId: session.id,
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

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
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
          style: theme.textTheme.labelLarge?.copyWith(
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

/// 单题行 — 错题可点击跳转详情页。
class _ProblemRow extends ConsumerWidget {
  const _ProblemRow({
    required this.index,
    required this.record,
    required this.sessionId,
  });

  /// 0-based 索引（与错题 ID 对应）。
  final int index;
  final ProblemRecord record;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCorrect = record.isCorrect;

    // 错题查找对应的 MathMistake ID
    String? mistakeId;
    if (!isCorrect) {
      final repo = ref.watch(mathMistakeRepoProvider);
      final id = '${sessionId}_$index';
      final mistake = repo.getById(id);
      if (mistake != null) mistakeId = id;
    }

    final canNavigate = mistakeId != null;

    return GestureDetector(
      onTap: canNavigate
          ? () => context.push(
                AppRoutes.mathMistakeDetail,
                extra: mistakeId,
              )
          : null,
      child: ColoredCard(
        color: theme.colorScheme.primary,
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.sm,
        ),
        child: Row(
          children: [
            // 序号
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: (isCorrect
                        ? theme.semantic.success
                        : theme.colorScheme.error)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCorrect
                      ? theme.semantic.success
                      : theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(width: SpacingTokens.sm),

            // 题目
            Expanded(
              child: Text(
                record.problemText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 用户答案
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCorrect
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: 16,
                      color: isCorrect
                          ? theme.semantic.success
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    Text(
                      record.userAnswer,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCorrect
                            ? theme.semantic.success
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                if (!isCorrect)
                  Text(
                    '正确: ${record.answerText}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.semantic.success,
                    ),
                  ),
              ],
            ),

            // 导航箭头（仅错题且有对应记录）
            if (canNavigate) ...[
              const SizedBox(width: SpacingTokens.xs),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
