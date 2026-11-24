import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_widgets.dart';

class EnglishHistoryPage extends ConsumerStatefulWidget {
  const EnglishHistoryPage({super.key, required this.bookId, this.attemptId});
  final String bookId;
  final String? attemptId;
  @override
  ConsumerState<EnglishHistoryPage> createState() => _EnglishHistoryPageState();
}

class _EnglishHistoryPageState extends ConsumerState<EnglishHistoryPage>
    with WidgetsBindingObserver {
  late final EnglishAudio _audio;
  late final _audioKey = englishAudioKey(widget.bookId);
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _audio = ref.read(englishAudioProvider(_audioKey));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  @override
  void dispose() {
    unawaited(_audio.stop());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check(int index, bool passed) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await ensureParentAccess(context) || !mounted) return;
      final authorized = ParentAccessService.instance.captureAuthorization();
      final repository = ref.read(
        englishProgressRepositoryProvider(widget.bookId),
      );
      if (repository == null) throw const FormatException('请重新下载对应原书并核对课程后再操作');
      await repository.parentCheck(widget.attemptId!, index, passed, () {
        assertParentAccess(context);
        authorized();
      });
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(englishProgressProvider(widget.bookId)),
        audio = ref.watch(englishAudioProvider(_audioKey)),
        theme = Theme.of(context);
    final attempt = progress?.attempts
        .where((a) => a.id == widget.attemptId)
        .firstOrNull;
    return AppScaffold(
      appBar: AppBar(title: Text(widget.attemptId == null ? '英语学习记录' : '本次学习')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            if (widget.attemptId == null) ...[
              if (progress == null || progress.attempts.isEmpty)
                const AppEmptyState(icon: Icons.history, title: '还没有已保存的英语记录'),
              if (progress?.attempts.isNotEmpty == true)
                AppTileGroup(
                  children: [
                    for (final a in progress!.attempts.reversed)
                      AppTile(
                        icon: a.kind == 'speaking'
                            ? Icons.mic_none
                            : Icons.fact_check_outlined,
                        iconColor: theme.colorScheme.primary,
                        title: a.title,
                        titleMaxLines: 2,
                        subtitle:
                            '${a.completedAt.toLocal().toString().substring(0, 16)} · ${a.kind == 'speaking' ? '跟读 ${a.spokenTexts.length} 句' : '答对 ${a.correct} / ${a.answers.length} 项'}',
                        onTap: () => context.push(
                          AppRoutes.englishBookOf(widget.bookId, attempt: a.id),
                        ),
                      ),
                  ],
                ),
            ] else if (attempt == null)
              const AppEmptyState(icon: Icons.history, title: '没有找到这次记录')
            else ...[
              if (ref.watch(englishBookProvider(widget.bookId)) == null)
                const Text('原书已移除，文字记录保留；录音仍在原设备。'),
              Text(attempt.title, style: theme.textTheme.headlineSmall),
              Text(attempt.completedAt.toLocal().toString().substring(0, 16)),
              const SizedBox(height: SpacingTokens.md),
              if (attempt.kind == 'speaking') ...[
                Text('已保存 ${attempt.spokenTexts.length} 句跟读'),
                const Text('录音不参与发音评分。'),
                if (audio.message.isNotEmpty) Text(audio.message),
                for (var i = 0; i < attempt.spokenTexts.length; i++)
                  AppTile(
                    icon: Icons.play_circle_outline,
                    iconColor: theme.colorScheme.primary,
                    title: attempt.spokenTexts[i],
                    titleMaxLines: 4,
                    subtitle: attempt.recordingIds.length <= i
                        ? '录音不在本机，文字记录已保留'
                        : '播放本机录音',
                    onTap: attempt.recordingIds.length <= i
                        ? null
                        : () => audio.replay(id: attempt.recordingIds[i]),
                  ),
                if (audio.busy)
                  TextButton(
                    onPressed: () => audio.stop(),
                    child: const Text('停止回听'),
                  ),
              ] else ...[
                Text(
                  '答对 ${attempt.correct} · 已核对 ${attempt.graded} / ${attempt.answers.length} 项',
                ),
                for (final entry in attempt.answers.asMap().entries)
                  Padding(
                    padding: const EdgeInsets.only(top: SpacingTokens.md),
                    child: ColoredCard(
                      color: theme.colorScheme.primary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key + 1}. ${entry.value.question.prompt}',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            entry.value.skipped
                                ? '已跳过'
                                : '你的回答：${entry.value.answer}',
                          ),
                          if (!entry.value.question.parentCheck &&
                              !entry.value.skipped)
                            Text(
                              '参考答案：${entry.value.question.answers.join(' / ')}',
                            ),
                          if (entry.value.hinted) const Text('用过提示，已安排复习'),
                          if (entry.value.question.parentCheck &&
                              !entry.value.skipped) ...[
                            Text(
                              entry.value.parentPassed == null
                                  ? '待家长核对'
                                  : entry.value.parentPassed!
                                  ? '家长已确认完成'
                                  : '家长建议再练习',
                            ),
                            Wrap(
                              spacing: SpacingTokens.sm,
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _check(entry.key, true),
                                  child: const Text('家长确认完成'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _check(entry.key, false),
                                  child: const Text('家长建议再练'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
