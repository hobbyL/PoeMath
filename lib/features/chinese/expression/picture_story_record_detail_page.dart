import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_review_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_feedback.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_history_prompt_card.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';

/// 查看一次已完成练习；只有主动进入重评页后才允许修改表达。
class PictureStoryRecordDetailPage extends ConsumerStatefulWidget {
  const PictureStoryRecordDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  ConsumerState<PictureStoryRecordDetailPage> createState() =>
      _PictureStoryRecordDetailPageState();
}

class _PictureStoryRecordDetailPageState
    extends ConsumerState<PictureStoryRecordDetailPage>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  late final int _profileRevision;
  late final StreamSubscription<String> _profileChanges;
  late final StreamSubscription<void> _playbackComplete;
  String? _playing;
  int _playRequest = 0;
  bool _showPrompt = false;

  bool get _sameProfile => _profileRevision == ProfileScope.revision;

  @override
  void initState() {
    super.initState();
    _profileRevision = ProfileScope.revision;
    WidgetsBinding.instance.addObserver(this);
    _profileChanges = ProfileScope.changes.listen((_) {
      unawaited(_stopPlayback());
    });
    _playbackComplete = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stopPlayback());
  }

  @override
  void dispose() {
    _playRequest++;
    WidgetsBinding.instance.removeObserver(this);
    _profileChanges.cancel();
    _playbackComplete.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _stopPlayback() async {
    _playRequest++;
    if (mounted) setState(() => _playing = null);
    await _player.stop();
  }

  Future<void> _play(PictureStorySegment segment) async {
    if (!_sameProfile) return;
    if (_playing == segment.id) {
      await _stopPlayback();
      return;
    }
    final request = ++_playRequest;
    setState(() => _playing = null);
    try {
      await _player.stop();
      if (!mounted || request != _playRequest) return;
      final exists = await File(segment.audioPath).exists();
      if (!mounted || request != _playRequest) return;
      if (!exists) throw const FileSystemException('录音文件不存在');
      setState(() => _playing = segment.id);
      await _player.play(DeviceFileSource(segment.audioPath));
    } on Exception {
      if (!mounted || request != _playRequest) return;
      setState(() => _playing = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这段录音暂时无法播放，表达文字仍保留。')));
    }
  }

  Future<void> _edit(PictureStoryPracticeRecord record) async {
    await _stopPlayback();
    if (!mounted || !_sameProfile) return;
    await Navigator.of(context).push(
      fadeSlideRoute<void>(
        builder: (_) => PictureStoryReviewPage(recordId: record.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(pictureStoryHistoryProvider);
    final record = _sameProfile
        ? records.where((item) => item.id == widget.recordId).firstOrNull
        : null;
    PictureStoryPrompt? prompt;
    if (record != null) {
      try {
        prompt = ref.watch(
          pictureStoryPromptVersionProvider((
            id: record.promptId,
            version: record.promptVersion,
          )),
        );
      } on Object {
        // 原题缺失时仍保留该次表达、点评与录音。
      }
    }
    final togglePrompt = record == null
        ? null
        : IconButton(
            tooltip: _showPrompt ? '隐藏题目' : '查看题目',
            isSelected: _showPrompt,
            icon: const Icon(Icons.image_outlined),
            selectedIcon: const Icon(Icons.image),
            onPressed: () => setState(() => _showPrompt = !_showPrompt),
          );
    final reviewAction = record == null ? null : _reviewAction(context, record);
    final content = record == null
        ? const <Widget>[]
        : _recordContent(context, record, prompt);
    if (_showPrompt && prompt != null && record != null) {
      return PictureStorySceneScaffold(
        image: prompt.image,
        semanticLabel: '练习详情：${prompt.title}',
        actions: [togglePrompt!],
        bottomNavigationBar: reviewAction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: content,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('练习详情'),
        actions: [if (togglePrompt != null) togglePrompt],
      ),
      bottomNavigationBar: reviewAction,
      body: record == null
          ? AppEmptyState(
              icon: Icons.history_outlined,
              title: '暂时无法打开这次练习',
              description: _sameProfile
                  ? '记录不存在或尚未完成，请返回练习记录。'
                  : '孩子档案已切换，请返回重新打开记录。',
            )
          : SafeArea(
              top: false,
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ResponsiveLayout.mediumBreakpoint,
                  ),
                  child: ListView(
                    // 展开题图使用独立滚动区域，收起后回到原先阅读位置。
                    key: PageStorageKey('record-expression-${record.id}'),
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: content,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _reviewAction(
    BuildContext context,
    PictureStoryPracticeRecord record,
  ) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ResponsiveLayout.mediumBreakpoint,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SpacingTokens.md,
              SpacingTokens.sm,
              SpacingTokens.md,
              SpacingTokens.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (record.revisionDraft != null) ...[
                  Text(
                    '有尚未点评的修改',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, SpacingTokens.minTapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.md,
                      vertical: SpacingTokens.md,
                    ),
                  ),
                  onPressed: () => _edit(record),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改表达并重新点评', textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _recordContent(
    BuildContext context,
    PictureStoryPracticeRecord record,
    PictureStoryPrompt? prompt,
  ) {
    final theme = Theme.of(context);
    return [
      if (_showPrompt) ...[
        PictureStoryHistoryPromptCard(prompt: prompt, showImage: false),
        const SizedBox(height: SpacingTokens.lg),
      ],
      _expressionHeading(context, record.startedAt),
      const SizedBox(height: SpacingTokens.md),
      if (prompt == null) ...[
        const Text('原题版本暂时无法读取，表达与录音记录仍保留。'),
        const SizedBox(height: SpacingTokens.sm),
      ],
      Text(
        record.answerText.isEmpty ? '本次未保存表达文字' : record.answerText,
        style: theme.textTheme.bodyLarge,
      ),
      if (record.segments.isNotEmpty) ...[
        const SizedBox(height: SpacingTokens.sm),
        for (final (index, segment) in record.segments.indexed)
          AppTile(
            flat: true,
            flatLeadingEdgeAligned: true,
            flatTrailingEdgeAligned: true,
            iconColor: theme.colorScheme.primary,
            trailingIcon: _playing == segment.id
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outline,
            title: '第 ${index + 1} 段录音',
            subtitle: '',
            trailingText: '${segment.durationSeconds} 秒',
            onTap: () => _play(segment),
          ),
      ],
      PictureStoryFeedback(
        feedbackJson: record.feedbackJson,
        legacyHeading: '点评',
        separated: true,
      ),
    ];
  }

  Widget _expressionHeading(BuildContext context, DateTime startedAt) {
    final theme = Theme.of(context);
    final date = pictureStoryHistoryDate(startedAt);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final dateStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        double textWidth(String text, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final title = Text('我的表达', style: titleStyle);
        final time = Text(date, textAlign: TextAlign.end, style: dateStyle);
        if (textWidth('我的表达', titleStyle) +
                textWidth(date, dateStyle) +
                SpacingTokens.md >
            constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: SpacingTokens.xs),
              time,
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [title, time],
        );
      },
    );
  }
}
