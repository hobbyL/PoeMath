// lib/features/formula/formula_detail_page.dart
//
// 公式详情页：公式展示、参数说明、记忆技巧、例题、收藏。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/formula/providers/formula_providers.dart';

class FormulaDetailPage extends ConsumerWidget {
  const FormulaDetailPage({super.key, required this.formulaId});

  final String formulaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formula = ref.watch(formulaByIdProvider(formulaId));
    final isFav = ref.watch(isFormulaFavoriteProvider(formulaId));
    final theme = Theme.of(context);

    if (formula == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('公式详情')),
        body: const Center(child: Text('公式未找到')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(formula.name),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.bookmark : Icons.bookmark_border,
              color: isFav ? theme.colorScheme.secondary : null,
            ),
            onPressed: () async {
              final repo = ref.read(formulaFavoriteRepoProvider);
              await repo.toggle(formulaId);
              ref.invalidate(isFormulaFavoriteProvider(formulaId));
            },
          ),
        ],
      ),
      body: AnimatedPageBody(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        children: [
            // 分类 + 年级标签
            Row(
              children: [
                _buildTag(context, formula.category, theme.colorScheme.primary),
                const SizedBox(width: SpacingTokens.sm),
                _buildTag(
                  context,
                  '${formula.grade}年级',
                  theme.colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 公式展示（LaTeX 渲染，解析失败时降级为纯文本）
            _buildSection(
              context,
              child: Center(
                child: formula.formulaLatex.isNotEmpty
                    ? Math.tex(
                        formula.formulaLatex,
                        textStyle: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                        onErrorFallback: (_) => Text(
                          formula.formulaText,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Text(
                        formula.formulaText,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
            ),

            // 参数说明
            if (formula.params.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(
                context,
                '参数说明',
                Icons.info_outline,
                child: Column(
                  children: formula.params.map((param) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(bottom: SpacingTokens.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${param.symbol}：',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              param.meaning,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // 记忆技巧
            if (formula.memoryTip.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(
                context,
                '记忆技巧',
                Icons.lightbulb_outline,
                child: Text(
                  formula.memoryTip,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ],

            // 例题
            if (formula.example.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(
                context,
                '例题',
                Icons.quiz_outlined,
                child: Text(
                  formula.example,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ],

            // 关联公式
            if (formula.relatedFormulas.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(
                context,
                '关联公式',
                Icons.link,
                child: Wrap(
                  spacing: SpacingTokens.sm,
                  children: formula.relatedFormulas.map((id) {
                    final related = ref.watch(formulaByIdProvider(id));
                    return ActionChip(
                      label: Text(related?.name ?? id),
                      onPressed: related != null
                          ? () {
                              // 导航到关联公式
                              Navigator.of(context).push(
                                fadeSlideRoute<void>(
                                  builder: (_) =>
                                      FormulaDetailPage(formulaId: id),
                                ),
                              );
                            }
                          : null,
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: SpacingTokens.xl),
          ],
        ),
    );
  }

  Widget _buildTag(BuildContext context, String text, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      ),
      child: child,
    );
  }

  Widget _buildLabeledSection(
    BuildContext context,
    String label,
    IconData icon, {
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          child,
        ],
      ),
    );
  }
}
