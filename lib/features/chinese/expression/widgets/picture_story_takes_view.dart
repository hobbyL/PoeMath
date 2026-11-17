import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_feedback.dart';

/// 完成页与历史详情共用口述选择、比较和每遍原话/点评。
class PictureStoryTakesView extends StatefulWidget {
  const PictureStoryTakesView({
    super.key,
    required this.record,
    required this.playingId,
    required this.onPlay,
    required this.onSelectionChanged,
  });

  final PictureStoryPracticeRecord record;
  final String? playingId;
  final ValueChanged<PictureStorySegment> onPlay;
  final VoidCallback onSelectionChanged;

  @override
  State<PictureStoryTakesView> createState() => _PictureStoryTakesViewState();
}

class _PictureStoryTakesViewState extends State<PictureStoryTakesView> {
  int? _selected;
  int? _previous;
  bool _comparing = false;

  @override
  void didUpdateWidget(PictureStoryTakesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.currentTake.id != widget.record.currentTake.id) {
      _selected = null;
      _previous = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<PictureStoryTake> takes;
    try {
      takes = widget.record.takes;
    } on Object {
      return const Text('口述版本暂时无法读取，请保留记录并稍后重试。');
    }
    final selected = (_selected ?? takes.length - 1).clamp(0, takes.length - 1);
    final previous = (_previous ?? (selected > 0 ? selected - 1 : 1)).clamp(
      0,
      takes.length - 1,
    );
    void change(VoidCallback update) {
      widget.onSelectionChanged();
      setState(update);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (takes.length > 1) ...[
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            children: [
              for (var i = 0; i < takes.length; i++)
                ChoiceChip(
                  label: Text('第 ${i + 1} 遍'),
                  selected: i == selected,
                  onSelected: (_) => change(() {
                    _selected = i;
                    if (previous == i) _previous = i == 0 ? 1 : i - 1;
                  }),
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: Icon(_comparing ? Icons.unfold_less : Icons.compare_arrows),
              label: Text(_comparing ? '收起对比' : '比较两遍表达'),
              onPressed: () => change(() => _comparing = !_comparing),
            ),
          ),
          if (_comparing) ...[
            Text('和哪一遍比较', style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.xs,
              children: [
                for (var i = 0; i < takes.length; i++)
                  if (i != selected)
                    ChoiceChip(
                      label: Text('对比第 ${i + 1} 遍'),
                      selected: previous == i,
                      onSelected: (_) => change(() => _previous = i),
                    ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final current = _take(
              context,
              takes[selected],
              selected,
              takes.length > 1,
            );
            if (!_comparing || takes.length == 1) return current;
            final prior = _take(context, takes[previous], previous, true);
            return constraints.maxWidth >= ResponsiveLayout.wideBreakpoint
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: prior),
                      const SizedBox(width: SpacingTokens.lg),
                      Expanded(child: current),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      prior,
                      const Divider(height: SpacingTokens.xl),
                      current,
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _take(
    BuildContext context,
    PictureStoryTake take,
    int index,
    bool heading,
  ) {
    final theme = Theme.of(context);
    final rawRevisions = jsonDecode(take.revisionsJson) as List;
    return Column(
      key: ValueKey('picture-story-take-${take.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading) ...[
          Text('第 ${index + 1} 遍表达', style: theme.textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.sm),
        ],
        Text(
          take.answerText.isEmpty ? '本次未保存表达文字' : take.answerText,
          style: theme.textTheme.bodyLarge,
        ),
        if (rawRevisions.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text('文字已修改，录音保留这一遍最初的口述。', style: theme.textTheme.bodySmall),
        ],
        if (take.segments.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.sm),
          for (final (i, segment) in take.segments.indexed)
            AppTile(
              flat: true,
              flatLeadingEdgeAligned: true,
              flatTrailingEdgeAligned: true,
              iconColor: theme.colorScheme.primary,
              trailingIcon: widget.playingId == segment.id
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
              title: '第 ${i + 1} 段录音',
              subtitle: '',
              trailingText: '${segment.durationSeconds} 秒',
              onTap: () => widget.onPlay(segment),
            ),
        ],
        PictureStoryFeedback(
          feedbackJson: take.feedbackJson,
          legacyHeading: '点评',
          separated: true,
        ),
        if (rawRevisions.length > 1)
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('这一遍的文字修改记录'),
              children: [
                for (final raw in rawRevisions.take(rawRevisions.length - 1))
                  Builder(
                    builder: (context) {
                      final revision = PictureStoryAnswerRevision.fromJson(raw);
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: SpacingTokens.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(revision.answer),
                            PictureStoryFeedback(
                              feedbackJson: revision.feedbackJson,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
