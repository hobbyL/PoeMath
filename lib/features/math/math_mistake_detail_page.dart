// lib/features/math/math_mistake_detail_page.dart
//
// 层级：features/math
// 职责：错题详情页 — 展示错题完整信息、解题步骤和操作按钮。
//       同时服务于错题本列表和练习记录详情的导航入口。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';
import 'package:poemath/math_engine/models/math_problem.dart';

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
                  MathText(
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
                        color: theme.semantic.success,
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
                        color: theme.semantic.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          SpacingTokens.radiusSmall,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: theme.semantic.success,
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Text(
                            '已掌握',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.semantic.success,
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
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),

            const SizedBox(height: SpacingTokens.md),

            // 错因标签
            if (mistake.errorType != null) ...[
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
              )
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 300.ms)
                  .slideX(begin: 0.1, end: 0, delay: 100.ms, duration: 300.ms),
              const SizedBox(height: SpacingTokens.md),
            ],

            // 解题步骤
            if (mistake.solutionStepsJson != null &&
                mistake.solutionStepsJson!.isNotEmpty)
              ColoredCard(
                color: theme.colorScheme.secondary,
                child: _buildSteps(context, mistake.solutionStepsJson!),
              )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 300.ms)
                  .slideX(
                    begin: 0.1,
                    end: 0,
                    delay: 200.ms,
                    duration: 300.ms,
                  ),

            const SizedBox(height: SpacingTokens.lg),

            // 操作按钮
            _ActionButtons(
              mistake: mistake,
              onDeleted: () => context.pop(),
            )
                .animate()
                .fadeIn(delay: 300.ms, duration: 300.ms),
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

/// 操作按钮区 — 一行展示所有按钮。
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

    return Row(
      children: [
        _buildActionButton(
          icon: Icons.replay,
          label: '再练一次',
          onTap: () => _repractice(context, ref),
          color: theme.colorScheme.primary,
        ),
        _buildActionButton(
          icon: Icons.auto_awesome,
          label: '同类新题',
          onTap: () => _generateSimilar(context, ref),
          color: theme.colorScheme.primary,
        ),
        if (!mistake.isResolved)
          _buildActionButton(
            icon: Icons.check,
            label: '已掌握',
            onTap: () async {
              final repo = ref.read(mathMistakeRepoProvider);
              await repo.resolve(mistake.id);
              ref.invalidate(mathMistakeRepoProvider);
            },
            color: theme.colorScheme.primary,
          ),
        _buildActionButton(
          icon: Icons.delete_outline,
          label: '删除',
          onTap: () async {
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
          color: theme.colorScheme.error,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.xs,
            vertical: SpacingTokens.xs,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
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
    await repo.recordRetryResult(mistake.id, isCorrect: result);

    ref.invalidate(mathMistakeRepoProvider);
  }

  void _generateSimilar(BuildContext context, WidgetRef ref) {
    final errorType = mistake.errorType;
    final grade = mistake.grade;

    // 根据错因类型选择对应的练习模式
    ProblemMode? targetMode;
    if (errorType == 'carry_omission' || errorType == 'borrow_omission') {
      // 进/退位错误 → 标准加减法
      targetMode = ProblemMode.findResult;
    } else if (errorType == 'multiplication_table') {
      // 口诀错误 → 标准乘除法
      targetMode = ProblemMode.findResult;
    } else if (errorType == 'operation_order') {
      // 运算顺序 → 连续运算
      targetMode = ProblemMode.chain;
    } else if (errorType == 'remainder_mistake') {
      // 余数错误 → 标准（含除法）
      targetMode = ProblemMode.findResult;
    }

    ref.read(mathGradeProvider.notifier).state = grade;
    ref.read(mathBatchSizeOverrideProvider.notifier).setNext(5);
    if (targetMode != null) {
      ref.read(mathPracticeModeProvider.notifier).state = targetMode;
    }

    // 显示提示
    if (errorType != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已生成针对「${_errorTypeLabel(errorType)}」的练习题',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    context.push(AppRoutes.mathPractice);
  }

  static String _errorTypeLabel(String errorType) {
    return switch (errorType) {
      'carry_omission' => '进位遗漏',
      'borrow_omission' => '退位遗漏',
      'multiplication_table' => '口诀错误',
      'operation_order' => '运算顺序',
      'remainder_mistake' => '余数错误',
      'decimal_alignment' => '小数对位',
      _ => errorType,
    };
  }
}
