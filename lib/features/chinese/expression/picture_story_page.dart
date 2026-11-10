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
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_action.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_contrast.dart';
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
            tooltip: '全部记录',
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
            ? const AppEmptyState(
                icon: Icons.image_outlined,
                title: '暂时没有可练习的题目',
                description: '请家长在设置中添加或启用看图说话题目。',
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = ResponsiveLayout.columns(
                    constraints.maxWidth,
                  );
                  final available = prompts!;
                  return ListView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: [
                      for (
                        var start = 0;
                        start < available.length;
                        start += columns
                      ) ...[
                        if (start > 0) const SizedBox(height: SpacingTokens.sm),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var column = 0;
                                column < columns;
                                column++
                              ) ...[
                                if (column > 0)
                                  const SizedBox(width: SpacingTokens.sm),
                                Expanded(
                                  child: start + column < available.length
                                      ? _PromptCard(
                                          key: ValueKey(
                                            available[start + column].id,
                                          ),
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
}

class _PromptCard extends ConsumerStatefulWidget {
  const _PromptCard({super.key, required this.prompt});

  final PictureStoryPrompt prompt;

  @override
  ConsumerState<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends ConsumerState<_PromptCard> {
  final _imageKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.prompt;
    final records = ref.watch(pictureStoryPromptHistoryProvider(prompt.id));
    final practiced = records.isNotEmpty;
    final bytes = practiced && prompt.image.isLocal
        ? ref
              .watch(pictureStoryImageBytesProvider(prompt.image.value))
              .valueOrNull
        : null;
    final pixels = !practiced || (prompt.image.isLocal && bytes == null)
        ? null
        : ref
              .watch(
                pictureStorySceneContrastProvider((
                  image: prompt.image,
                  imageBytes: bytes,
                  builtinScheme: prompt.image.isLocal
                      ? null
                      : theme.colorScheme,
                )),
              )
              .valueOrNull;
    void openPractice() =>
        context.push(AppRoutes.pictureStoryPracticeOf(prompt.id));

    return ColoredCard(
      color: theme.colorScheme.primary,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Semantics(
            label: prompt.title,
            value: practiced ? '已练习 ${records.length} 次，开始新练习' : '开始练习',
            button: true,
            excludeSemantics: true,
            onTap: openPractice,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: openPractice,
                excludeFromSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PictureStoryImageView(
                      key: _imageKey,
                      image: prompt.image,
                      preview: true,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(SpacingTokens.radiusMedium),
                      ),
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
            ),
          ),
          if (practiced)
            Positioned(
              top: SpacingTokens.sm,
              right: SpacingTokens.sm,
              child: PictureStoryImageAction(
                surfaceKey: _imageKey,
                pixels: pixels,
                child: IconButton(
                  onPressed: () => context.push(
                    AppRoutes.pictureStoryPromptHistoryOf(prompt.id),
                  ),
                  icon: const Icon(Icons.history_outlined),
                  tooltip: '练习记录 · ${records.length} 次',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
