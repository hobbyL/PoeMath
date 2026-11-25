import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_widgets.dart';

class EnglishPracticePage extends ConsumerStatefulWidget {
  const EnglishPracticePage({
    super.key,
    required this.bookId,
    required this.kind,
    this.lessonId,
    this.due = false,
    this.retry = false,
    this.targetKey,
  });
  final String bookId, kind;
  final String? lessonId;
  final bool due, retry;
  final String? targetKey;
  @override
  ConsumerState<EnglishPracticePage> createState() =>
      _EnglishPracticePageState();
}

class _EnglishPracticePageState extends ConsumerState<EnglishPracticePage>
    with WidgetsBindingObserver {
  late final EnglishAudio _audio;
  late final _audioKey = englishAudioKey(widget.bookId);
  late final EnglishProgressRepository _progress = ref.read(
    englishProgressRepositoryProvider(widget.bookId),
  )!;
  final _drafts = PracticeDraftRepository();
  late final String _scope =
      '${widget.bookId}/${widget.lessonId ?? 'all'}/${widget.kind}/${widget.due}/${widget.retry}/${widget.targetKey ?? 'all'}';
  String _session = newEnglishId();
  List<EnglishQuestion>? _questions;
  List<EnglishAnswer> _answers = [];
  final _input = TextEditingController();
  List<int> _tokens = [];
  bool _hint = false, _heard = false, _busy = false;
  String? _error;
  EnglishAttempt? _attempt;
  EnglishAnswer? _feedback;
  final _watch = Stopwatch()..start();
  int _previousSeconds = 0;
  StreamSubscription<String>? _profiles;
  EnglishPracticeKind? get _kind => EnglishPracticeKind.values
      .where((k) => k.name == widget.kind)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _audio = ref.read(englishAudioProvider(_audioKey));
    WidgetsBinding.instance.addObserver(this);
    _profiles = ProfileScope.changes.listen((_) {
      unawaited(_audio.stop());
      if (mounted) setState(() => _error = '学习档案已变化，请返回重新进入');
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

  void _init(EnglishCourse course, Map<String, String>? voice) {
    if (_questions != null || _kind == null) return;
    _questions = [];
    try {
      _drafts.claim('englishPractice', scope: _scope);
      final draft = _drafts.get('englishPractice', scope: _scope);
      if (draft != null) {
        _questions = englishList(
          draft['questions'],
          EnglishQuestion.fromJson,
          max: 10,
        );
        _answers = englishList(
          draft['answers'],
          EnglishAnswer.fromJson,
          max: 10,
        );
        if (_questions!.any((q) {
              final t = course.target(q.lessonId, q.target.id);
              return t == null ||
                  !t.isAvailableForChild ||
                  t.fingerprint != q.target.fingerprint;
            }) ||
            _answers.length > _questions!.length ||
            _answers.asMap().entries.any(
              (e) => e.value.question.id != _questions![e.key].id,
            )) {
          throw const FormatException('内容已经更新，请重新开始本轮。过去的学习记录仍保留。');
        }
        _session = englishString(draft['sessionId']);
        _input.text = englishString(draft['input'], empty: true);
        _tokens = englishList(
          draft['tokens'],
          (v) => englishInt(v, max: 100),
          max: 100,
        );
        if (_answers.length < _questions!.length &&
            _tokens.any(
              (i) => i >= _questions![_answers.length].options.length,
            )) {
          throw const FormatException('词块草稿无效');
        }
        _hint = draft['hint'] == true;
        _previousSeconds = englishInt(draft['seconds'], max: 86400);
        if (draft['attempt'] != null) {
          _attempt = EnglishAttempt.fromJson(draft['attempt']);
        }
      } else {
        final due = widget.targetKey != null
            ? {widget.targetKey!}
            : widget.due
            ? _progress.dueKeys(course, DateTime.now())
            : widget.retry
            ? _progress.retryKeys(course)
            : null;
        _questions = buildEnglishQuestions(
          course,
          _kind!,
          lessonId: widget.lessonId,
          targetKeys: due,
          voiceKey: voice == null ? null : englishVoiceKey(voice),
          seed: DateTime.now().millisecondsSinceEpoch,
        ).take(10).toList();
      }
    } on Object catch (e) {
      _error = e is FormatException ? e.message.toString() : '草稿读取失败，请重试或重新开始';
    }
  }

  Future<void> _checkpoint({
    List<EnglishAnswer>? answers,
    String? input,
    List<int>? tokens,
    bool? hint,
  }) async {
    _progress.check();
    _drafts.assertOwner('englishPractice', scope: _scope);
    await _drafts.save('englishPractice', {
      'sessionId': _session,
      'lessonId': widget.lessonId,
      'practiceKind': widget.kind,
      'due': widget.due,
      'retry': widget.retry,
      'targetKey': widget.targetKey,
      'questions': _questions!.map((q) => q.toJson()).toList(),
      'answers': (answers ?? _answers).map((a) => a.toJson()).toList(),
      'input': input ?? _input.text,
      'tokens': tokens ?? _tokens,
      'hint': hint ?? _hint,
      'seconds': (_previousSeconds + _watch.elapsed.inSeconds).clamp(0, 86400),
      'attempt': _attempt?.toJson(),
    }, scope: _scope);
  }

  Future<void> _change({String? input, List<int>? tokens, bool? hint}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _checkpoint(input: input, tokens: tokens, hint: hint);
      if (mounted) {
        setState(() {
          if (input != null) _input.text = input;
          if (tokens != null) _tokens = tokens;
          if (hint != null) _hint = hint;
        });
      }
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answer(EnglishQuestion q, {bool skip = false}) async {
    if (_busy || _feedback != null) return;
    setState(() => _busy = true);
    try {
      await _audio.stop();
      final text = _answerText(q);
      if (!skip && !q.parentCheck && text.trim().isEmpty) {
        throw const FormatException('先选出或填入你的答案');
      }
      final answer = EnglishAnswer(
        question: q,
        answer: skip ? '' : text,
        correct: skip || q.parentCheck ? null : q.accepts(text),
        hinted: _hint,
        skipped: skip,
      );
      final next = [..._answers, answer];
      await _checkpoint(answers: next, input: '', tokens: [], hint: false);
      if (mounted) {
        setState(() {
          _answers = next;
          _feedback = answer;
          _input.clear();
          _tokens = [];
          _hint = false;
          _heard = false;
        });
      }
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _answerText(EnglishQuestion q) => _isTokens(q)
      ? _tokens
            .map((i) => q.options[i])
            .join(q.kind == EnglishPracticeKind.spelling ? '' : ' ')
      : _input.text;
  bool _isTokens(EnglishQuestion q) =>
      q.kind == EnglishPracticeKind.sentence ||
      q.kind == EnglishPracticeKind.spelling;
  Future<void> _finish(EnglishCourse course) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _attempt ??= EnglishAttempt(
        id: _session,
        lessonId: widget.lessonId ?? _questions!.first.lessonId,
        title: widget.lessonId == null
            ? _kind!.label
            : '${course.lesson(widget.lessonId!)?.unitTitle ?? ''} · ${course.lesson(widget.lessonId!)?.title ?? ''} · ${_kind!.label}',
        kind: 'practice',
        completedAt: DateTime.now(),
        durationSeconds: (_previousSeconds + _watch.elapsed.inSeconds).clamp(
          0,
          86400,
        ),
        answers: _answers,
      );
      await _checkpoint();
      await _progress.complete(_attempt!);
      await _drafts.remove(
        'englishPractice',
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
    _input.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voices = ref.watch(englishVoicesProvider);
    final audio = ref.watch(englishAudioProvider(_audioKey)),
        voice = ref.watch(englishVoiceProvider),
        theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: Text(_kind?.label ?? '英语练习')),
      body: SafeArea(
        top: false,
        child: EnglishCourseBody(
          bookId: widget.bookId,
          builder: (book, course) {
            if (_kind == null) {
              return const AppEmptyState(
                icon: Icons.extension_outlined,
                title: '练习类型不存在',
              );
            }
            if (_kind == EnglishPracticeKind.listening &&
                voices.isLoading &&
                _questions == null) {
              return const Center(child: CircularProgressIndicator());
            }
            _init(course, voice);
            if (_error != null) {
              return AppEmptyState(
                icon: Icons.refresh,
                title: '本轮需要重新开始',
                description: _error,
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await _drafts.remove('englishPractice', scope: _scope);
                        if (mounted) {
                          setState(() {
                            _questions = null;
                            _answers = [];
                            _tokens = [];
                            _input.clear();
                            _hint = false;
                            _error = null;
                            _attempt = null;
                            _feedback = null;
                            _session = newEnglishId();
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
            if (_questions!.isEmpty) {
              return const AppEmptyState(
                icon: Icons.task_alt,
                title: '目前没有可练题目',
                description: '听辨题需先核对英语示范。',
              );
            }
            final feedback = _feedback;
            if (feedback != null) {
              return ListView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                children: [
                  Text(
                    feedback.skipped
                        ? '这题已跳过'
                        : feedback.question.parentCheck
                        ? '已记录，等待家长核对'
                        : feedback.correct == true
                        ? '答对了'
                        : '再看看课本里的答案',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  if (!feedback.skipped && !feedback.question.parentCheck)
                    Text('课本答案：${feedback.question.answers.join(' / ')}'),
                  if (feedback.hinted) const Text('用过提示，已安排复习。'),
                  const SizedBox(height: SpacingTokens.md),
                  FilledButton(
                    onPressed: () => setState(() => _feedback = null),
                    child: Text(
                      _answers.length == _questions!.length ? '查看本轮结果' : '下一题',
                    ),
                  ),
                ],
              );
            }
            if (_answers.length == _questions!.length) {
              return ListView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                children: [
                  Text('这一轮完成了', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    '独立答对 ${_answers.where((a) => a.objectiveCorrect).length} 项 · 跳过 ${_answers.where((a) => a.skipped).length} 项',
                  ),
                  if (_answers.any((a) => a.question.parentCheck && !a.skipped))
                    const Text('开放题已记录，等待家长核对。'),
                  const SizedBox(height: SpacingTokens.md),
                  FilledButton(
                    onPressed: _busy ? null : () => _finish(course),
                    child: Text(_busy ? '正在保存…' : '保存本轮结果'),
                  ),
                ],
              );
            }
            final q = _questions![_answers.length], tokens = _isTokens(q);
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.prompt, style: theme.textTheme.headlineSmall),
                      if (q.kind == EnglishPracticeKind.original &&
                          q.target.picture != null)
                        EnglishSourceImage(
                          book: book,
                          source: q.target.picture!,
                        ),
                      if (q.audioText != null) ...[
                        const SizedBox(height: SpacingTokens.md),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (voice == null ||
                                      englishVoiceKey(voice) != q.voiceKey) {
                                    englishMessage(
                                      context,
                                      const FormatException('音色已改变，请重新开始本轮'),
                                    );
                                    return;
                                  }
                                  final heard = await audio.speak(
                                    q.audioText!,
                                    voice,
                                  );
                                  if (mounted) setState(() => _heard = heard);
                                },
                          icon: const Icon(Icons.volume_up_outlined),
                          label: const Text('播放题目'),
                        ),
                        if (audio.message.isNotEmpty) Text(audio.message),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                if (tokens) ...[
                  ColoredCard(
                    color: theme.colorScheme.secondary,
                    child: Text(
                      _tokens.isEmpty ? '点选下面的词块' : _answerText(q),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Wrap(
                    spacing: SpacingTokens.sm,
                    runSpacing: SpacingTokens.sm,
                    children: [
                      for (var i = 0; i < q.options.length; i++)
                        OutlinedButton(
                          key: ValueKey('english-token-$i'),
                          onPressed: _busy || _tokens.contains(i)
                              ? null
                              : () => _change(tokens: [..._tokens, i]),
                          child: Text(
                            q.options[i] == ' ' ? '空格' : q.options[i],
                          ),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: _busy || _tokens.isEmpty
                        ? null
                        : () => _change(tokens: [..._tokens]..removeLast()),
                    child: const Text('撤回一个'),
                  ),
                ] else if (q.options.isNotEmpty && !q.parentCheck) ...[
                  for (final option in q.options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _change(input: option),
                        style: _input.text == option
                            ? OutlinedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SpacingTokens.sm,
                          ),
                          child: Text(option),
                        ),
                      ),
                    ),
                ] else
                  TextField(
                    controller: _input,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: q.parentCheck ? '记录你的回答或完成情况' : '输入答案',
                    ),
                    onChanged: (value) {
                      unawaited(
                        _checkpoint(input: value).catchError((Object e) {
                          if (context.mounted) englishMessage(context, e);
                        }),
                      );
                    },
                  ),
                if (_hint)
                  Text(
                    q.parentCheck
                        ? '可以对照原书完成，再请家长核对。'
                        : '提示：${q.answers.join(' / ')}',
                  ),
                const SizedBox(height: SpacingTokens.md),
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.sm,
                  children: [
                    FilledButton(
                      onPressed: _busy || q.audioText != null && !_heard
                          ? null
                          : () => _answer(q),
                      child: Text(q.parentCheck ? '记录完成' : '提交答案'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _change(hint: true),
                      child: const Text('看提示'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _answer(q, skip: true),
                      child: const Text('跳过'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
