// lib/features/math/math_session_detail_page.dart
//
// 层级：features/math
// 职责：练习组详情 — 展示某次练习的所有题目及作答情况。
//       错题行可展开查看错因分析和解题步骤（与错题本一致）。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
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
      appBar: AppBar(
        title: Text('${session.grade}年级$semesterLabel · $difficultyLabel'),
      ),
      body: Column(
        children: [
          // 概要卡片
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: ColoredCard(
              color: theme.colorScheme.primary,
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryItem(
                      label: '正确率',
                      value: '$accuracyPct%',
                      color: accuracy >= 0.9
                          ? ColorTokens.success
                          : accuracy >= 0.7
                              ? ColorTokens.poemGold
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
            ),
          ).animate().fadeIn(duration: 300.ms),

          // 题目列表
          if (records.isEmpty)
            Expanded(
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
            Expanded(
              child: ListView.builder(
                itemCount: records.length,
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md,
                ),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return _ProblemRow(
                    index: index,
                    record: record,
                    sessionId: session.id,
                  )
                      .animate()
                      .fadeIn(
                        delay: (80 * index).ms,
                        duration: 300.ms,
                      )
                      .slideX(
                        begin: 0.1,
                        end: 0,
                        delay: (80 * index).ms,
                        duration: 300.ms,
                      );
                },
              ),
            ),
        ],
      ),
    );
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

/// 单题行 — 错题可展开查看错因和解题步骤。
class _ProblemRow extends ConsumerStatefulWidget {
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
  ConsumerState<_ProblemRow> createState() => _ProblemRowState();
}

class _ProblemRowState extends ConsumerState<_ProblemRow> {
  bool _expanded = false;

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
    final record = widget.record;
    final isCorrect = record.isCorrect;

    // 错题查找对应的 MathMistake（含错因、解题步骤）
    MathMistake? mistake;
    if (!isCorrect) {
      final repo = ref.watch(mathMistakeRepoProvider);
      final mistakeId = '${widget.sessionId}_${widget.index}';
      mistake = repo.getById(mistakeId);
    }

    final canExpand = !isCorrect && mistake != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: GestureDetector(
        onTap: canExpand
            ? () => setState(() => _expanded = !_expanded)
            : null,
        child: ColoredCard(
          color: isCorrect
              ? ColorTokens.success
              : theme.colorScheme.error,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 主行：序号 + 题目 + 答案
                Row(
                  children: [
                    // 序号
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: (isCorrect
                                ? ColorTokens.success
                                : theme.colorScheme.error)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${widget.index + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isCorrect
                              ? ColorTokens.success
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
                                  ? ColorTokens.success
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(width: SpacingTokens.xs),
                            Text(
                              record.userAnswer,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isCorrect
                                    ? ColorTokens.success
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        if (!isCorrect)
                          Text(
                            '正确: ${record.answerText}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ColorTokens.success,
                            ),
                          ),
                      ],
                    ),

                    // 展开箭头（仅错题）
                    if (canExpand) ...[
                      const SizedBox(width: SpacingTokens.xs),
                      Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),

                // 展开内容：错因 + 解题步骤
                if (_expanded && mistake != null) ...[
                  const Divider(height: SpacingTokens.lg),

                  // 错因标签
                  if (mistake.errorType != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: SpacingTokens.sm,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: ColorTokens.error
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            SpacingTokens.radiusSmall,
                          ),
                        ),
                        child: Text(
                          _errorTypeLabels[mistake.errorType] ??
                              mistake.errorType!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ColorTokens.error,
                          ),
                        ),
                      ),
                    ),

                  // 解题步骤
                  if (mistake.solutionStepsJson != null &&
                      mistake.solutionStepsJson!.isNotEmpty)
                    _buildSteps(context, mistake.solutionStepsJson!),

                  // 已掌握标记
                  if (mistake.isResolved)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: SpacingTokens.sm,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: ColorTokens.success,
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Text(
                            '已掌握',
                            style:
                                theme.textTheme.labelSmall?.copyWith(
                              color: ColorTokens.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (mistake.retryCount > 0) ...[
                            const SizedBox(width: SpacingTokens.sm),
                            Text(
                              '重练 ${mistake.retryCount} 次',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(
                                color: theme
                                    .colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSteps(BuildContext context, String stepsJson) {
    final theme = Theme.of(context);
    final lines = stepsJson.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '解题步骤',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        ...lines.map((line) {
          final parts = line.split('|||');
          final description = parts.isNotEmpty ? parts[0] : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Text(
                    description,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
