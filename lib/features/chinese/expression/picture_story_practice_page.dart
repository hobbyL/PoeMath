import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/page_transitions.dart';

import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/picture_story_feedback_service.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_audio_service.dart';
import 'package:poemath/features/chinese/expression/picture_story_review_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_feedback.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

class PictureStoryPracticePage extends ConsumerStatefulWidget {
  const PictureStoryPracticePage({super.key, required this.promptId});

  final String promptId;

  @override
  ConsumerState<PictureStoryPracticePage> createState() =>
      _PictureStoryPracticePageState();
}

class _PictureStoryPracticePageState
    extends ConsumerState<PictureStoryPracticePage>
    with WidgetsBindingObserver {
  late final PictureStoryAudioService _audio;
  final _player = AudioPlayer();
  final _disposals = Expando<Future<void>>();
  final _textControllers = <String, TextEditingController>{};
  Timer? _timer;
  StreamSubscription<String>? _transcriptSubscription;
  StreamSubscription<void>? _playbackSubscription;
  SpeechRecognitionService? _speech;
  PictureStoryFeedbackService? _feedbackService;
  PictureStoryPracticeRecord? _record;
  PictureStoryPracticeRecord? _savedRecord;
  bool get _completed => _savedRecord?.status == 'completed';
  List<PictureStorySegment> _segments = [];
  String _liveText = '';
  String? _message;
  String? _playingId;
  int _elapsedSeconds = 0;
  int _generation = 0;
  int _playRequest = 0;
  int _draftRevision = 0;
  bool _foreground = false;
  bool _starting = false;
  bool _recording = false;
  bool _processing = false;
  bool _finishing = false;
  bool _deleting = false;
  bool _showHints = false;
  bool _usedHints = false;
  late final PictureStoryRepository _repository;
  late final String _profile;
  late final int _profileRevision;
  StreamSubscription<String>? _profileChanges;
  PictureStoryPrompt? _prompt;
  bool _promptReadFailed = false;

  bool get _canComplete =>
      _foreground &&
      !_starting &&
      !_recording &&
      !_processing &&
      !_finishing &&
      !_deleting &&
      !_completed &&
      _record != null;

  @override
  void initState() {
    super.initState();
    _profile = ProfileScope.currentId;
    _profileRevision = ProfileScope.revision;
    _profileChanges = ProfileScope.changes.listen(
      (_) => _invalidateRecording(),
    );
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(pictureStoryAudioServiceProvider);
    _repository = ref.read(pictureStoryRepositoryProvider);
    try {
      _prompt = _repository.findPrompt(widget.promptId)?.copyWith();
    } on Object {
      _promptReadFailed = true;
    }
    // 入口捕获不可变版本；失效题目不能创建一个没有原题的草稿。
    if (_prompt == null) return;
    _record = PictureStoryPracticeRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      profileId: ProfileScope.currentId,
      promptId: widget.promptId,
      promptVersion: _prompt!.version,
      startedAt: DateTime.now(),
      status: 'draft',
      segmentsJson: '[]',
    );
    unawaited(_saveDraft());
  }

  @override
  void dispose() {
    unawaited(_profileChanges?.cancel());
    unawaited(_playbackSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _invalidateRecording();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _player.dispose();
    super.dispose();
  }

  bool _current(int generation) =>
      mounted &&
      _foreground &&
      generation == _generation &&
      ProfileScope.currentId == _profile &&
      ProfileScope.revision == _profileRevision &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  Future<void> _disposeSpeech(SpeechRecognitionService speech) {
    return _disposals[speech] ??= () async {
      try {
        await speech.dispose();
      } on Object catch (error) {
        AppLogger.e('看图说话录音清理失败', tag: 'PictureStory', error: error);
      }
    }();
  }

  Future<void> _cancelSpeech(SpeechRecognitionService speech) async {
    try {
      await speech.cancel();
    } on Object catch (error) {
      AppLogger.e('看图说话取消录音失败', tag: 'PictureStory', error: error);
    } finally {
      await _disposeSpeech(speech);
    }
  }

  void _invalidateRecording() {
    ++_generation;
    _feedbackService?.cancel();
    _timer?.cancel();
    _timer = null;
    final subscription = _transcriptSubscription;
    _transcriptSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final speech = _speech;
    _speech = null;
    if (speech != null) unawaited(_cancelSpeech(speech));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      final active = _starting || _recording || _processing;
      _invalidateRecording();
      unawaited(_player.stop());
      // Persist only the segments already accepted while the page was active.
      if (!_finishing && !_deleting && !_completed) unawaited(_saveDraft());
      if (mounted) {
        setState(() {
          _starting = false;
          _recording = false;
          _processing = false;
          _finishing = false;
          _elapsedSeconds = 0;
          _liveText = '';
          _playingId = null;
          if (active) _message = '录音已取消，回到前台后请重新开始';
        });
      }
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startRecording() async {
    if (!_foreground ||
        _starting ||
        _recording ||
        _processing ||
        _finishing ||
        _deleting ||
        _completed) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _liveText = '';
      _message = null;
    });
    SpeechRecognitionService? speech;
    StreamSubscription<String>? subscription;
    var started = false;
    try {
      final factory = ref.read(speechRecognitionServiceFactoryProvider);
      // Each attempt owns its recorder; a late old start cannot cancel a new one.
      speech = factory();
      _speech = speech;
      await speech.initialize();
      if (!_current(generation)) return;
      if (speech is StreamingSpeechRecognitionService) {
        final streaming = speech as StreamingSpeechRecognitionService;
        subscription = streaming.transcriptStream.listen((String text) {
          if (_current(generation) &&
              (_starting || _recording || _processing)) {
            setState(() => _liveText = text);
          }
        });
        _transcriptSubscription = subscription;
      }
      await speech.start();
      if (!_current(generation)) return;
      started = true;
      _timer?.cancel();
      setState(() {
        _starting = false;
        _recording = true;
        _elapsedSeconds = 0;
        _liveText = '';
        _message = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_current(generation) || !_recording) {
          timer.cancel();
          return;
        }
        final next = _elapsedSeconds + 1;
        setState(() => _elapsedSeconds = next);
        if (next >= 60) unawaited(_finishSegment());
      });
    } on SpeechRecognitionException catch (error) {
      if (_current(generation)) setState(() => _message = error.message);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话开始录音失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (_current(generation)) {
        setState(() => _message = '无法开始录音，请检查麦克风权限');
      }
    } finally {
      if (!started) {
        if (identical(_transcriptSubscription, subscription)) {
          _transcriptSubscription = null;
        }
        if (subscription != null) unawaited(subscription.cancel());
        if (identical(_speech, speech)) _speech = null;
        if (speech != null) unawaited(_cancelSpeech(speech));
        if (_current(generation)) {
          setState(() {
            _starting = false;
            _recording = false;
            _processing = false;
          });
        }
      }
    }
  }

  Future<void> _finishSegment() async {
    final speech = _speech;
    final generation = _generation;
    if (!_current(generation) || !_recording || _processing || speech == null) {
      return;
    }
    final subscription = _transcriptSubscription;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _processing = true;
      _message = null;
    });
    try {
      SpeechRecognitionResult? result;
      Object? recognitionError;
      try {
        result = await speech.stop();
      } on Object catch (error) {
        recognitionError = error;
      }
      if (!_current(generation)) return;
      final retained = speech is RetainedAudioSpeechRecognitionService
          ? (speech as RetainedAudioSpeechRecognitionService).takeLastAudio()
          : null;
      if (retained == null || retained.isEmpty) {
        setState(() {
          _message = recognitionError is SpeechRecognitionException
              ? recognitionError.message
              : '录音没有保存成功，请再试一次';
        });
        return;
      }
      final segmentId =
          '${_record!.id}-${_segments.length + 1}-${DateTime.now().microsecondsSinceEpoch}';
      final audioPath = await _audio.savePcm16(id: segmentId, pcm: retained);
      if (!_current(generation)) {
        // The new file has no record reference; keep all earlier saved clips.
        await _audio.delete(audioPath);
        return;
      }
      final transcript = result?.text.trim().isNotEmpty == true
          ? result!.text.trim()
          : _liveText.trim();
      final segment = PictureStorySegment(
        id: segmentId,
        position: _segments.length,
        audioPath: audioPath,
        durationSeconds: (retained.length / 32000).ceil(),
        transcript: transcript,
        editedText: transcript,
        recognitionMode: result?.mode ?? 'unavailable',
        recognitionError: recognitionError?.toString(),
      );
      setState(() {
        _segments = [..._segments, segment];
        _processing = false;
        _elapsedSeconds = 0;
        _liveText = '';
        _message = recognitionError == null ? null : '录音已保存，但文字识别失败，可以手动填写。';
      });
      _controllerFor(segment);
      _record!.setSegments(_segments);
      await _saveDraft(generation: generation);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话保存录音失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (_current(generation)) {
        setState(() => _message = '录音保存失败，请检查设备空间后重试');
      }
    } finally {
      if (identical(_transcriptSubscription, subscription)) {
        _transcriptSubscription = null;
      }
      if (subscription != null) unawaited(subscription.cancel());
      if (identical(_speech, speech)) _speech = null;
      unawaited(_disposeSpeech(speech));
      if (_current(generation)) setState(() => _processing = false);
    }
  }

  TextEditingController _controllerFor(PictureStorySegment segment) {
    return _textControllers.putIfAbsent(
      segment.id,
      () => TextEditingController(text: segment.answerText),
    );
  }

  Future<void> _deleteSegment(PictureStorySegment segment) async {
    if (!_canComplete || !_segments.any((item) => item.id == segment.id)) {
      return;
    }
    final next = _record!.copy()
      ..setSegments(_segments.where((item) => item.id != segment.id));
    setState(() {
      _deleting = true;
      _message = null;
    });
    try {
      // Do not remove the only audio copy until its reference is durably removed.
      if (!await _saveDraft(snapshot: next)) return;
      _record = next;
      _segments = next.segments;
      if (mounted) {
        final controller = _textControllers.remove(segment.id);
        setState(() {});
        // 等旧 TextField 从树上移除，再释放它使用的控制器。
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller?.dispose(),
        );
      }
      try {
        if (mounted && _playingId == segment.id) {
          _playingId = null;
          await _playbackSubscription?.cancel();
          await _player.stop();
        }
        await _audio.delete(segment.audioPath);
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '录音片段已删除，音频文件清理失败',
          tag: 'PictureStory',
          error: error,
          stackTrace: stackTrace,
        );
        if (mounted) {
          setState(() => _message = '片段已删除，但录音文件清理失败');
        }
        return;
      }
      if (!mounted || !_foreground) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已删除这一段录音'),
          action: SnackBarAction(label: '知道了', onPressed: () {}),
        ),
      );
    } finally {
      _deleting = false;
      if (mounted) setState(() {});
    }
  }

  void _showCompletionHint(String message) {
    setState(() => _message = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _complete() async {
    if (!_canComplete) return;
    if (_segments.isEmpty) {
      _showCompletionHint('请先点击“说一说”，录制一段表达。');
      return;
    }
    final generation = _generation;
    _record!.setSegments(_segments);
    if (_record!.answerText.trim().isEmpty) {
      _showCompletionHint('请先填写或说出你的表达，再完成练习。');
      return;
    }
    setState(() {
      _finishing = true;
      _message = null;
    });
    final completed = _record!.copy();
    try {
      final image = await _captureIllustration();
      if (!_current(generation)) return;
      completed.setSegments(_segments);
      completed.status = 'completed';
      completed.completedAt = DateTime.now();
      completed.usedHints = _usedHints;
      completed.feedbackJson = unavailablePictureStoryFeedback(
        '表达已保存，可以回听或稍后重试点评。',
      );
      if (!await _saveDraft(generation: generation, snapshot: completed)) {
        return;
      }
      if (!_current(generation)) return;
      _record = completed;
      await _recordExpressionActivity(completed);
      if (!_current(generation)) return;
      final aiFeedback = await _generateAiFeedback(
        prompt: _prompt!,
        generation: generation,
        image: image,
      );
      if (!_current(generation)) return;
      if (aiFeedback != null) {
        final withAi = completed.copy();
        withAi.feedbackJson = aiFeedback;
        final saved = await _saveDraft(
          generation: generation,
          snapshot: withAi,
        );
        if (_current(generation)) {
          if (saved) {
            _record = withAi;
          } else {
            _message = '表达已保存，AI 点评未能保存，可稍后重试。';
          }
        }
      }
    } finally {
      if (_current(generation)) setState(() => _finishing = false);
    }
  }

  Future<void> _recordExpressionActivity(
    PictureStoryPracticeRecord record,
  ) async {
    final completedAt = record.completedAt;
    if (completedAt == null) return;
    try {
      await ref
          .read(learningActivityRepositoryProvider)
          .record(
            id: 'picture-story:${record.id}',
            activityType: LearningActivityType.pictureStoryExpression,
            totalItems: 1,
            successfulItems: 1,
            starsEarned: 0,
            durationSeconds: record.totalDurationSeconds,
            completedAt: completedAt,
          );
      ref.invalidate(todayLearningActivityCountsProvider);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图表达完成活动保存失败',
        tag: 'PictureStoryPractice',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _saveDraft({
    int? generation,
    PictureStoryPracticeRecord? snapshot,
  }) async {
    final record = (snapshot ?? _record)?.copy();
    if (record == null) return false;
    final revision = ++_draftRevision;
    void check() {
      if (ProfileScope.currentId != _profile ||
          ProfileScope.revision != _profileRevision) {
        throw const _PictureStoryRecordingCancelled();
      }
      if (generation != null && !_current(generation)) {
        throw const _PictureStoryRecordingCancelled();
      }
    }

    try {
      await _repository.save(record, check: check);
      if (revision == _draftRevision) {
        _savedRecord = record;
        if (mounted && _foreground) setState(() {});
      }
      return true;
    } on _PictureStoryRecordingCancelled {
      return false;
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话记录保存失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted &&
          _foreground &&
          revision == _draftRevision &&
          (generation == null || _current(generation))) {
        setState(() => _message = '练习暂时没有保存，请检查设备空间后重试');
      }
      return false;
    }
  }

  Future<Uint8List?> _captureIllustration() async {
    final prompt = _prompt;
    if (!mounted || prompt == null) return null;
    if (prompt.image.isLocal) {
      try {
        // AI 使用完整的永久图片，不采集列表裁切或图片加载占位。
        return await ref
            .read(pictureStoryImageServiceProvider)
            .readForVision(prompt.image.value);
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '读取评价题图失败',
          tag: 'PictureStory',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }
    try {
      return await PictureStoryIllustration.renderForVision(
        kind: prompt.image.value,
        scheme: Theme.of(context).colorScheme,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话图片采集失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<String?> _generateAiFeedback({
    required PictureStoryPrompt prompt,
    required int generation,
    required Uint8List? image,
  }) async {
    final service = _feedbackService = PictureStoryFeedbackService(
      settings: ref.read(settingsRepositoryProvider),
      httpClient: ref.read(llmExplainHttpClientProvider),
      onSelectionChanged: () {
        if (_current(generation)) {
          ref.read(llmSelectionVersionProvider.notifier).state++;
        }
      },
    );
    final answer = _record!.answerText;
    if (!_current(generation)) return null;
    return service.evaluate(
      prompt: prompt,
      answer: answer,
      image: image,
      isActive: () => _current(generation),
    );
  }

  Future<void> _play(PictureStorySegment segment) async {
    final generation = _generation;
    final request = ++_playRequest;
    bool canPlay() =>
        _current(generation) &&
        !_deleting &&
        request == _playRequest &&
        _segments.any((item) => item.id == segment.id);
    if (!canPlay()) return;
    try {
      final exists = await File(segment.audioPath).exists();
      if (!canPlay()) return;
      if (!exists) {
        setState(() => _message = '录音文件已清理，文字记录仍然保留');
        return;
      }
      await _playbackSubscription?.cancel();
      await _player.stop();
      if (!canPlay()) return;
      if (_playingId == segment.id) {
        setState(() => _playingId = null);
        return;
      }
      setState(() => _playingId = segment.id);
      _playbackSubscription = _player.onPlayerComplete.listen((_) {
        if (canPlay() && _playingId == segment.id) {
          setState(() => _playingId = null);
        }
      });
      await _player.play(DeviceFileSource(segment.audioPath));
      // 准备播放期间可能已删除此片段；迟到结果不能重新播放它。
      if (!canPlay() && mounted && request == _playRequest) {
        await _player.stop();
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '录音播放失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (canPlay()) {
        setState(() {
          _playingId = null;
          _message = '录音暂时无法播放，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = _prompt;
    if (prompt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('看图说话')),
        body: PictureStoryUnavailableView(
          message: _promptReadFailed ? '题目暂时无法读取，请返回题库重试。' : '题目不存在，请返回选择其他题目。',
        ),
      );
    }
    if (_completed && !_finishing) {
      return _buildResult(theme, prompt, _savedRecord!);
    }
    return PictureStorySceneScaffold(
      image: prompt.image,
      semanticLabel: '看图说话练习：${prompt.title}',
      actions: [
        IconButton(
          onPressed: () => setState(() {
            _showHints = !_showHints;
            if (_showHints) _usedHints = true;
          }),
          isSelected: _showHints,
          tooltip: _showHints ? '隐藏提示' : '显示提示',
          icon: const Icon(Icons.lightbulb_outline),
          selectedIcon: const Icon(Icons.tips_and_updates_outlined),
        ),
        IconButton(
          onPressed: _canComplete ? _complete : null,
          icon: const Icon(Icons.check_outlined),
          tooltip: '完成练习',
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= ResponsiveLayout.wideBreakpoint;
          final content = _buildContent(theme, prompt);
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content[0]),
                    const SizedBox(width: SpacingTokens.lg),
                    Expanded(child: content[1]),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content[0],
                    const SizedBox(height: SpacingTokens.md),
                    content[1],
                  ],
                );
        },
      ),
    );
  }

  Widget _buildResult(
    ThemeData theme,
    PictureStoryPrompt prompt,
    PictureStoryPracticeRecord record,
  ) => Scaffold(
    appBar: AppBar(title: const Text('本次表达')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          ColoredCard(
            color: theme.colorScheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('练习已完成', style: theme.textTheme.titleLarge),
                Text(prompt.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: SpacingTokens.sm),
                Text(record.answerText),
                if (!_finishing)
                  PictureStoryFeedback(feedbackJson: record.feedbackJson),
                if (_finishing) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  const LinearProgressIndicator(semanticsLabel: '正在点评'),
                  const Text('表达已保存，正在等待 AI 点评…'),
                ],
                const SizedBox(height: SpacingTokens.md),
                FilledButton.tonalIcon(
                  onPressed: _finishing
                      ? null
                      : () async {
                          await _player.stop();
                          if (!mounted) return;
                          await Navigator.of(context).push(
                            fadeSlideRoute<void>(
                              builder: (_) =>
                                  PictureStoryReviewPage(recordId: record.id),
                            ),
                          );
                          if (!mounted ||
                              ProfileScope.currentId != _profile ||
                              ProfileScope.revision != _profileRevision) {
                            return;
                          }
                          setState(() {
                            _savedRecord = _repository.find(record.id)?.copy();
                            _record = _savedRecord?.copy();
                            _playingId = null;
                          });
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改表达并重新点评'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(_message!),
                ],
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          Text('回听最初的表达', style: theme.textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.sm),
          for (final segment in record.segments)
            AppTile(
              icon: _playingId == segment.id
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
              iconColor: theme.colorScheme.primary,
              title:
                  '第 ${segment.position + 1} 段 · ${segment.durationSeconds} 秒',
              subtitle: segment.answerText.isEmpty
                  ? '未填写文字'
                  : segment.answerText,
              onTap: () => _play(segment),
            ),
          const SizedBox(height: SpacingTokens.md),
          FilledButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.chineseSectionOf('expression'));
              }
            },
            child: const Text('完成'),
          ),
        ],
      ),
    ),
  );

  List<Widget> _buildContent(ThemeData theme, PictureStoryPrompt prompt) {
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: TypographyTokens.fsBodySmall,
    );
    return [
      ColoredCard(
        color: theme.colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt.title, style: titleStyle),
            const SizedBox(height: SpacingTokens.sm),
            Text('先观察，再说一说', style: bodyStyle),
            const SizedBox(height: SpacingTokens.sm),
            for (final question in prompt.questions)
              Padding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                child: Text('· $question', style: bodyStyle),
              ),
            if (_showHints) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(prompt.sceneFacts.join('\n'), style: bodyStyle),
            ],
          ],
        ),
      ),
      ColoredCard(
        color: theme.colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('我的表达', style: titleStyle),
            const SizedBox(height: SpacingTokens.sm),
            if (_segments.isEmpty && !_recording && !_processing)
              Text('录完一段后，识别文字会自动填在这里。你可以修改文字。', style: bodyStyle),
            for (final segment in _segments)
              _segmentTile(theme, segment, bodyStyle),
            if (_recording)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                child: Text(
                  _liveText.isEmpty
                      ? '正在听你说… $_elapsedSeconds/60 秒'
                      : _liveText,
                  style: bodyStyle?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            if (_starting || _processing || _finishing || _deleting)
              const LinearProgressIndicator(),
            if (_finishing) const Text('正在整理本次反馈…'),
            if (_message != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(
                _message!,
                style: bodyStyle?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: SpacingTokens.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        !_foreground ||
                            _starting ||
                            _processing ||
                            _finishing ||
                            _deleting
                        ? null
                        : (_recording ? _finishSegment : _startRecording),
                    icon: Icon(
                      _recording ? Icons.stop : Icons.mic_none_outlined,
                    ),
                    label: Text(
                      _starting ? '正在准备…' : (_recording ? '说好了' : '说一说'),
                    ),
                  ),
                ),
                if (_segments.isNotEmpty) ...[
                  const SizedBox(width: SpacingTokens.sm),
                  IconButton(
                    onPressed: _canComplete ? _complete : null,
                    icon: const Icon(Icons.done_all_outlined),
                    tooltip: '完成练习',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _segmentTile(
    ThemeData theme,
    PictureStorySegment segment,
    TextStyle? bodyStyle,
  ) {
    final controller = _controllerFor(segment);
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Column(
        children: [
          const Divider(height: SpacingTokens.md),
          Row(
            children: [
              IconButton(
                onPressed: _deleting ? null : () => _play(segment),
                icon: Icon(
                  _playingId == segment.id
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                tooltip: '播放',
              ),
              Expanded(
                child: Text(
                  '第 ${segment.position + 1} 段 · ${segment.durationSeconds} 秒',
                  style: bodyStyle,
                ),
              ),
              IconButton(
                onPressed: _canComplete ? () => _deleteSegment(segment) : null,
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除这段',
              ),
            ],
          ),
          TextField(
            controller: controller,
            readOnly: _finishing || _deleting,
            style: bodyStyle,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '识别文字（可修改）'),
            onChanged: (value) {
              if (_deleting || _finishing) return;
              final index = _segments.indexWhere(
                (item) => item.id == segment.id,
              );
              if (index < 0) return;
              _segments[index] = _segments[index].copyWith(editedText: value);
              _record?.setSegments(_segments);
              unawaited(_saveDraft());
            },
          ),
          if (segment.recognitionError != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('识别失败，可直接填写答案', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: SpacingTokens.xs),
        ],
      ),
    );
  }
}

class _PictureStoryRecordingCancelled implements Exception {
  const _PictureStoryRecordingCancelled();
}
