// lib/features/poem/poem_tab_page.dart
//
// 层级：features/poem
// 职责：诗词 Tab 主页 — 搜索栏 + 年级筛选 + 诗词列表。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/widgets/grade_filter_chips.dart';
import 'package:poemath/features/poem/widgets/poem_card.dart';

class PoemTabPage extends ConsumerWidget {
  const PoemTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poems = ref.watch(filteredPoemsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('诗词'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.xs,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索诗词、作者…',
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
                ref.read(poemSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: SpacingTokens.sm),
          const GradeFilterChips(),
          const SizedBox(height: SpacingTokens.xs),
          Expanded(
            child: poems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        Text(
                          '暂无诗词',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: poems.length,
                    padding: const EdgeInsets.only(
                      bottom: 100, // 为 NotchedBottomBar 预留空间
                    ),
                    itemBuilder: (context, index) {
                      final poem = poems[index];
                      final isFav =
                          ref.watch(isFavoriteProvider(poem.id));
                      return PoemCard(
                        poem: poem,
                        isFavorite: isFav,
                        onTap: () {
                          context.push(AppRoutes.poemDetailOf(poem.id));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
