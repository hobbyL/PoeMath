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
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_audio_service.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';

class PictureStoryPracticePage extends ConsumerStatefulWidget {
  const PictureStoryPracticePage({super.key, required this.promptId});

  final String promptId;

  @override
  ConsumerState<PictureStoryPracticePage> createState() =>
      _PictureStoryPracticePageState();
}

class _PictureStoryPracticePageState
    extends ConsumerState<PictureStoryPracticePage> {
  final _audio = PictureStoryAudioService();
  final _player = AudioPlayer();
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
  bool _recording = false;
  bool _processing = false;
  bool _finishing = false;
  bool _showHints = false;
  bool _usedHints = false;

  PictureStoryPrompt? get _prompt => PictureStoryCatalog.find(widget.promptId);

  @override
  void initState() {
    super.initState();
    _record = PictureStoryPracticeRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      profileId: ProfileScope.currentId,
      promptId: widget.promptId,
      promptVersion: _prompt?.version ?? 1,
      startedAt: DateTime.now(),
      status: 'draft',
      segmentsJson: '[]',
    );
    unawaited(_saveDraft());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transcriptSubscription?.cancel();
    final speech = _speech;
    if (speech != null) unawaited(speech.dispose());
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_recording || _processing || _finishing) return;
    final factory = ref.read(speechRecognitionServiceFactoryProvider);
    final speech = _speech ??= factory();
    try {
      await speech.initialize();
      if (speech is StreamingSpeechRecognitionService) {
        final streaming = speech as StreamingSpeechRecognitionService;
        await _transcriptSubscription?.cancel();
        _transcriptSubscription =
            streaming.transcriptStream.listen((String text) {
          if (mounted && (_recording || _processing)) {
            setState(() => _liveText = text);
          }
        });
      }
      await speech.start();
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _recording = true;
        _elapsedSeconds = 0;
        _liveText = '';
        _message = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          timer.cancel();
          return;
        }
        final next = _elapsedSeconds + 1;
        setState(() => _elapsedSeconds = next);
        if (next >= 60) unawaited(_finishSegment());
      });
    } on SpeechRecognitionException catch (error) {
      if (mounted) setState(() => _message = error.message);
      await speech.cancel();
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话开始录音失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _message = '无法开始录音，请检查麦克风权限');
      await speech.cancel();
    }
  }

  Future<void> _finishSegment() async {
    if (!_recording || _processing || _speech == null) return;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _processing = true;
      _message = null;
    });
    SpeechRecognitionResult? result;
    Object? recognitionError;
    try {
      result = await _speech!.stop();
    } on Object catch (error) {
      recognitionError = error;
    }
    final retained = _speech is RetainedAudioSpeechRecognitionService
        ? (_speech! as RetainedAudioSpeechRecognitionService).takeLastAudio()
        : null;
    if (!mounted) return;
    if (retained == null || retained.isEmpty) {
      setState(() {
        _processing = false;
        _message = recognitionError is SpeechRecognitionException
            ? recognitionError.message
            : '录音没有保存成功，请再试一次';
      });
      return;
    }
    final segmentId =
        '${_record!.id}-${_segments.length + 1}-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final audioPath = await _audio.savePcm16(id: segmentId, pcm: retained);
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
      await _saveDraft();
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话保存录音失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _processing = false;
        _message = '录音保存失败，请检查设备空间后重试';
      });
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
    if (_finishing ||
        _record == null ||
        _segments.isEmpty ||
        _recording ||
        _processing) {
      return;
    }
    setState(() => _finishing = true);
    _record!.setSegments(_segments);
    _record!.status = 'completed';
    _record!.completedAt = DateTime.now();
    _record!.usedHints = _usedHints;
    _record!.feedbackJson = jsonEncode(<String, Object>{
      'source': 'local',
      'highlights': ['你愿意把看到的内容说出来了。', if (_segments.length > 1) '你用了多段话补充细节。'],
      'suggestion': _record!.answerText.trim().isEmpty
          ? '可以先填写听到的文字，再请家长一起回听。'
          : '再补充一个动作或人物的心情，故事会更生动。',
    });
    await _saveDraft();
    final aiFeedback = await _generateAiFeedback(prompt: _prompt!);
    if (aiFeedback != null && _record != null) {
      _record!.feedbackJson = jsonEncode(<String, Object>{
        'source': 'vision',
        'text': aiFeedback,
      });
      await _saveDraft();
    }
    if (!mounted) return;
    setState(() => _finishing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('本次练习已保存')));
    context.pop();
  }

  Future<void> _saveDraft() async {
    final record = _record;
    if (record == null) return;
    try {
      await ref.read(pictureStoryRepositoryProvider).save(record);
      ref.invalidate(pictureStoryHistoryProvider);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '看图说话记录保存失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Uint8List?> _captureIllustration() async {
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
  }) async {
    final image = await _captureIllustration();
    if (image == null) return null;
    final settings = ref.read(settingsRepositoryProvider);
    try {
      final config =
          await settings.readLlmConfigForScenario(LlmScenario.assistant);
      if (config == null || !config.supportsVision || !mounted) return null;
      final client = createRuntimeLlmClient(
        httpClient: ref.read(llmExplainHttpClientProvider),
        settings: settings,
        isActive: () => mounted,
        onSelectionChanged: () =>
            ref.read(llmSelectionVersionProvider.notifier).state++,
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
    if (!await File(segment.audioPath).exists()) {
      if (mounted) setState(() => _message = '录音文件已清理，文字记录仍然保留');
      return;
    }
    await _player.stop();
    if (_playingId == segment.id) {
      setState(() => _playingId = null);
      return;
    }
    setState(() => _playingId = segment.id);
    await _player.play(DeviceFileSource(segment.audioPath));
    _player.onPlayerComplete.first.then((_) {
      if (mounted && _playingId == segment.id) {
        setState(() => _playingId = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = _prompt;
    if (prompt == null) {
      return const Scaffold(body: Center(child: Text('题目不存在')));
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
            final wide = constraints.maxWidth >= 760;
            final content = _buildContent(theme, prompt);
            return wide
                ? Row(
                    children: [
                      Expanded(child: content[0]),
                      const SizedBox(width: SpacingTokens.lg),
                      Expanded(child: content[1]),
                    ],
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
                  child: PictureStoryIllustration(kind: prompt.illustration),
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
            if (_processing) const LinearProgressIndicator(),
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
                    onPressed: _processing || _finishing
                        ? null
                        : (_recording ? _finishSegment : _startRecording),
                    icon: Icon(
                      _recording ? Icons.stop : Icons.mic_none_outlined,
                    ),
                    label: Text(_recording ? '说好了' : '开始录音'),
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
