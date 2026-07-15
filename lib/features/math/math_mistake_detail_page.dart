// lib/features/math/math_mistake_detail_page.dart
//
// 层级：features/math
// 职责：错题详情页 — 展示错题完整信息、解题步骤和操作按钮。
//       同时服务于错题本列表和练习记录详情的导航入口。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';

class MathMistakeDetailPage extends ConsumerWidget {
  const MathMistakeDetailPage({super.key, required this.mistakeId});

  /// 错题 ID，用于从仓库实时读取最新状态。
  final String mistakeId;

  static const _errorTypeLabels = <String, String>{
    'carry_omission': '进位遗漏',
    'borrow_omission': '退位遗漏',
    'multiplication_table_error': '口诀错误',
    'order_of_operations_error': '运算顺序错误',
    'remainder_error': '余数错误',
    'decimal_alignment_error': '小数对位错误',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(mathMistakeRepoProvider);
    final mistake = repo.getById(mistakeId);

    if (mistake == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错题详情')),
        body: const Center(child: Text('该错题已被删除')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('错题详情')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 题目卡片
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 题目文本
                  Text(
                    mistake.problemText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),

                  // 答案对比行
                  Row(
                    children: [
                      _AnswerChip(
                        label: '你的答案',
                        value: mistake.userAnswer,
                        color: theme.colorScheme.error,
                        icon: Icons.cancel_rounded,
                      ),
                      const SizedBox(width: SpacingTokens.lg),
                      _AnswerChip(
                        label: '正确答案',
                        value: mistake.correctAnswer,
                        color: ColorTokens.success,
                        icon: Icons.check_circle_rounded,
                      ),
                    ],
                  ),

                  // 已掌握标记
                  if (mistake.isResolved) ...[
                    const SizedBox(height: SpacingTokens.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.sm,
                        vertical: SpacingTokens.xs,
                      ),
                      decoration: BoxDecoration(
                        color: ColorTokens.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusSmall,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: ColorTokens.success,
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Text(
                            '已掌握',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: ColorTokens.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (mistake.retryCount > 0) ...[
                            const SizedBox(width: SpacingTokens.sm),
                            Text(
                              '重练 ${mistake.retryCount} 次',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
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

            const SizedBox(height: SpacingTokens.md),

            // 错因标签
            if (mistake.errorType != null)
              ColoredCard(
                color: theme.colorScheme.error,
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Text(
                      '错因：${_errorTypeLabels[mistake.errorType] ?? mistake.errorType!}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            if (mistake.errorType != null)
              const SizedBox(height: SpacingTokens.md),

            // 解题步骤
            if (mistake.solutionStepsJson != null &&
                mistake.solutionStepsJson!.isNotEmpty)
              ColoredCard(
                color: theme.colorScheme.secondary,
                child: _buildSteps(context, mistake.solutionStepsJson!),
              ),

            const SizedBox(height: SpacingTokens.lg),

            // 操作按钮
            _ActionButtons(
              mistake: mistake,
              onDeleted: () => context.pop(),
            ),
          ],
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
        const SizedBox(height: SpacingTokens.sm),
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
                    style: theme.textTheme.bodyMedium,
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

/// 答案展示组件。
class _AnswerChip extends StatelessWidget {
  const _AnswerChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: SpacingTokens.xs),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 操作按钮区。
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({
    required this.mistake,
    required this.onDeleted,
  });

  final MathMistake mistake;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.sm,
      children: [
        // 再练一次
        FilledButton.tonalIcon(
          onPressed: () => _repractice(context, ref),
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('再练一次'),
        ),

        // 同类新题
        FilledButton.tonalIcon(
          onPressed: () => _generateSimilar(context, ref),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('同类新题'),
        ),

        // 已掌握
        if (!mistake.isResolved)
          FilledButton.tonalIcon(
            onPressed: () async {
              final repo = ref.read(mathMistakeRepoProvider);
              await repo.resolve(mistake.id);
              ref.invalidate(mathMistakeRepoProvider);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('已掌握'),
          ),

        // 删除
        OutlinedButton.icon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除错题'),
                content: const Text('确定要删除这道错题吗？'),
                actions: [
                  TextButton(
                    onPressed: () => ctx.pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => ctx.pop(true),
                    child: Text(
                      '删除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            final repo = ref.read(mathMistakeRepoProvider);
            await repo.delete(mistake.id);
            ref.invalidate(mathMistakeRepoProvider);
            if (context.mounted) onDeleted();
          },
          icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
          label: Text(
            '删除',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }

  Future<void> _repractice(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MistakeRepracticeDialog(
        problemText: mistake.problemText,
        correctAnswer: mistake.correctAnswer,
      ),
    );

    if (result == null) return;

    final repo = ref.read(mathMistakeRepoProvider);
    await repo.incrementRetry(mistake.id);

    if (result) {
      await repo.resolve(mistake.id);
    }

    ref.invalidate(mathMistakeRepoProvider);
  }

  void _generateSimilar(BuildContext context, WidgetRef ref) {
    ref.read(mathGradeProvider.notifier).state = mistake.grade;
    ref.read(mathBatchSizeProvider.notifier).state = 5;
    context.push(AppRoutes.mathPractice);
  }
}
