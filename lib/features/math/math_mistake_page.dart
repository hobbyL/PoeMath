// lib/features/math/math_mistake_page.dart
//
// 错题本页面：展示错题列表、支持重练和删除。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';

class MathMistakePage extends ConsumerWidget {
  const MathMistakePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mistakes = ref.watch(mathMistakesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('错题本（${mistakes.length}）'),
      ),
      body: mistakes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: ColorTokens.success.withValues(alpha: 0.5),
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
            )
          : ListView.builder(
              itemCount: mistakes.length,
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemBuilder: (context, index) {
                final mistake = mistakes[index];
                return _MistakeCard(mistake: mistake)
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
    );
  }
}

class _MistakeCard extends ConsumerStatefulWidget {
  const _MistakeCard({required this.mistake});

  final MathMistake mistake;

  @override
  ConsumerState<_MistakeCard> createState() => _MistakeCardState();
}

class _MistakeCardState extends ConsumerState<_MistakeCard> {
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
    final mistake = widget.mistake;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(SpacingTokens.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
            border: mistake.isResolved
                ? Border.all(color: ColorTokens.success)
                : null,
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
                    ),
                  ),
                  if (mistake.isResolved)
                    const Icon(
                      Icons.check_circle,
                      size: 20,
                      color: ColorTokens.success,
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),

              // 答案行
              const SizedBox(height: SpacingTokens.xs),
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
                      color: ColorTokens.error,
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
                      color: ColorTokens.success,
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
                    color: ColorTokens.error.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(SpacingTokens.radiusSmall),
                  ),
                  child: Text(
                    _errorTypeLabels[mistake.errorType] ??
                        mistake.errorType!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ColorTokens.error,
                    ),
                  ),
                ),
              ],

              // 展开内容
              if (_expanded) ...[
                const Divider(height: SpacingTokens.lg),

                // 解题步骤
                if (mistake.solutionStepsJson != null &&
                    mistake.solutionStepsJson!.isNotEmpty)
                  _buildSteps(context, mistake.solutionStepsJson!),

                // 操作按钮（一行四个，图标+文字竖排）
                const SizedBox(height: SpacingTokens.md),
                Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.replay,
                      label: '再练一次',
                      onTap: () => _repractice(context),
                      color: theme.colorScheme.primary,
                    ),
                    _buildActionButton(
                      icon: Icons.auto_awesome,
                      label: '同类新题',
                      onTap: () => _generateSimilar(context),
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
                        final repo = ref.read(mathMistakeRepoProvider);
                        await repo.delete(mistake.id);
                        ref.invalidate(mathMistakeRepoProvider);
                      },
                      color: theme.colorScheme.error,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
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

  /// 再练一次：弹出对话框重新回答同一题。
  Future<void> _repractice(BuildContext context) async {
    final mistake = widget.mistake;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MistakeRepracticeDialog(
        problemText: mistake.problemText,
        correctAnswer: mistake.correctAnswer,
      ),
    );

    if (result == null) return; // 取消

    final repo = ref.read(mathMistakeRepoProvider);
    await repo.incrementRetry(mistake.id);

    if (result) {
      // 答对了，标记已解决
      await repo.resolve(mistake.id);
    }

    ref.invalidate(mathMistakeRepoProvider);
  }

  /// 生成同类新题：设置年级和学期，导航到练习页。
  void _generateSimilar(BuildContext context) {
    final mistake = widget.mistake;

    // 设置年级（从错题记录中获取）
    ref.read(mathGradeProvider.notifier).state = mistake.grade;
    // 学期默认上学期（错题不记录学期，取决于当前设置即可）
    ref.read(mathBatchSizeProvider.notifier).state = 5; // 少量同类题

    context.push(AppRoutes.mathPractice);
  }
}
