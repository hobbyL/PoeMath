import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart'
    show PictureStoryImageCleanupException;
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';

class PictureStoryDetailPage extends ConsumerStatefulWidget {
  const PictureStoryDetailPage({super.key, required this.promptId});
  final String promptId;

  @override
  ConsumerState<PictureStoryDetailPage> createState() =>
      _PictureStoryDetailPageState();
}

class _PictureStoryDetailPageState
    extends ConsumerState<PictureStoryDetailPage> {
  bool _deleting = false;

  Future<void> _delete(PictureStoryPrompt prompt) async {
    if (_deleting) return;
    final profileId = ProfileScope.currentId;
    final repository = ref.read(pictureStoryRepositoryProvider);
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('删除题目'),
          content: Text(
            '「${prompt.title}」将从所有孩子的题库中移除，并清理不再使用的题图。练习历史及其题图会保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await repository.deletePrompt(prompt: prompt, profileId: profileId);
      if (!mounted) return;
      _finishDeletion('题目已删除');
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话题目删除失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        if (error is PictureStoryImageCleanupException) {
          _finishDeletion(error.toString());
          return;
        }
        final message = switch (error) {
          ParentAccessDenied() => error.toString(),
          CacheInUseException() => '正在处理题图，请完成后再删除',
          FormatException() => error.message,
          _ => '题目没有删除，请重试',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _finishDeletion(String message) {
    final messenger = ScaffoldMessenger.of(context);
    _goBack();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.pictureStoryManagement);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    PictureStoryPrompt? prompt;
    var failed = false;
    try {
      prompt = ref.watch(pictureStoryPromptByIdProvider(widget.promptId));
    } on Object {
      failed = true;
    }
    if (prompt == null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _goBack),
          title: const Text(
            '题目详情',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: PictureStoryUnavailableView(
          message: failed ? '题目暂时无法读取，已保存内容仍保留。' : '题目不存在，请返回题库选择其他题目。',
          onRetry: failed
              ? () => ref.invalidate(pictureStoryCatalogProvider)
              : null,
        ),
      );
    }
    return PictureStorySceneScaffold(
      image: prompt.image,
      semanticLabel: '题目详情：${prompt.title}',
      onBack: _goBack,
      actions: [
        IconButton(
          tooltip: '编辑题目',
          icon: const Icon(Icons.edit_outlined),
          onPressed: _deleting
              ? null
              : () =>
                    context.push(AppRoutes.pictureStoryEditOf(widget.promptId)),
        ),
        IconButton(
          tooltip: '删除题目',
          icon: const Icon(Icons.delete_outline),
          onPressed: _deleting ? null : () => _delete(prompt!),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prompt.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  [
                    prompt.levelLabel,
                    if (prompt.theme.isNotEmpty) prompt.theme,
                  ].join(' · '),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          _section(theme, '引导问题', prompt.questions),
          const SizedBox(height: SpacingTokens.md),
          _section(theme, '观察提示', prompt.sceneFacts),
          const SizedBox(height: SpacingTokens.md),
          _section(theme, '练习目标', prompt.goals),
          const SizedBox(height: SpacingTokens.md),
          _section(theme, '参考表达', [
            if (prompt.reference.isNotEmpty) prompt.reference,
          ], numbered: false),
        ],
      ),
    );
  }

  Widget _section(
    ThemeData theme,
    String title,
    List<String> lines, {
    bool numbered = true,
  }) => ColoredCard(
    color: theme.colorScheme.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: SpacingTokens.sm),
        if (lines.isEmpty) const Text('暂未填写，可在编辑中补充'),
        for (var index = 0; index < lines.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index + 1 < lines.length ? SpacingTokens.sm : 0,
            ),
            child: Text(
              numbered ? '${index + 1}. ${lines[index]}' : lines[index],
            ),
          ),
      ],
    ),
  );
}
