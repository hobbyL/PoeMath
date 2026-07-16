// lib/features/poem/poem_favorites_page.dart
//
// 层级：features/poem
// 职责：诗词收藏夹 — 集中展示所有已收藏的诗词，支持宽屏多列布局。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/widgets/poem_card.dart';

class PoemFavoritesPage extends ConsumerWidget {
  const PoemFavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favRepo = ref.watch(poemFavoriteRepoProvider);
    final poemRepo = ref.watch(poemRepoProvider);
    final progressRepo = ref.watch(poemProgressRepoProvider);
    final favorites = favRepo.getAll();
    final theme = Theme.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _responsiveColumns(constraints.maxWidth);
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                title: Text('我的收藏（${favorites.length}）'),
              ),
              if (favorites.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 64,
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        Text(
                          '还没有收藏的诗词',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: SpacingTokens.xs),
                        Text(
                          '在诗词详情页点击收藏按钮即可收藏',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                    vertical: SpacingTokens.sm,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: SpacingTokens.sm,
                      crossAxisSpacing: SpacingTokens.sm,
                      mainAxisExtent: 120,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final fav = favorites[index];
                        final poem = poemRepo.getById(fav.poemId);
                        if (poem == null) return const SizedBox.shrink();

                        final progress = progressRepo.get(poem.id);
                        final status =
                            progress?.status ?? LearningStatus.notStarted;
                        final isFav = true; // 在收藏列表里一定是收藏的

                        return PoemCard(
                          poem: poem,
                          isFavorite: isFav,
                          learningStatus: status,
                          onTap: () => context
                              .push(AppRoutes.poemDetailOf(poem.id)),
                        )
                            .animate()
                            .fadeIn(
                              delay: (60 * index).ms,
                              duration: 300.ms,
                            )
                            .slideY(
                              begin: 0.05,
                              end: 0,
                              delay: (60 * index).ms,
                              duration: 300.ms,
                            );
                      },
                      childCount: favorites.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static int _responsiveColumns(double width) {
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }
}
