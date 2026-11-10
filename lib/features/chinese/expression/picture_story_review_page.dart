import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/picture_story_feedback_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_feedback.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';

/// 同一次练习的文字修订；录音仍对应最初口述，各版答案与点评成对展示。
class PictureStoryReviewPage extends ConsumerStatefulWidget {
  const PictureStoryReviewPage({super.key, required this.recordId});
  final String recordId;
  @override
  ConsumerState<PictureStoryReviewPage> createState() =>
      _PictureStoryReviewPageState();
}

class _PictureStoryReviewPageState extends ConsumerState<PictureStoryReviewPage>
    with WidgetsBindingObserver {
  late final PictureStoryRepository _repository;
  late final String _profile;
  late final int _profileRevision;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  PictureStoryPracticeRecord? _record;
  PictureStoryPrompt? _prompt;
  PictureStoryFeedbackService? _feedback;
  StreamSubscription<String>? _profileChanges;
  Future<bool> _saving = Future.value(true);
  bool _busy = false;
  bool _editing = false;
  bool _foreground = true;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile = ProfileScope.currentId;
    _profileRevision = ProfileScope.revision;
    _repository = ref.read(pictureStoryRepositoryProvider);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _profileChanges = ProfileScope.changes.listen((_) => _cancel());
    try {
      _record = _repository.find(widget.recordId)?.copy();
      final record = _record;
      if (record != null && record.status == 'completed') {
        _prompt = _repository.findPrompt(
          record.promptId,
          version: record.promptVersion,
        );
        record.revisions; // 坏历史不得当空历史覆盖。
        _text.text = record.revisionDraft ?? record.answerText;
        _editing = true;
      }
    } on Object {
      _error = '练习记录暂时无法读取，请返回重试。';
      _record = null;
    }
  }

  bool get _sameProfile =>
      ProfileScope.currentId == _profile &&
      ProfileScope.revision == _profileRevision;
  bool _active(int generation) =>
      mounted &&
      _foreground &&
      _sameProfile &&
      generation == _generation &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  void _cancel() {
    _generation++;
    _feedback?.cancel();
    if (mounted) {
      setState(() {
        if (_busy) _error = '点评已暂停，修改文字已保留，可重新发起。';
        _busy = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _cancel();
    if (mounted) setState(() {});
  }

  Future<bool> _saveText(String text) {
    return _saving = _saving.then((_) async {
      try {
        if (!_sameProfile) throw const FormatException('孩子档案已切换，请重新打开记录');
        _record = await _repository.saveFeedbackDraft(
          _record!,
          text,
          check: () {
            if (!_sameProfile) throw const FormatException('孩子档案已切换，请重新打开记录');
          },
        );
        return true;
      } on Object {
        if (mounted) setState(() => _error = '修改暂未保存，记录可能已更新，请保留文字后重新打开。');
        return false;
      }
    });
  }

  Future<Uint8List?> _image() async {
    final prompt = _prompt!;
    if (prompt.image.isLocal) {
      return ref
          .read(pictureStoryImageServiceProvider)
          .readForVision(prompt.image.value);
    }
    return PictureStoryIllustration.renderForVision(
      kind: prompt.image.value,
      scheme: Theme.of(context).colorScheme,
    );
  }

  Future<void> _evaluate() async {
    if (_busy || !_foreground || !_sameProfile || _prompt == null) return;
    if (_text.text.trim().isEmpty) {
      setState(() => _error = '请先填写表达文字，再重新点评。');
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = _feedback = PictureStoryFeedbackService(
      settings: ref.read(settingsRepositoryProvider),
      httpClient: ref.read(llmExplainHttpClientProvider),
      onSelectionChanged: () {
        if (_active(generation)) {
          ref.read(llmSelectionVersionProvider.notifier).state++;
        }
      },
    );
    try {
      if (!await _saveText(_text.text) || !_active(generation)) return;
      final snapshot = _record!.copy();
      Uint8List? image;
      try {
        image = await _image();
      } on Object {
        /* 服务给出可重试提示。 */
      }
      if (!_active(generation)) return;
      final feedback = await service.evaluate(
        prompt: _prompt!,
        answer: snapshot.revisionDraft!,
        image: image,
        isActive: () => _active(generation),
      );
      if (!_active(generation)) return;
      final result = jsonDecode(feedback) as Map<String, dynamic>;
      if (result['source'] != 'vision') {
        setState(() => _error = '本次未获得 AI 点评。${result['suggestion']} 修改文字已保留。');
        return;
      }
      final saved = await _repository.appendFeedback(
        snapshot,
        feedback,
        check: () {
          if (!_active(generation)) throw const FormatException('点评已暂停');
        },
      );
      if (_active(generation)) {
        setState(() {
          _record = saved;
          _editing = false;
        });
        _scroll.jumpTo(0);
      }
    } on Object {
      if (_active(generation)) setState(() => _error = '点评未能保存，修改文字已保留，请稍后重试。');
    } finally {
      service.cancel();
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _feedback?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_profileChanges?.cancel());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = _record;
    final prompt = _prompt;
    final revisions = record?.revisions ?? <PictureStoryAnswerRevision>[];
    final previous = record == null
        ? <PictureStoryAnswerRevision>[]
        : _editing
        ? (revisions.isEmpty
              ? [
                  PictureStoryAnswerRevision(
                    answer: record.answerText,
                    feedbackJson: record.feedbackJson,
                    createdAt: record.completedAt ?? record.startedAt,
                  ),
                ]
              : revisions)
        : revisions.take(revisions.isEmpty ? 0 : revisions.length - 1).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('修改表达与点评')),
      body: record == null
          ? AppEmptyState(
              icon: Icons.history_outlined,
              title: '暂时无法打开这次表达',
              description: _error ?? '请返回练习记录重试。',
            )
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                if (prompt != null) PictureStoryImageView(image: prompt.image),
                if (prompt == null) const Text('原题版本暂时无法读取，仍可查看已有表达与点评。'),
                if (prompt != null) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(prompt.title, style: theme.textTheme.titleMedium),
                  for (final question in prompt.questions) Text(question),
                ],
                const SizedBox(height: SpacingTokens.md),
                if (!_sameProfile) const Text('孩子档案已切换，请返回重新打开记录。'),
                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editing ? '修改我的表达' : '本次表达',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      if (_editing) ...[
                        TextField(
                          controller: _text,
                          minLines: 4,
                          maxLines: 12,
                          maxLength: 6000,
                          readOnly: _busy || !_sameProfile,
                          decoration: const InputDecoration(labelText: '表达文字'),
                          onChanged: (text) => unawaited(_saveText(text)),
                        ),
                        const Text('修改文字不会改变原录音，之前的表达和点评会保留。'),
                        const SizedBox(height: SpacingTokens.sm),
                        if (_busy)
                          const LinearProgressIndicator(semanticsLabel: '正在点评'),
                        const SizedBox(height: SpacingTokens.sm),
                        FilledButton(
                          onPressed:
                              _busy ||
                                  !_foreground ||
                                  !_sameProfile ||
                                  prompt == null
                              ? null
                              : _evaluate,
                          child: Text(_busy ? '正在点评…' : '保存并重新点评'),
                        ),
                      ] else ...[
                        Text(record.answerText),
                        PictureStoryFeedback(feedbackJson: record.feedbackJson),
                        const SizedBox(height: SpacingTokens.md),
                        FilledButton.tonalIcon(
                          onPressed: !_sameProfile || prompt == null
                              ? null
                              : () {
                                  setState(() {
                                    _editing = true;
                                    _error = null;
                                  });
                                },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('修改表达并重新点评'),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: SpacingTokens.sm),
                        Text(_error!),
                      ],
                    ],
                  ),
                ),
                if (previous.isNotEmpty) ...[
                  const SizedBox(height: SpacingTokens.md),
                  ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Material(
                      type: MaterialType.transparency,
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('之前的表达与点评'),
                        children: [
                          for (final (index, version) in previous.indexed)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: SpacingTokens.lg,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    index == 0 ? '最初的表达' : '第 ${index + 1} 版表达',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(version.answer),
                                  PictureStoryFeedback(
                                    feedbackJson: version.feedbackJson,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
