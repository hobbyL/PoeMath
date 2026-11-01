import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';

class PictureStoryManagementPage extends ConsumerStatefulWidget {
  const PictureStoryManagementPage({super.key});

  @override
  ConsumerState<PictureStoryManagementPage> createState() =>
      _PictureStoryManagementPageState();
}

class _PictureStoryManagementPageState
    extends ConsumerState<PictureStoryManagementPage> {
  final _savingIds = <String>{};

  Future<void> _toggle(
    PictureStoryRepository repository,
    String id,
    bool enabled,
  ) async {
    if (_savingIds.contains(id)) return;
    setState(() => _savingIds.add(id));
    try {
      await repository.setEnabled(id, enabled);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '题目启用设置保存失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        final message =
            error is ParentAccessDenied ? error.toString() : '启用设置没有保存，请重试';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _savingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    const previewWidth = SpacingTokens.xxl + SpacingTokens.md;
    final theme = Theme.of(context);
    final repository = ref.watch(pictureStoryRepositoryProvider);
    final List<PictureStoryPrompt> prompts;
    final Set<String> enabledIds;
    try {
      prompts = ref.watch(pictureStoryCatalogProvider);
      enabledIds =
          ref.watch(pictureStoryPromptProvider).map((p) => p.id).toSet();
    } on Object {
      return Scaffold(
        appBar: AppBar(title: const Text('看图说话题库')),
        body: PictureStoryUnavailableView(
          message: '本地题库暂时无法读取，已保存内容仍保留。请重试或恢复有效备份。',
          onRetry: () => ref.invalidate(pictureStoryCatalogProvider),
        ),
      );
    }
    final tiles = [
      for (final prompt in prompts)
        AppTile(
          key: ValueKey(prompt.id),
          leadingEdgeWidth: previewWidth,
          leading: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: previewWidth,
              child: PictureStoryImageView(
                image: prompt.image,
                preview: true,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          iconColor: theme.colorScheme.primary,
          title: prompt.title,
          subtitle: [
            prompt.levelLabel,
            if (prompt.theme.isNotEmpty) prompt.theme,
          ].join(' · '),
          onTap: () => context.push(AppRoutes.pictureStoryDetailOf(prompt.id)),
          allowTapWithTrailing: true,
          trailing: Semantics(
            label: '启用${prompt.title}',
            child: Switch(
              value: enabledIds.contains(prompt.id),
              onChanged: _savingIds.contains(prompt.id)
                  ? null
                  : (enabled) => _toggle(repository, prompt.id, enabled),
            ),
          ),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('看图说话题库'),
        actions: [
          IconButton(
            tooltip: '新增题目',
            icon: const Icon(Icons.add),
            onPressed: () => context.push(AppRoutes.pictureStoryCreate),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = ResponsiveLayout.columns(constraints.maxWidth);
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                if (tiles.isEmpty)
                  ColoredCard(
                    color: theme.colorScheme.primary,
                    child: const Text('题库里还没有题目，点击右上角「新增题目」添加。'),
                  ),
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
