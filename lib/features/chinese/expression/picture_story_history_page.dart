import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_history_prompt_card.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';

class PictureStoryHistoryPage extends ConsumerWidget {
  const PictureStoryHistoryPage({super.key, this.promptId});

  final String? promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = promptId;
    final records = id == null
        ? ref.watch(pictureStoryHistoryProvider)
        : ref.watch(pictureStoryPromptHistoryProvider(id));
    PictureStoryPrompt? headerPrompt;
    if (id != null) {
      try {
        headerPrompt = records.isEmpty
            ? ref.watch(pictureStoryPromptByIdProvider(id))
            : ref.watch(
                pictureStoryPromptVersionProvider((
                  id: id,
                  version: records.first.promptVersion,
                )),
              );
      } on Object {
        // 保留历史记录，不用当前题目替代无法读取的原版本。
      }
    }
    final empty = AppEmptyState(
      icon: Icons.history_outlined,
      title: id == null ? '还没有完成的练习' : '这道题还没有完成的练习',
      description: '完成练习后，可在这里回看表达、点评与录音。',
    );
    final content = [
      if (id != null)
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ResponsiveLayout.mediumBreakpoint,
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.md),
              child: PictureStoryHistoryPromptCard(
                prompt: headerPrompt,
                showImage: false,
              ),
            ),
          ),
        ),
      if (records.isEmpty)
        empty
      else
        LayoutBuilder(
          builder: (context, constraints) => MasonryLayout(
            columnCount: ResponsiveLayout.columns(constraints.maxWidth),
            gap: SpacingTokens.md,
            children: records.map((record) {
              PictureStoryPrompt? original;
              if (id == null) {
                try {
                  original = ref.watch(
                    pictureStoryPromptVersionProvider((
                      id: record.promptId,
                      version: record.promptVersion,
                    )),
                  );
                } on Object {
                  // 原题缺失仍可打开该次表达详情。
                }
              }
              return AppTile(
                key: ValueKey('picture-story-record-${record.id}'),
                iconColor: theme.colorScheme.primary,
                title: record.answerText.trim().isEmpty
                    ? '本次未保存表达文字'
                    : record.answerText.replaceAll(RegExp(r'\s+'), ' ').trim(),
                titleMaxLines: 2,
                subtitle: id == null ? original?.title ?? '原题版本暂时无法读取' : '',
                subtitleMaxLines: 1,
                trailingText: pictureStoryHistoryDate(record.startedAt),
                trailingTextMaxLines: null,
                onTap: () => context.push(
                  AppRoutes.pictureStoryRecordDetailOf(record.id),
                ),
              );
            }).toList(),
          ),
        ),
    ];
    if (headerPrompt != null) {
      return PictureStorySceneScaffold(
        image: headerPrompt.image,
        semanticLabel: '题目练习记录：${headerPrompt.title}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: content,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? '看图说话记录' : '题目练习记录')),
      body: records.isEmpty && id == null
          ? empty
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                children: content,
              ),
            ),
    );
  }
}
