import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/adventure/adventure_artwork.dart';
import 'package:poemath/features/math/adventure/math_adventure_page.dart';
import 'package:poemath/features/math/adventure/math_adventure_providers.dart';

class MathAdventureAlbumPage extends ConsumerWidget {
  const MathAdventureAlbumPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final records = ref.watch(mathAdventureProgressProvider);
    if (records.hasError) return adventureReadError(ref);
    final progress = records.requireValue;
    final total = progress.fold(
      0,
      (sum, item) => sum + item.collectedRegionIds.length,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('自然纪念册'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.mathAdventure);
            }
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            padding: const EdgeInsets.all(SpacingTokens.md),
            itemCount: 13,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('把发现，珍藏起来', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: SpacingTokens.sm),
                      Text(
                        '已收集 $total 件纪念物 · 属于当前学习档案',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      const Text('每走完一片区域，就留下一份自然的礼物。'),
                    ],
                  ),
                );
              }
              final grade = (index - 1) ~/ 2 + 1;
              final semester = index.isOdd ? '上' : '下';
              final collected =
                  progress
                      .where((p) => p.grade == grade && p.semester == semester)
                      .firstOrNull
                      ?.collectedRegionIds ??
                  <String>{};
              final targets = MathAdventureCatalog.collectible(grade, semester);
              final regions = MathAdventureRegion.values.where(
                (r) => targets.contains(r) || collected.contains(r.id),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$grade 年级$semester册',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    for (final region in regions)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SpacingTokens.sm,
                        ),
                        child: ColoredCard(
                          color: theme.colorScheme.primary,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AdventureSouvenir(
                                region: region,
                                collected: collected.contains(region.id),
                                size: SpacingTokens.xxl + SpacingTokens.md,
                              ),
                              const SizedBox(width: SpacingTokens.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${region.souvenir} · ${collected.contains(region.id) ? '已收集' : '待发现'}',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: SpacingTokens.xs),
                                    Text(
                                      collected.contains(region.id)
                                          ? region.story
                                          : '探索完${region.title}后，收进纪念册。',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
