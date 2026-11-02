import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';

class PictureStoryPage extends ConsumerWidget {
  const PictureStoryPage({
    super.key,
    this.navigationTitle,
    this.navigationToolbarHeight,
  });

  final Widget? navigationTitle;
  final double? navigationToolbarHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    List<PictureStoryPrompt>? prompts;
    try {
      prompts = ref.watch(pictureStoryPromptProvider);
    } on Object {
      // 保留损坏目录原值，恢复后可重试；不能误显示成空题库。
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: navigationTitle != null,
        title: navigationTitle ?? const Text('表达'),
        toolbarHeight: navigationToolbarHeight,
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.pictureStoryHistory),
            icon: const Icon(Icons.history_outlined),
            tooltip: '练习记录',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: prompts == null
            ? PictureStoryUnavailableView(
                message: '题库暂时无法读取，请家长检查题库或恢复有效备份。',
                onRetry: () => ref.invalidate(pictureStoryCatalogProvider),
              )
            : prompts.isEmpty
                ? _emptyState(context, theme)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          ResponsiveLayout.columns(constraints.maxWidth);
                      final available = prompts!;
                      return ListView(
                        padding: const EdgeInsets.all(SpacingTokens.md),
                        children: [
                          for (var start = 0;
                              start < available.length;
                              start += columns) ...[
                            if (start > 0)
                              const SizedBox(height: SpacingTokens.sm),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var column = 0;
                                      column < columns;
                                      column++) ...[
                                    if (column > 0)
                                      const SizedBox(width: SpacingTokens.sm),
                                    Expanded(
                                      child: start + column < available.length
                                          ? _PromptCard(
                                              prompt: available[start + column],
                                            )
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

  Widget _emptyState(BuildContext context, ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_search_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: SpacingTokens.md),
                const Text('暂时没有可练习的题目'),
                const SizedBox(height: SpacingTokens.xs),
                const Text('请家长在设置中添加或启用看图说话题目。', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}

class _PromptCard extends ConsumerWidget {
  const _PromptCard({required this.prompt});

  final PictureStoryPrompt prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final practiced = ref
        .watch(pictureStoryHistoryProvider)
        .where((record) => record.promptId == prompt.id)
        .isNotEmpty;
    void openPractice() =>
        context.push(AppRoutes.pictureStoryPracticeOf(prompt.id));

    return Semantics(
      label: prompt.title,
      value: practiced ? '已练习' : null,
      button: true,
      excludeSemantics: true,
      onTap: openPractice,
      child: ColoredCard(
        color: theme.colorScheme.secondary,
        padding: EdgeInsets.zero,
        onTap: openPractice,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                PictureStoryImageView(
                  image: prompt.image,
                  preview: true,
                  borderRadius: BorderRadius.zero,
                ),
                if (practiced)
                  Positioned(
                    top: SpacingTokens.sm,
                    right: SpacingTokens.sm,
                    child: Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      prompt.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
