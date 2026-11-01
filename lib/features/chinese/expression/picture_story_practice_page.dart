import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_audio_service.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';

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
  final _illustrationKey = GlobalKey();
  Timer? _timer;
  StreamSubscription<String>? _transcriptSubscription;
  SpeechRecognitionService? _speech;
  PictureStoryPracticeRecord? _record;
  List<PictureStorySegment> _segments = [];
  String _liveText = '';
  String? _message;
  String? _playingId;
  int _elapsedSeconds = 0;
  int _generation = 0;
  int _draftRevision = 0;
  bool _foreground = false;
  bool _starting = false;
  bool _recording = false;
  bool _processing = false;
  bool _finishing = false;
  bool _showHints = false;
  bool _usedHints = false;
  late final PictureStoryRepository _repository;
  PictureStoryPrompt? _prompt;
  bool _promptReadFailed = false;

  @override
  void initState() {
    super.initState();
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
    WidgetsBinding.instance.removeObserver(this);
    _invalidateRecording();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _player.dispose();
    super.dispose();
  }

  bool _current(int generation) =>
      mounted && _foreground && generation == _generation;

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
      unawaited(_saveDraft());
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
    if (!_foreground || _starting || _recording || _processing || _finishing) {
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
    if (_record == null) return;
    final removedIndex = _segments.indexOf(segment);
    setState(() {
      _segments = [
        for (var i = 0; i < _segments.length; i++)
          if (i != removedIndex) _segments[i].copyWith(position: i),
      ];
    });
    _record!.setSegments(_segments);
    await _saveDraft();
    await _audio.delete(segment.audioPath);
    _textControllers.remove(segment.id)?.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已删除这一段录音'),
        action: SnackBarAction(label: '知道了', onPressed: () {}),
      ),
    );
  }

  Future<void> _complete() async {
    if (!_foreground ||
        _starting ||
        _finishing ||
        _record == null ||
        _segments.isEmpty ||
        _recording ||
        _processing) {
      return;
    }
    final generation = _generation;
    setState(() => _finishing = true);
    final before = _record!.copy();
    try {
      _record!.setSegments(_segments);
      _record!.status = 'completed';
      _record!.completedAt = DateTime.now();
      _record!.usedHints = _usedHints;
      _record!.feedbackJson = jsonEncode(<String, Object>{
        'source': 'local',
        'highlights': [
          '你愿意把看到的内容说出来了。',
          if (_segments.length > 1) '你用了多段话补充细节。',
        ],
        'suggestion': _record!.answerText.trim().isEmpty
            ? '可以先填写听到的文字，再请家长一起回听。'
            : '再补充一个动作或人物的心情，故事会更生动。',
      });
      if (!await _saveDraft(generation: generation)) {
        if (!_current(generation)) return;
        _record = before;
        return;
      }
      if (!_current(generation)) return;
      final aiFeedback = await _generateAiFeedback(
        prompt: _prompt!,
        generation: generation,
      );
      if (!_current(generation)) return;
      if (aiFeedback != null) {
        _record!.feedbackJson = jsonEncode(<String, Object>{
          'source': 'vision',
          'text': aiFeedback,
        });
        await _saveDraft(generation: generation);
      }
      if (!_current(generation)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本次练习已保存')));
      context.pop();
    } finally {
      if (_current(generation)) setState(() => _finishing = false);
    }
  }

  Future<bool> _saveDraft({int? generation}) async {
    final record = _record?.copy();
    if (record == null) return false;
    final revision = ++_draftRevision;
    void check() {
      if (generation != null && !_current(generation)) {
        throw const _PictureStoryRecordingCancelled();
      }
    }

    try {
      await _repository.save(record, check: check);
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
    final renderObject = _illustrationKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    try {
      final image = await renderObject.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
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
  }) async {
    final image = await _captureIllustration();
    if (image == null || !_current(generation)) return null;
    final settings = ref.read(settingsRepositoryProvider);
    try {
      final config =
          await settings.readLlmConfigForScenario(LlmScenario.assistant);
      if (config == null || !config.supportsVision || !_current(generation)) {
        return null;
      }
      final client = createRuntimeLlmClient(
        httpClient: ref.read(llmExplainHttpClientProvider),
        settings: settings,
        isActive: () => _current(generation),
        onSelectionChanged: () {
          if (_current(generation)) {
            ref.read(llmSelectionVersionProvider.notifier).state++;
          }
        },
      );
      final promptText =
          '请评价孩子的看图说话：${_record?.answerText ?? ''}\n练习目标：${prompt.goals.join('；')}';
      try {
        final completion = await client.chatComplete(
          config: config,
          systemPrompt:
              '你是小学语文口语表达老师。请根据图片和孩子的表达，给出简短、具体、鼓励性的中文反馈。先说一个做得好的地方，再给一个可执行的改进建议。只输出两句话，不要编造图片中看不到的细节。',
          messages: [
            ChatMessage(
              role: ChatRole.user,
              content: promptText,
              contentParts: [
                <String, Object?>{'type': 'text', 'text': promptText},
                <String, Object?>{
                  'type': 'image_url',
                  'image_url': <String, String>{
                    'url': 'data:image/png;base64,${base64Encode(image)}',
                  },
                },
              ],
            ),
          ],
          maxTokens: 240,
          requiresVision: true,
        );
        final text = completion.content?.trim();
        return text == null || text.isEmpty ? null : text;
      } finally {
        client.close();
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话 AI 反馈失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _play(PictureStorySegment segment) async {
    final generation = _generation;
    if (!_current(generation)) return;
    if (!await File(segment.audioPath).exists()) {
      if (_current(generation)) {
        setState(() => _message = '录音文件已清理，文字记录仍然保留');
      }
      return;
    }
    if (!_current(generation)) return;
    await _player.stop();
    if (!_current(generation)) return;
    if (_playingId == segment.id) {
      setState(() => _playingId = null);
      return;
    }
    setState(() => _playingId = segment.id);
    await _player.play(DeviceFileSource(segment.audioPath));
    _player.onPlayerComplete.first.then((_) {
      if (_current(generation) && _playingId == segment.id) {
        setState(() => _playingId = null);
      }
    });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(prompt.title),
        actions: [
          IconButton(
            onPressed: _complete,
            icon: const Icon(Icons.check_outlined),
            tooltip: '完成练习',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= ResponsiveLayout.wideBreakpoint;
            final content = _buildContent(theme, prompt);
            return wide
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: content[0]),
                        const SizedBox(width: SpacingTokens.lg),
                        Expanded(child: content[1]),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: [
                      content[0],
                      const SizedBox(height: SpacingTokens.md),
                      content[1],
                    ],
                  );
          },
        ),
      ),
    );
  }

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
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                RepaintBoundary(
                  key: _illustrationKey,
                  child: PictureStoryImageView(image: prompt.image),
                ),
                Positioned(
                  top: SpacingTokens.sm,
                  right: SpacingTokens.sm,
                  child: IconButton(
                    onPressed: () => setState(() {
                      _showHints = !_showHints;
                      if (_showHints) _usedHints = true;
                    }),
                    isSelected: _showHints,
                    tooltip: _showHints ? '隐藏提示' : '显示提示',
                    icon: const Icon(Icons.lightbulb_outline),
                    selectedIcon: Icon(
                      Icons.tips_and_updates_outlined,
                      color: theme.brightness == Brightness.dark
                          ? ColorTokens.mathYellow
                          : ColorTokens.hintAmber,
                      shadows: const [
                        Shadow(
                          color: ColorTokens.mathYellow,
                          blurRadius: SpacingTokens.sm,
                        ),
                        Shadow(
                          color: ColorTokens.mathYellow,
                          blurRadius: SpacingTokens.lg,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '先观察，再说一说',
                    style: titleStyle,
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  for (final question in prompt.questions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                      child: Text(
                        '· $question',
                        style: bodyStyle,
                      ),
                    ),
                  if (_showHints) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      prompt.sceneFacts.join('；'),
                      style: bodyStyle,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ColoredCard(
        color: theme.colorScheme.secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '我的表达',
              style: titleStyle,
            ),
            const SizedBox(height: SpacingTokens.sm),
            if (_segments.isEmpty && !_recording && !_processing)
              Text(
                '录完一段后，识别文字会自动填在这里。你可以修改文字。',
                style: bodyStyle,
              ),
            for (final segment in _segments)
              _segmentTile(theme, segment, bodyStyle),
            if (_recording)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SpacingTokens.sm,
                ),
                child: Text(
                  _liveText.isEmpty
                      ? '正在听你说… $_elapsedSeconds/60 秒'
                      : _liveText,
                  style: bodyStyle?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            if (_starting || _processing) const LinearProgressIndicator(),
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
                        !_foreground || _starting || _processing || _finishing
                            ? null
                            : (_recording ? _finishSegment : _startRecording),
                    icon: Icon(
                      _recording ? Icons.stop : Icons.mic_none_outlined,
                    ),
                    label: Text(
                      _starting ? '正在准备…' : (_recording ? '说好了' : '开始录音'),
                    ),
                  ),
                ),
                if (_segments.isNotEmpty) ...[
                  const SizedBox(width: SpacingTokens.sm),
                  IconButton(
                    onPressed: _complete,
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
                onPressed: () => _play(segment),
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
                onPressed: _processing ? null : () => _deleteSegment(segment),
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除这段',
              ),
            ],
          ),
          TextField(
            controller: controller,
            style: bodyStyle,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '识别文字（可修改）'),
            onChanged: (value) {
              final index =
                  _segments.indexWhere((item) => item.id == segment.id);
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
