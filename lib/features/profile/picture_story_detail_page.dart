import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';

class PictureStoryDetailPage extends ConsumerWidget {
  const PictureStoryDetailPage({super.key, required this.promptId});
  final String promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    PictureStoryPrompt? prompt;
    var failed = false;
    try {
      prompt = ref.watch(pictureStoryPromptByIdProvider(promptId));
    } on Object {
      failed = true;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('题目详情'),
        actions: [
          if (prompt != null)
            IconButton(
              tooltip: '编辑题目',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push(AppRoutes.pictureStoryEditOf(promptId)),
            ),
        ],
      ),
      body: prompt == null
          ? PictureStoryUnavailableView(
              message: failed ? '题目暂时无法读取，已保存内容仍保留。' : '题目不存在，请返回题库选择其他题目。',
              onRetry: failed
                  ? () => ref.invalidate(pictureStoryCatalogProvider)
                  : null,
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ResponsiveLayout.wideBreakpoint,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoredCard(
                          color: theme.colorScheme.primary,
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PictureStoryImageView(image: prompt.image),
                              Padding(
                                padding: const EdgeInsets.all(SpacingTokens.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prompt.title,
                                      style: theme.textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: SpacingTokens.sm),
                                    Text(
                                      [
                                        prompt.levelLabel,
                                        if (prompt.theme.isNotEmpty)
                                          prompt.theme,
                                      ].join(' · '),
                                    ),
                                  ],
                                ),
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
                        _section(
                          theme,
                          '参考表达',
                          [if (prompt.reference.isNotEmpty) prompt.reference],
                          numbered: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _section(
    ThemeData theme,
    String title,
    List<String> lines, {
    bool numbered = true,
  }) =>
      ColoredCard(
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
