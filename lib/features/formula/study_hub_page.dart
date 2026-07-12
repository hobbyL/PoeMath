// lib/features/formula/study_hub_page.dart
//
// 层级：features/formula
// 职责：公式知识库 — 分类筛选 + 搜索 + 公式卡片列表。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/features/formula/providers/formula_providers.dart';

class StudyHubPage extends ConsumerWidget {
  const StudyHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formulas = ref.watch(filteredFormulasProvider);
    final categories = ref.watch(availableCategoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('公式知识库'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.xs,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索公式…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: SpacingTokens.sm,
                ),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(formulaSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 分类筛选
          if (categories.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.sm),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: SpacingTokens.xs),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: selectedCategory == null,
                      onSelected: (_) {
                        ref.read(selectedCategoryProvider.notifier).state =
                            null;
                      },
                    ),
                  ),
                  ...categories.map((cat) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(right: SpacingTokens.xs),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: selectedCategory == cat,
                        onSelected: (_) {
                          ref.read(selectedCategoryProvider.notifier).state =
                              selectedCategory == cat ? null : cat;
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.xs),
          ],

          // 公式列表
          Expanded(
            child: formulas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.functions_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        Text(
                          '暂无公式',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: formulas.length,
                    padding: const EdgeInsets.only(
                      bottom: 100, // 为 NotchedBottomBar 预留空间
                    ),
                    itemBuilder: (context, index) {
                      final formula = formulas[index];
                      final isFav = ref.watch(
                        isFormulaFavoriteProvider(formula.id),
                      );

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.md,
                          vertical: SpacingTokens.xs,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: ColorTokens.mathPurple
                                .withValues(alpha: 0.15),
                            child: const Icon(
                              Icons.functions,
                              color: ColorTokens.mathPurple,
                            ),
                          ),
                          title: Text(
                            formula.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            formula.formulaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            isFav
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: isFav
                                ? ColorTokens.mathYellow
                                : null,
                            size: 20,
                          ),
                          onTap: () {
                            context.push(
                              AppRoutes.formulaDetailOf(formula.id),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
