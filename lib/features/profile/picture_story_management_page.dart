import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';

class PictureStoryManagementPage extends ConsumerWidget {
  const PictureStoryManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const previewWidth = SpacingTokens.xxl + SpacingTokens.md;
    final theme = Theme.of(context);
    final repository = ref.watch(pictureStoryRepositoryProvider);
    final prompts = ref.watch(pictureStoryCatalogProvider);
    final enabledIds = ref
        .watch(pictureStoryPromptProvider)
        .map((prompt) => prompt.id)
        .toSet();
    final tiles = [
      for (final prompt in prompts)
        AppTile(
          leadingEdgeWidth: previewWidth,
          leading: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: previewWidth,
              child: PictureStoryIllustration(
                kind: prompt.illustration,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          iconColor: theme.colorScheme.primary,
          title: prompt.title,
          subtitle: '${prompt.levelLabel} · ${prompt.theme}',
          trailing: Switch(
            value: enabledIds.contains(prompt.id),
            onChanged: (enabled) async {
              await repository.setEnabled(prompt.id, enabled);
              if (!context.mounted) return;
              ref.invalidate(pictureStoryPromptProvider);
              ref.invalidate(pictureStoryPromptCountProvider);
            },
          ),
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('看图说话题库')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = ResponsiveLayout.columns(constraints.maxWidth);
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                for (var start = 0; start < tiles.length; start += columns) ...[
                  if (start > 0) const SizedBox(height: SpacingTokens.sm),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0)
                            const SizedBox(width: SpacingTokens.sm),
                          Expanded(
                            child: start + column < tiles.length
                                ? tiles[start + column]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
