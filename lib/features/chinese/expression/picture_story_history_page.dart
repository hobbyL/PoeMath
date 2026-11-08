import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_history_prompt_card.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';

class PictureStoryHistoryPage extends ConsumerStatefulWidget {
  const PictureStoryHistoryPage({super.key, this.promptId});

  final String? promptId;

  @override
  ConsumerState<PictureStoryHistoryPage> createState() =>
      _PictureStoryHistoryPageState();
}

class _PictureStoryHistoryPageState
    extends ConsumerState<PictureStoryHistoryPage> {
  final _scroll = ScrollController();
  final _recordKeys = <String, GlobalKey>{};
  double? _width;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _preserveVisibleRecord(double width) {
    if (_width != null && _width != width) {
      GlobalKey? anchor;
      var top = double.infinity;
      for (final key in _recordKeys.values) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y >= kToolbarHeight && y < top) {
          anchor = key;
          top = y;
        }
      }
      if (anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = anchor?.currentContext;
          if (mounted && context != null) {
            Scrollable.ensureVisible(context, alignment: .15);
          }
        });
      }
    }
    _width = width;
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.promptId;
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
    final storageKey = PageStorageKey('picture-story-history-${id ?? 'all'}');
    return LayoutBuilder(
      builder: (context, constraints) {
        _preserveVisibleRecord(constraints.maxWidth);
        final columns = ResponsiveLayout.columns(
          constraints.maxWidth - SpacingTokens.md * 2,
        );
        // 固定小批次在横竖屏之间保持相同的 sliver 索引，每批最多挂载 12 张卡片。
        const batchSize = 12;
        final slivers = <Widget>[
          if (id != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                child: PictureStoryHistoryPromptCard(
                  prompt: headerPrompt,
                  showImage: false,
                ),
              ),
            ),
          if (records.isEmpty)
            SliverToBoxAdapter(child: empty)
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, batch) {
                final start = batch * batchSize;
                final end = (start + batchSize).clamp(0, records.length);
                return Padding(
                  key: ValueKey('history-batch-${records[start].id}'),
                  padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                  child: MasonryLayout(
                    columnCount: columns,
                    gap: SpacingTokens.md,
                    children: [
                      for (var i = start; i < end; i++)
                        _HistoryRecordTile(
                          key: _recordKeys.putIfAbsent(
                            records[i].id,
                            GlobalKey.new,
                          ),
                          record: records[i],
                          showPrompt: id == null,
                        ),
                    ],
                  ),
                );
              }, childCount: (records.length / batchSize).ceil()),
            ),
        ];
        if (headerPrompt != null) {
          return PictureStorySceneScaffold(
            image: headerPrompt.image,
            semanticLabel: '题目练习记录：${headerPrompt.title}',
            scrollController: _scroll,
            scrollStorageKey: storageKey,
            slivers: slivers,
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(id == null ? '看图说话记录' : '题目练习记录')),
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              key: storageKey,
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  sliver: SliverMainAxisGroup(slivers: slivers),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryRecordTile extends ConsumerWidget {
  const _HistoryRecordTile({
    super.key,
    required this.record,
    required this.showPrompt,
  });
  final PictureStoryPracticeRecord record;
  final bool showPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    PictureStoryPrompt? original;
    if (showPrompt) {
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
      iconColor: Theme.of(context).colorScheme.primary,
      title: record.answerText.trim().isEmpty
          ? '本次未保存表达文字'
          : record.answerText.replaceAll(RegExp(r'\s+'), ' ').trim(),
      titleMaxLines: 2,
      subtitle: showPrompt ? original?.title ?? '原题版本暂时无法读取' : '',
      subtitleMaxLines: 1,
      trailingText: pictureStoryHistoryDate(record.startedAt),
      trailingTextMaxLines: null,
      onTap: () =>
          context.push(AppRoutes.pictureStoryRecordDetailOf(record.id)),
    );
  }
}
