import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_widgets.dart';

class EnglishStudyPage extends ConsumerStatefulWidget {
  const EnglishStudyPage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.kind,
    this.targetId,
  });
  final String bookId, lessonId;
  final String? kind, targetId;
  @override
  ConsumerState<EnglishStudyPage> createState() => _EnglishStudyPageState();
}

class _EnglishStudyPageState extends ConsumerState<EnglishStudyPage>
    with WidgetsBindingObserver {
  late final EnglishAudio _audio;
  late final _audioKey = englishAudioKey(widget.bookId);
  StreamSubscription<String>? _profiles;
  String _vocabularyMode = 'list';
  int? _vocabularyIndex;
  bool _vocabularyRevealed = false, _vocabularyBusy = false;
  @override
  void initState() {
    super.initState();
    _audio = ref.read(englishAudioProvider(_audioKey));
    WidgetsBinding.instance.addObserver(this);
    _profiles = ProfileScope.changes.listen((_) => unawaited(_audio.stop()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  @override
  void dispose() {
    unawaited(_audio.stop());
    _profiles?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _remember(String target) async {
    if (!mounted) return;
    try {
      await ref
          .read(englishProgressRepositoryProvider(widget.bookId))
          ?.remember(widget.lessonId, targetId: target);
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    }
  }

  Future<void> _moveVocabulary(List<EnglishTarget> targets, int delta) async {
    if (_vocabularyBusy) return;
    final index = _vocabularyIndex ?? 0;
    final nextIndex = (index + delta + targets.length) % targets.length;
    setState(() {
      _vocabularyIndex = nextIndex;
      _vocabularyRevealed = false;
    });
    await _remember(targets[nextIndex].id);
  }

  Future<void> _rateVocabulary(
    List<EnglishTarget> targets,
    EnglishTarget target, {
    required bool mastered,
  }) async {
    if (_vocabularyBusy) return;
    setState(() => _vocabularyBusy = true);
    try {
      await _audio.stop();
      await ref
          .read(englishProgressRepositoryProvider(widget.bookId))
          ?.selfAssessVocabulary(
            widget.lessonId,
            target.id,
            expectedFingerprint: target.fingerprint,
            mastered: mastered,
          );
      if (!mounted) return;
      setState(() {
        _vocabularyIndex = ((_vocabularyIndex ?? 0) + 1) % targets.length;
        _vocabularyRevealed = false;
      });
      await _remember(targets[_vocabularyIndex!].id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mastered ? '已记录自评' : '已安排明日复习')));
      }
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _vocabularyBusy = false);
    }
  }

  Future<void> _playVocabulary(
    EnglishTarget target,
    Map<String, String>? voice,
  ) async {
    await _remember(target.id);
    if (!mounted) return;
    final played = await _audio.speak(target.text, voice);
    if (mounted &&
        widget.targetId != null &&
        !played &&
        !_audio.busy &&
        _audio.message.isNotEmpty) {
      englishMessage(context, StateError(_audio.message));
    }
  }

  Future<void> _openVocabularySource(
    BuildContext context,
    EnglishTarget target,
  ) async {
    await _remember(target.id);
    await _audio.stop();
    if (context.mounted) {
      context.push(
        AppRoutes.englishBookOf(widget.bookId, page: target.sources.first.page),
      );
    }
  }

  Future<void> _openVocabularyDetail(EnglishTarget target) async {
    await _remember(target.id);
    await _audio.stop();
    if (!mounted) return;
    context.push(
      AppRoutes.englishVocabularyOf(
        widget.bookId,
        lesson: widget.lessonId,
        target: target.id,
      ),
    );
  }

  Future<void> _practiceVocabulary(
    EnglishTarget target,
    EnglishPracticeKind kind,
  ) async {
    await _remember(target.id);
    await _audio.stop();
    if (!mounted) return;
    context.push(
      AppRoutes.englishBookOf(
        widget.bookId,
        action: 'practice',
        kind: kind.name,
        lesson: widget.lessonId,
        targetKey: '${widget.lessonId}/${target.id}/${kind.name}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(englishAudioProvider(_audioKey)),
        voice = ref.watch(englishVoiceProvider),
        theme = Theme.of(context);
    final isVocabularyDetail =
        widget.kind == 'vocabulary' && widget.targetId != null;
    final detailTarget = isVocabularyDetail
        ? ref
              .watch(englishCourseProvider(widget.bookId))
              .asData
              ?.value
              ?.lesson(widget.lessonId)
              ?.targets
              .where(
                (target) =>
                    target.id == widget.targetId &&
                    target.isLearnableVocabulary,
              )
              .firstOrNull
        : null;
    return AppScaffold(
      backgroundScene: PineInkScene.study,
      appBar: AppBar(
        title: Text(
          widget.kind != 'vocabulary'
              ? '学一学'
              : widget.targetId == null
              ? '单词与短语'
              : '单词详情',
        ),
        actions: [
          IconButton(
            key: isVocabularyDetail
                ? const ValueKey('english-vocabulary-playback')
                : null,
            tooltip: isVocabularyDetail && !audio.busy ? '听一听' : '停止朗读',
            onPressed: audio.busy
                ? () => audio.stop()
                : detailTarget != null && detailTarget.hasSpeech
                ? () => _playVocabulary(detailTarget, voice)
                : null,
            icon: Icon(
              isVocabularyDetail && !audio.busy
                  ? Icons.volume_up_outlined
                  : Icons.stop_circle_outlined,
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          widget.kind == 'vocabulary' && widget.targetId == null
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                SpacingTokens.md,
                SpacingTokens.sm,
                SpacingTokens.md,
                SpacingTokens.sm,
              ),
              child: SegmentedButton<String>(
                key: const ValueKey('english-vocabulary-mode'),
                expandedInsets: EdgeInsets.zero,
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.all(SpacingTokens.sm),
                ),
                segments: const [
                  ButtonSegment(value: 'list', label: Text('词表')),
                  ButtonSegment(value: 'flashcard', label: Text('翻卡自测')),
                ],
                selected: {_vocabularyMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() {
                  if (_vocabularyBusy) return;
                  _vocabularyMode = selection.first;
                  _vocabularyRevealed = false;
                }),
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        child: EnglishCourseBody(
          bookId: widget.bookId,
          builder: (book, course) {
            final lesson = course.lesson(widget.lessonId);
            if (lesson == null) {
              return const AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: '课时已移除',
              );
            }
            final targets = lesson.targets
                .where(
                  (target) => widget.kind == 'vocabulary'
                      ? target.isLearnableVocabulary
                      : target.approved &&
                            (widget.kind == null ||
                                target.kind.name == widget.kind),
                )
                .toList();
            if (widget.kind == 'vocabulary') {
              if (widget.targetId != null) {
                final target = detailTarget;
                if (target == null) {
                  return const AppEmptyState(
                    icon: Icons.menu_book_outlined,
                    title: '这个词暂不可学习',
                  );
                }
                return _vocabularyDetail(
                  context,
                  book,
                  course,
                  target,
                  voice,
                  theme,
                );
              }
              return _vocabularyLearning(
                context,
                book,
                lesson,
                targets,
                audio,
                voice,
                theme,
              );
            }
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                Text(
                  '${lesson.unitTitle} · ${lesson.title}',
                  style: theme.textTheme.titleLarge,
                ),
                if (audio.message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SpacingTokens.sm,
                    ),
                    child: Text(audio.message),
                  ),
                if (voice == null) const Text('没有英语音色，仍可学习文字。'),
                for (final target in targets)
                  Padding(
                    padding: const EdgeInsets.only(top: SpacingTokens.md),
                    child: ColoredCard(
                      color: theme.colorScheme.primary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (target.role.isNotEmpty)
                            Text(
                              target.role,
                              style: theme.textTheme.labelLarge,
                            ),
                          SelectableText(
                            target.text,
                            style: theme.textTheme.headlineSmall,
                          ),
                          if (target.meaning.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: SpacingTokens.sm,
                              ),
                              child: Text(target.meaning),
                            ),
                          if (target.picture != null)
                            EnglishSourceImage(
                              book: book,
                              source: target.picture!,
                            ),
                          Wrap(
                            spacing: SpacingTokens.sm,
                            runSpacing: SpacingTokens.xs,
                            children: [
                              if (target.hasSpeech)
                                TextButton.icon(
                                  onPressed: () async {
                                    await _remember(target.id);
                                    if (mounted) {
                                      await audio.speak(target.text, voice);
                                    }
                                  },
                                  icon: const Icon(Icons.volume_up_outlined),
                                  label: const Text('听一听'),
                                ),
                              TextButton(
                                onPressed: () async {
                                  await audio.stop();
                                  if (context.mounted) {
                                    context.push(
                                      AppRoutes.englishBookOf(
                                        widget.bookId,
                                        page: target.sources.first.page,
                                      ),
                                    );
                                  }
                                },
                                child: const Text('看原书'),
                              ),
                              TextButton(
                                onPressed: () => _remember(target.id),
                                child: const Text('学到这里'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (targets.isEmpty)
                  const AppEmptyState(
                    icon: Icons.pending_actions,
                    title: '本部分还没有核对好的内容',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _vocabularyLearning(
    BuildContext context,
    Textbook book,
    EnglishLesson lesson,
    List<EnglishTarget> targets,
    EnglishAudio audio,
    Map<String, String>? voice,
    ThemeData theme,
  ) {
    if (targets.isEmpty) {
      return const AppEmptyState(
        icon: Icons.pending_actions,
        title: '本课还没有可学习的单词',
      );
    }
    final progress = ref.watch(englishProgressProvider(widget.bookId));
    if (_vocabularyIndex == null) {
      final rememberedId = progress?.lastLessonId == lesson.id
          ? progress?.lastTargetId
          : null;
      final rememberedIndex = targets.indexWhere(
        (target) => target.id == rememberedId,
      );
      _vocabularyIndex = rememberedIndex < 0 ? 0 : rememberedIndex;
    } else {
      _vocabularyIndex = _vocabularyIndex!.clamp(0, targets.length - 1);
    }
    return ListView(
      key: const ValueKey('english-vocabulary-learning'),
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        if (audio.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Text(audio.message),
          ),
        if (_vocabularyMode == 'list')
          ResponsiveCardGrid(
            preferredTileWidth: ResponsiveLayout.compactCardWidth,
            children: [
              for (final target in targets)
                AppTile(
                  key: ValueKey('english-vocabulary-word-${target.id}'),
                  layout: AppTileLayout.stacked,
                  iconColor: theme.colorScheme.primary,
                  title: target.text,
                  titleWrap: true,
                  subtitle: target.meaning,
                  trailingPrefix: target.hasSpeech
                      ? IconButton(
                          tooltip: '朗读 ${target.text}',
                          alignment: AlignmentDirectional.centerEnd,
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(
                              SpacingTokens.minTapTarget,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _playVocabulary(target, voice),
                          icon: const Icon(Icons.volume_up_outlined),
                        )
                      : null,
                  onTap: () => _openVocabularyDetail(target),
                ),
            ],
          )
        else
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ResponsiveLayout.mediumBreakpoint,
              ),
              child: _vocabularyFlashcard(context, book, targets, voice, theme),
            ),
          ),
      ],
    );
  }

  Widget _vocabularyDetail(
    BuildContext context,
    Textbook book,
    EnglishCourse course,
    EnglishTarget target,
    Map<String, String>? voice,
    ThemeData theme,
  ) {
    final play = target.hasSpeech ? () => _playVocabulary(target, voice) : null;
    final practiceKinds =
        [EnglishPracticeKind.meaning, EnglishPracticeKind.spelling]
            .where(
              (kind) => buildEnglishQuestions(
                course,
                kind,
                lessonId: widget.lessonId,
                targetKeys: {'${widget.lessonId}/${target.id}/${kind.name}'},
              ).isNotEmpty,
            )
            .toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.mediumBreakpoint,
        ),
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            ColoredCard(
              key: const ValueKey('english-vocabulary-detail-card'),
              color: theme.colorScheme.primary,
              onTap: play,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    target.text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    target.meaning,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (target.picture != null) ...[
                    const SizedBox(height: SpacingTokens.md),
                    EnglishSourceImage(book: book, source: target.picture!),
                  ],
                ],
              ),
            ),
            if (practiceKinds.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              ResponsiveCardGrid(
                preferredTileWidth: ResponsiveLayout.compactCardWidth,
                children: [
                  for (final kind in practiceKinds)
                    AppTile(
                      key: ValueKey('english-vocabulary-${kind.name}-practice'),
                      icon: kind == EnglishPracticeKind.meaning
                          ? Icons.checklist_outlined
                          : Icons.spellcheck_outlined,
                      iconColor: theme.colorScheme.primary,
                      title: kind == EnglishPracticeKind.meaning
                          ? '词义选择'
                          : kind.label,
                      titleWrap: true,
                      subtitle: '',
                      onTap: () => _practiceVocabulary(target, kind),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vocabularyFlashcard(
    BuildContext context,
    Textbook book,
    List<EnglishTarget> targets,
    Map<String, String>? voice,
    ThemeData theme,
  ) {
    final index = _vocabularyIndex ?? 0, target = targets[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredCard(
          color: theme.colorScheme.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(target.meaning, style: theme.textTheme.headlineSmall),
              if (_vocabularyRevealed) ...[
                const SizedBox(height: SpacingTokens.md),
                SelectableText(
                  target.text,
                  style: theme.textTheme.headlineMedium,
                ),
                if (target.picture != null)
                  EnglishSourceImage(book: book, source: target.picture!),
              ],
            ],
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.xs,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('english-vocabulary-reveal'),
              onPressed: _vocabularyBusy
                  ? null
                  : () => setState(
                      () => _vocabularyRevealed = !_vocabularyRevealed,
                    ),
              icon: Icon(
                _vocabularyRevealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              label: Text(_vocabularyRevealed ? '遮住英文' : '翻出英文'),
            ),
            if (_vocabularyRevealed && target.hasSpeech)
              TextButton.icon(
                onPressed: () => _playVocabulary(target, voice),
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('听一听'),
              ),
            if (_vocabularyRevealed)
              TextButton(
                onPressed: () => _openVocabularyDetail(target),
                child: const Text('单词详情'),
              ),
            if (_vocabularyRevealed)
              TextButton(
                onPressed: () => _openVocabularySource(context, target),
                child: const Text('看原书'),
              ),
          ],
        ),
        if (_vocabularyRevealed) ...[
          const SizedBox(height: SpacingTokens.md),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('english-vocabulary-self-mastered'),
                onPressed: _vocabularyBusy
                    ? null
                    : () => _rateVocabulary(targets, target, mastered: true),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('掌握'),
              ),
              FilledButton.icon(
                key: const ValueKey('english-vocabulary-self-again'),
                onPressed: _vocabularyBusy
                    ? null
                    : () => _rateVocabulary(targets, target, mastered: false),
                icon: const Icon(Icons.event_repeat),
                label: const Text('待复习'),
              ),
            ],
          ),
        ],
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          spacing: SpacingTokens.sm,
          children: [
            TextButton(
              onPressed: _vocabularyBusy
                  ? null
                  : () => _moveVocabulary(targets, -1),
              child: const Text('上一个'),
            ),
            TextButton(
              onPressed: _vocabularyBusy
                  ? null
                  : () => _moveVocabulary(targets, 1),
              child: const Text('下一个'),
            ),
          ],
        ),
      ],
    );
  }
}

class EnglishSpeakingPage extends ConsumerStatefulWidget {
  const EnglishSpeakingPage({
    super.key,
    required this.bookId,
    required this.lessonId,
  });
  final String bookId, lessonId;
  @override
  ConsumerState<EnglishSpeakingPage> createState() =>
      _EnglishSpeakingPageState();
}

class _EnglishSpeakingPageState extends ConsumerState<EnglishSpeakingPage>
    with WidgetsBindingObserver {
  late final EnglishAudio _audio;
  late final _audioKey = englishAudioKey(widget.bookId);
  late final EnglishProgressRepository _progress = ref.read(
    englishProgressRepositoryProvider(widget.bookId),
  )!;
  final _drafts = PracticeDraftRepository();
  late final String _scope = '${widget.bookId}/${widget.lessonId}';
  String _session = newEnglishId(), _role = '全部角色';
  Map<String, String> _recordings = {};
  List<EnglishTarget>? _targets;
  int _index = 0, _previousSeconds = 0;
  bool _busy = false;
  String? _error;
  EnglishAttempt? _attempt;
  final _watch = Stopwatch()..start();
  StreamSubscription<String>? _profiles;
  @override
  void initState() {
    super.initState();
    _audio = ref.read(englishAudioProvider(_audioKey));
    WidgetsBinding.instance.addObserver(this);
    _profiles = ProfileScope.changes.listen((_) {
      unawaited(_audio.stop());
      if (mounted) setState(() => _error = '档案已切换，请返回重新进入');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _watch.stop();
      unawaited(_audio.stop());
    } else {
      _watch.start();
    }
  }

  void _init(EnglishLesson lesson) {
    if (_targets != null) return;
    _targets = lesson.targets.where((t) => t.approved && t.hasSpeech).toList();
    try {
      _drafts.claim('englishSpeaking', scope: _scope);
      final draft = _drafts.get('englishSpeaking', scope: _scope);
      if (draft != null) {
        final fingerprints = englishObject(draft['fingerprints']);
        if (_targets!.any((t) => fingerprints[t.id] != t.fingerprint) ||
            fingerprints.length != _targets!.length) {
          throw const FormatException('课时内容已更新，旧录音仍保留在本机；请重新开始跟读');
        }
        _session = englishString(draft['sessionId']);
        _role = englishString(draft['role'] ?? '全部角色');
        _previousSeconds = englishInt(draft['seconds'] ?? 0, max: 86400);
        _index = englishInt(
          draft['index'],
          max: (_targets!.length - 1).clamp(0, 1000),
        );
        _recordings = englishObject(draft['recordings'])
            .map((k, v) => MapEntry(k, englishString(v, max: 160)));
        if (draft['attempt'] != null) {
          _attempt = EnglishAttempt.fromJson(draft['attempt']);
        }
      }
    } on Object catch (e) {
      _error = e is FormatException ? e.message.toString() : '跟读草稿暂时无法读取';
    }
  }

  Future<void> _saveDraft() async {
    _progress.check();
    _drafts.assertOwner('englishSpeaking', scope: _scope);
    await _drafts.save('englishSpeaking', {
      'sessionId': _session,
      'index': _index,
      'role': _role,
      'seconds': (_previousSeconds + _watch.elapsed.inSeconds).clamp(0, 86400),
      'recordings': _recordings,
      'fingerprints': {for (final t in _targets!) t.id: t.fingerprint},
      'attempt': _attempt?.toJson(),
    }, scope: _scope);
  }

  Future<void> _saveSegment(EnglishTarget target) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await _audio.saveRecording();
      final old = _recordings;
      _recordings = {...old, target.id: id};
      try {
        await _saveDraft();
      } on Object {
        _recordings = old;
        rethrow;
      }
      _audio.acknowledgeRecording();
      if (mounted) setState(() {});
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(EnglishLesson lesson) async {
    if (_busy || _recordings.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _audio.stop();
      final recorded = _targets!
          .where((t) => _recordings.containsKey(t.id))
          .toList();
      _attempt ??= EnglishAttempt(
        id: _session,
        lessonId: widget.lessonId,
        title: '${lesson.unitTitle} · ${lesson.title}',
        kind: 'speaking',
        completedAt: DateTime.now(),
        durationSeconds: (_previousSeconds + _watch.elapsed.inSeconds).clamp(
          0,
          86400,
        ),
        spokenTexts: recorded.map((t) => t.text).toList(),
        recordingIds: recorded.map((t) => _recordings[t.id]!).toList(),
        spokenFingerprints: {for (final t in recorded) t.id: t.fingerprint},
      );
      await _saveDraft();
      await _progress.complete(_attempt!);
      await _drafts.remove(
        'englishSpeaking',
        scope: _scope,
        sessionId: _session,
      );
      if (mounted) {
        context.replace(
          AppRoutes.englishBookOf(widget.bookId, attempt: _session),
        );
      }
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_audio.stop());
    _profiles?.cancel();
    _watch.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(englishAudioProvider(_audioKey)),
        voice = ref.watch(englishVoiceProvider),
        theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('跟读与回听')),
      body: SafeArea(
        top: false,
        child: EnglishCourseBody(
          bookId: widget.bookId,
          builder: (book, course) {
            final lesson = course.lesson(widget.lessonId);
            if (lesson == null) {
              return const AppEmptyState(icon: Icons.mic_none, title: '课时已移除');
            }
            _init(lesson);
            if (_error != null) {
              return AppEmptyState(
                icon: Icons.refresh,
                title: '需要重新开始',
                description: _error,
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await _drafts.remove('englishSpeaking', scope: _scope);
                        if (mounted) {
                          setState(() {
                            _targets = null;
                            _recordings = {};
                            _index = 0;
                            _role = '全部角色';
                            _previousSeconds = 0;
                            _watch.reset();
                            _attempt = null;
                            _session = newEnglishId();
                            _error = null;
                          });
                        }
                      } on Object catch (e) {
                        if (context.mounted) englishMessage(context, e);
                      }
                    },
                    child: const Text('重新开始'),
                  ),
                ],
              );
            }
            final targets = _targets!
                .where((t) => _role == '全部角色' || t.role == _role)
                .toList();
            if (targets.isEmpty) {
              return const AppEmptyState(
                icon: Icons.mic_none,
                title: '本课还没有可跟读的词句',
              );
            }
            _index = _index.clamp(0, targets.length - 1);
            final target = targets[_index], recording = _recordings[target.id];
            final roles = {
              '全部角色',
              ..._targets!.map((t) => t.role).where((r) => r.isNotEmpty),
            };
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                Text(
                  '${lesson.unitTitle} · ${lesson.title}',
                  style: theme.textTheme.titleMedium,
                ),
                if (roles.length > 1)
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _role,
                    items: [
                      for (final r in roles)
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: audio.recording || audio.hasUnsaved || _busy
                        ? null
                        : (r) async {
                            await audio.stop();
                            if (mounted) {
                              setState(() {
                                _role = r!;
                                _index = 0;
                              });
                              try {
                                await _saveDraft();
                              } on Object catch (e) {
                                if (context.mounted) englishMessage(context, e);
                              }
                            }
                          },
                  ),
                englishHeading(
                  context,
                  '第 ${_index + 1} / ${targets.length} 句',
                ),
                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (target.role.isNotEmpty) Text(target.role),
                      Text(target.text, style: theme.textTheme.headlineMedium),
                      if (target.meaning.isNotEmpty) Text(target.meaning),
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                if (audio.message.isNotEmpty) Text(audio.message),
                if (voice == null) const Text('没有英语音色，仍可录音。'),
                const SizedBox(height: SpacingTokens.md),
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: audio.recording || _busy
                          ? null
                          : () => audio.speak(target.text, voice),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('听示范'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || audio.busy || _attempt != null
                          ? null
                          : audio.recording
                          ? () => audio.finishRecording()
                          : () => audio.startRecording(),
                      icon: Icon(audio.recording ? Icons.stop : Icons.mic_none),
                      label: Text(
                        audio.recording
                            ? '结束录音'
                            : recording == null
                            ? '开始录音'
                            : '重新录音',
                      ),
                    ),
                    if (audio.hasUnsaved)
                      OutlinedButton(
                        onPressed: _busy ? null : () => audio.replay(),
                        child: const Text('试听刚才的录音'),
                      ),
                    if (audio.hasUnsaved)
                      OutlinedButton(
                        onPressed: _busy ? null : () => _saveSegment(target),
                        child: const Text('保存这一句'),
                      ),
                    if (recording != null)
                      OutlinedButton(
                        onPressed: audio.recording || _busy
                            ? null
                            : () => audio.replay(id: recording),
                        child: const Text('听我的录音'),
                      ),
                    if (audio.busy)
                      TextButton(
                        onPressed: () => audio.stop(),
                        child: const Text('停止播放'),
                      ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.lg),
                Wrap(
                  spacing: SpacingTokens.sm,
                  children: [
                    TextButton(
                      onPressed:
                          _index == 0 ||
                              audio.recording ||
                              audio.hasUnsaved ||
                              _busy
                          ? null
                          : () => _move(-1),
                      child: const Text('上一句'),
                    ),
                    TextButton(
                      onPressed:
                          _index == targets.length - 1 ||
                              audio.recording ||
                              audio.hasUnsaved ||
                              _busy
                          ? null
                          : () => _move(1),
                      child: const Text('下一句'),
                    ),
                  ],
                ),
                if (audio.hasUnsaved) const Text('先保存这一句，再切换到下一句。'),
                Text('已保存 ${_recordings.length} 句 · 录音仅存本机'),
                const SizedBox(height: SpacingTokens.md),
                FilledButton(
                  onPressed:
                      _busy ||
                          audio.recording ||
                          audio.hasUnsaved ||
                          _recordings.isEmpty
                      ? null
                      : () => _complete(lesson),
                  child: Text(_busy ? '正在保存…' : '完成本次跟读'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _move(int delta) async {
    try {
      await _audio.stop();
      _index += delta;
      await _saveDraft();
      if (mounted) setState(() {});
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    }
  }
}

class EnglishVoicePage extends ConsumerWidget {
  const EnglishVoicePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(englishVoiceProvider);
    return AppScaffold(
      appBar: AppBar(title: const Text('英语声音')),
      body: SafeArea(
        top: false,
        child: ref
            .watch(englishVoicesProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => AppEmptyState(
                icon: Icons.volume_off_outlined,
                title: '音色暂时无法读取',
                actions: [
                  TextButton(
                    onPressed: () => ref.invalidate(englishVoicesProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (voices) => ListView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                children: [
                  if (voices.isEmpty)
                    const AppEmptyState(
                      icon: Icons.volume_off_outlined,
                      title: '没有英语音色',
                      description: '安装系统英语语音包后刷新。',
                    ),
                  if (voices.isNotEmpty)
                    AppTileGroup(
                      children: [
                        for (final voice in voices)
                          AppTile(
                            icon:
                                selected != null &&
                                    englishVoiceKey(selected) ==
                                        englishVoiceKey(voice)
                                ? Icons.check_circle_outline
                                : Icons.volume_up_outlined,
                            iconColor: Theme.of(context).colorScheme.primary,
                            title: voice['name'] ?? '',
                            subtitle:
                                '${voice['locale']} · ${voice['network_required'] == 'true'
                                    ? '需要网络'
                                    : voice['network_required'] == 'false'
                                    ? '可离线合成'
                                    : '联网要求由系统决定'}',
                            onTap: () async {
                              try {
                                assertParentAccess(context);
                                final authorized = ParentAccessService.instance
                                    .captureAuthorization();
                                final key = englishVoiceSettingKey;
                                authorized();
                                await HiveBoxes.settings.put(
                                  key,
                                  jsonEncode(voice),
                                );
                              } on Object catch (e) {
                                if (context.mounted) englishMessage(context, e);
                              }
                            },
                          ),
                      ],
                    ),
                  TextButton(
                    onPressed: () => ref.invalidate(englishVoicesProvider),
                    child: const Text('刷新系统音色'),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
