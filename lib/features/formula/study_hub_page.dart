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
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final theme = Theme.of(context);

    final filterLabel = selectedCategory ?? '全部';

    return Scaffold(
      appBar: AppBar(
        title: const Text('公式知识库'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                _showCategoryPicker(context, ref, selectedCategory),
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(filterLabel),
          ),
        ],
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
      body: formulas.isEmpty
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = _responsiveColumns(constraints.maxWidth);
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: SpacingTokens.sm,
                    mainAxisSpacing: SpacingTokens.sm,
                    mainAxisExtent: 80,
                  ),
                  itemCount: formulas.length,
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                    vertical: SpacingTokens.sm,
                  ).copyWith(bottom: 100),
                  itemBuilder: (context, index) {
                    final formula = formulas[index];
                    final isFav = ref.watch(
                      isFormulaFavoriteProvider(formula.id),
                    );

                    return InkWell(
                      onTap: () {
                        context.push(
                          AppRoutes.formulaDetailOf(formula.id),
                        );
                      },
                      borderRadius: BorderRadius.circular(
                        SpacingTokens.radiusMedium,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(SpacingTokens.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(
                            SpacingTokens.radiusMedium,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
                              child: Icon(
                                Icons.functions,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: SpacingTokens.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    formula.name,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    formula.formulaText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isFav
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: isFav
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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

  void _showCategoryPicker(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) {
    final categories = ref.read(availableCategoriesProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '选择分类',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<String?>(
                      groupValue: current,
                      onChanged: (v) {
                        ref.read(selectedCategoryProvider.notifier).state = v;
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RadioListTile<String?>(
                            title: Text('全部'),
                            value: null,
                          ),
                          ...categories.map((cat) {
                            return RadioListTile<String?>(
                              title: Text(cat),
                              value: cat,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }
}
