import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_feedback.dart';

class PictureStoryHistoryPage extends ConsumerStatefulWidget {
  const PictureStoryHistoryPage({super.key});

  @override
  ConsumerState<PictureStoryHistoryPage> createState() =>
      _PictureStoryHistoryPageState();
}

class _PictureStoryHistoryPageState
    extends ConsumerState<PictureStoryHistoryPage> {
  final _player = AudioPlayer();
  String? _playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(PictureStorySegment segment) async {
    if (!await File(segment.audioPath).exists()) return;
    if (_playing == segment.id) {
      await _player.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    await _player.stop();
    setState(() => _playing = segment.id);
    await _player.play(DeviceFileSource(segment.audioPath));
    _player.onPlayerComplete.first.then((_) {
      if (mounted && _playing == segment.id) setState(() => _playing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = ref
        .watch(pictureStoryHistoryProvider)
        .whereType<PictureStoryPracticeRecord>()
        .where((record) => record.status == 'completed')
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('看图说话记录')),
      body: records.isEmpty
          ? const AppEmptyState(
              icon: Icons.history_outlined,
              title: '还没有完成的练习',
              description: '完成一次看图说话练习后，可在这里回看表达与录音。',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                PictureStoryPrompt? prompt;
                try {
                  prompt = ref.watch(
                    pictureStoryPromptVersionProvider((
                      id: record.promptId,
                      version: record.promptVersion,
                    )),
                  );
                } on Object {
                  // 历史缺失时明确提示，不用新版题目代替原版本。
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                  child: ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (prompt != null)
                          PictureStoryImageView(image: prompt.image),
                        if (prompt == null)
                          const Text('原题版本暂时无法读取，表达与录音记录仍保留。'),
                        const SizedBox(height: SpacingTokens.sm),
                        Text(
                          prompt?.title ?? '看图说话',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: SpacingTokens.xs),
                        Text(
                          '${record.segments.length} 段 · ${record.totalDurationSeconds} 秒 · ${_date(record.startedAt)}',
                        ),
                        if (record.answerText.isNotEmpty) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          Text(record.answerText),
                        ],
                        PictureStoryFeedback(feedbackJson: record.feedbackJson),
                        if (prompt != null && prompt.reference.isNotEmpty) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          Text('参考表达', style: theme.textTheme.labelLarge),
                          const SizedBox(height: SpacingTokens.xs),
                          Text(prompt.reference),
                        ],
                        const SizedBox(height: SpacingTokens.sm),
                        for (final segment in record.segments)
                          AppTile(
                            flat: true,
                            iconColor: theme.colorScheme.primary,
                            icon: _playing == segment.id
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline,
                            title: segment.answerText.isEmpty
                                ? '未填写文字'
                                : segment.answerText,
                            subtitle:
                                '${segment.durationSeconds} 秒 · ${segment.recognitionMode == 'realtime' ? '实时识别' : '一句话识别'}',
                            onTap: () => _play(segment),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _date(DateTime value) => '${value.year}/${value.month}/${value.day}';
}
