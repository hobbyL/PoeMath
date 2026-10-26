import 'dart:async';
import 'package:flutter/material.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts/narration_audio_identity.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_reading.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';
import 'package:poemath/domain/textbook_recognition_session.dart';
import 'package:poemath/features/textbook/recognition/recognition_page_state.dart';

class TextbookRecognitionPracticePage extends RecognitionPage {
  const TextbookRecognitionPracticePage({
    super.key,
    required super.bookId,
    required super.lessonId,
    super.routeObserver,
    this.recognitionFirst = false,
    this.targetId,
  });
  final bool recognitionFirst;
  final String? targetId;
  @override
  RecognitionPageState<TextbookRecognitionPracticePage> createState() =>
      _PracticeState();
}

class _PracticeState
    extends RecognitionPageState<TextbookRecognitionPracticePage> {
  @override
  bool get showNavigationBar => false;

  bool noRound = false;
  SpeechRecognitionService? _oral;
  SpeechRecognitionSettingsSnapshot? _oralSettings;
  Timer? _recordingTimer;
  int _oralGeneration = 0;
  bool _starting = false, _recording = false, _evaluating = false;
  String? _oralMessage;
  bool get _oralWorking => _starting || _recording || _evaluating;

  @override
  Future<void> onLoaded() async {
    final targetId = widget.targetId;
    final readingFirst = widget.recognitionFirst || targetId != null;
    final lessonId = widget.lessonId;
    final bookId = widget.bookId;
    bool sameEntry() =>
        current &&
        widget.targetId == targetId &&
        widget.lessonId == lessonId &&
        widget.bookId == bookId;
    if (current) setState(() => noRound = false);
    try {
      final settings = await ref
          .read(settingsRepositoryProvider)
          .loadSpeechRecognitionSettingsSnapshot();
      if (sameEntry()) setState(() => _oralSettings = settings);
    } on Object {
      if (sameEntry()) setState(() => _oralMessage = '读取语音识别设置失败，仍可听示范练习');
    }
    if (!sameEntry()) return;
    final p = progress!;
    final saved = p.session;
    if (saved?.lessonId == widget.lessonId &&
        !saved!.finished &&
        saved.recognitionFirst == readingFirst &&
        (targetId == null ||
            saved.questions.length == 1 &&
                saved.question.kind == RecognitionQuestionKind.read &&
                saved.question.targetId == targetId)) {
      return;
    }
    final at = DateTime.now();
    final id = '${repository!.epoch}/${at.microsecondsSinceEpoch}';
    final s = buildRecognitionSession(
      progress: p,
      lessonId: widget.lessonId,
      targets: targets,
      id: id,
      now: at,
      epoch: repository!.epoch,
      recognitionFirst: widget.recognitionFirst,
      targetId: targetId,
    );
    if (s == null) {
      setState(() => noRound = true);
      return;
    }
    final repo = repository!;
    final fp = fingerprint;
    await runWrite(
      () => repo.change(
        lessonId: widget.lessonId,
        fingerprint: fp,
        operationId: '$id/start',
        expectedRevision: p.revision,
        reduce: (latest, _) => latest.copy(session: s),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant TextbookRecognitionPracticePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId == widget.bookId &&
        oldWidget.lessonId == widget.lessonId &&
        (oldWidget.targetId != widget.targetId ||
            oldWidget.recognitionFirst != widget.recognitionFirst)) {
      unawaited(stopAudio());
      unawaited(reload());
    }
  }

  void _writeSession(
    String suffix,
    RecognitionProgress Function(RecognitionProgress, List<RecognitionTarget>)
        reduce, {
    VoidCallback? success,
  }) {
    final p = progress!, s = p.session!, repo = repository!, fp = fingerprint;
    unawaited(
      runWrite(
        () => repo.change(
          lessonId: widget.lessonId,
          fingerprint: fp,
          operationId: '${s.question.id}/$suffix',
          expectedRevision: p.revision,
          sessionId: s.id,
          reduce: reduce,
        ),
        success: success,
      ),
    );
  }

  void _answer(RecognitionEvidence e) {
    final at = DateTime.now();
    _writeSession(
      'answer',
      (p, t) => answerRecognition(p, t, e, at),
      success: () => unawaited(stopAudio()),
    );
  }

  void _next() {
    _writeSession(
      'next',
      (p, _) => p.copy(
        session: p.session!.copy(
          index: p.session!.index + 1,
          hinted: false,
          clearFeedback: true,
        ),
      ),
      success: () {
        _oralMessage = null;
        unawaited(stopAudio());
      },
    );
  }

  void _playDemonstration() {
    if (_oralWorking || busy || !current) return;
    final text = targets
        .firstWhere((t) => t.id == progress!.session!.question.targetId)
        .text;
    _writeSession(
      'hint',
      (p, _) => p.copy(session: p.session!.copy(hinted: true)),
      success: () => playAudio(text),
    );
  }

  Future<void> _startRecording() async {
    if (_oralWorking || busy || !current) return;
    final target = targets.firstWhere(
      (t) => t.id == progress!.session!.question.targetId,
    );
    if (recognitionPronunciation(target.pinyin) == null) return;
    final generation = ++_oralGeneration;
    setState(() {
      _starting = true;
      _oralMessage = null;
    });
    try {
      await super.stopAudio();
      if (!current || generation != _oralGeneration) return;
      final settings = await ref
          .read(settingsRepositoryProvider)
          .loadSpeechRecognitionSettingsSnapshot();
      if (!current || generation != _oralGeneration) return;
      setState(() => _oralSettings = settings);
      if (!settings.settings.hasCredentials) {
        throw const SpeechRecognitionException('请家长先保存语音识别密钥');
      }
      _oral ??= ref.read(speechRecognitionServiceFactoryProvider)();
      await _oral!.initialize();
      if (!current || generation != _oralGeneration) return;
      await _oral!.start();
      if (!current || generation != _oralGeneration) return;
      setState(() {
        _starting = false;
        _recording = true;
      });
      _recordingTimer = Timer(
        const Duration(seconds: 10),
        () => unawaited(_finishRecording()),
      );
    } on Object catch (e) {
      if (generation == _oralGeneration) await _oral?.cancel();
      if (current && generation == _oralGeneration) {
        setState(() {
          _starting = false;
          _oralMessage =
              e is SpeechRecognitionException ? e.message : '无法开始录音，请重试';
        });
      }
    }
  }

  Future<void> _finishRecording() async {
    if (!_recording || !current) return;
    _recordingTimer?.cancel();
    final generation = _oralGeneration;
    final session = progress!.session!;
    final questionId = session.question.id;
    final target = targets.firstWhere((t) => t.id == session.question.targetId);
    final settings = _oralSettings!;
    setState(() {
      _recording = false;
      _evaluating = true;
    });
    try {
      final latest = await ref
          .read(settingsRepositoryProvider)
          .loadSpeechRecognitionSettingsSnapshot();
      if (!current || generation != _oralGeneration) return;
      if (!_sameConfiguration(settings, latest)) {
        throw const SpeechRecognitionException('语音识别配置已变化，请重新进入练习');
      }
      final recognized = await _oral!.stop();
      final result = matchRecognitionReading(
        target: target.text,
        pinyin: target.pinyin,
        transcript: recognized.text,
        contexts: [...lesson!.words, ...lesson!.paragraphs],
      );
      final after = await ref
          .read(settingsRepositoryProvider)
          .loadSpeechRecognitionSettingsSnapshot();
      if (!current ||
          generation != _oralGeneration ||
          progress?.session?.id != session.id ||
          progress?.session?.question.id != questionId) {
        return;
      }
      if (!_sameConfiguration(settings, after)) {
        throw const SpeechRecognitionException('语音识别配置已变化，这次还没确认');
      }
      setState(() {
        _evaluating = false;
        _oralMessage = switch (result) {
          RecognitionReadingOutcome.inconclusive => '这次没听清，请靠近一些再读一次。也可以先听示范。',
          RecognitionReadingOutcome.needsContext =>
            '这次还不能确定读音，请自己组个词再读一次，或换个词试试。',
          _ => null,
        };
      });
      if (result == RecognitionReadingOutcome.matched ||
          result == RecognitionReadingOutcome.needsPractice) {
        _answer(
          result == RecognitionReadingOutcome.matched
              ? RecognitionEvidence.oralCorrect
              : RecognitionEvidence.oralAgain,
        );
      }
    } on Object catch (e) {
      if (current && generation == _oralGeneration) {
        setState(() {
          _evaluating = false;
          _oralMessage = switch (e) {
            SpeechRecognitionException() => e.message,
            CloudQuotaExceededException() => e.message,
            _ => '语音识别暂时不可用，这次还没确认，请重试',
          };
        });
      }
      if (generation == _oralGeneration) await _oral?.cancel();
    }
  }

  bool _sameConfiguration(
    SpeechRecognitionSettingsSnapshot a,
    SpeechRecognitionSettingsSnapshot b,
  ) =>
      b.settings.hasCredentials &&
      a.credentials?.secretId == b.credentials?.secretId &&
      a.credentials?.secretKey == b.credentials?.secretKey;

  @override
  void playAudio(
    String text, {
    NarrationAudioIdentity? requiredIdentity,
    VoidCallback? rejected,
  }) {
    if (_oralWorking) return;
    super.playAudio(
      text,
      requiredIdentity: requiredIdentity,
      rejected: rejected,
    );
  }

  @override
  Future<void> stopAudio() async {
    ++_oralGeneration;
    _recordingTimer?.cancel();
    if (mounted && current) {
      setState(() {
        _starting = false;
        _recording = false;
        _evaluating = false;
      });
    }
    await Future.wait([super.stopAudio(), if (_oral != null) _oral!.cancel()]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs may briefly make the app inactive before recording starts.
    if (state == AppLifecycleState.inactive && _starting) return;
    if (state != AppLifecycleState.resumed) unawaited(stopAudio());
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    ++_oralGeneration;
    unawaited(_oral?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = progress?.session;
    final ready = targets.where((t) => t.ready).toList();
    if (widget.targetId != null &&
        (!ready.any((target) => target.id == widget.targetId) ||
            s == null ||
            s.questions
                .any((question) => question.targetId != widget.targetId))) {
      return frame('认字', []);
    }
    if (ready.isEmpty) {
      return frame('认字', [
        const Text('本课还没有可练习的生字。'),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回本课'),
        ),
      ]);
    }
    if (noRound || s == null || s.lessonId != widget.lessonId) {
      return frame('认一认', [
        const Text('今天先学到这里。到复习时间，我们再来认一认。'),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回本课'),
        ),
      ]);
    }
    if (s.finished) {
      final ids = s.questions.map((q) => q.targetId).toSet();
      return frame('这一轮完成了', [
        Text('这一轮完成了', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: SpacingTokens.md),
        Text(
          '这次练过 ${ids.length} 个字',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: SpacingTokens.md),
        for (final t in targets.where((t) => ids.contains(t.id)))
          AppTile(
            iconColor: Theme.of(context).colorScheme.primary,
            icon: Icons.auto_stories_outlined,
            title: t.text,
            subtitle:
                '${recognitionRecordLabel(recognitionCurrentRecord(progress!, widget.lessonId, t))} · 下次 ${recognitionCurrentRecord(progress!, widget.lessonId, t)?.nextDay ?? '稍后'}\n独立认读 ${recognitionCurrentRecord(progress!, widget.lessonId, t)?.oralCorrect ?? 0} 次 · 辨认 ${recognitionCurrentRecord(progress!, widget.lessonId, t)?.correct ?? 0} 次',
          ),
        const SizedBox(height: SpacingTokens.lg),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('回到本课'),
        ),
      ]);
    }
    final q = s.question;
    final t = targets.firstWhere((t) => t.id == q.targetId);
    final cue = t.cues.where((c) => c.key == q.cueKey).firstOrNull;
    final approval = cue == null ? null : recognitionAudio(progress!, t, cue);
    final feedback = s.feedback != null;
    final showPinyin = s.hinted || feedback;
    final prompt = switch (q.kind) {
      RecognitionQuestionKind.study => '先自己试着认一认',
      RecognitionQuestionKind.read => '这个字你认识吗？自己读出来',
      RecognitionQuestionKind.listen => '听一听，选出这个字',
      RecognitionQuestionKind.context => '听一听，在词句里找到这个字'
    };
    final isChoice = q.kind == RecognitionQuestionKind.listen ||
        q.kind == RecognitionQuestionKind.context;
    final audioControls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        audioButton(
          prompt,
          label: '听说明',
          iconOnly: true,
          enabled: !_oralWorking,
          icon: Icons.help_outline,
        ),
        !feedback && !isChoice && !s.hinted
            ? IconButton(
                onPressed: busy || _oralWorking ? null : _playDemonstration,
                tooltip: '听示范',
                constraints: const BoxConstraints(
                  minWidth: SpacingTokens.minTapTarget,
                  minHeight: SpacingTokens.minTapTarget,
                ),
                icon: const Icon(Icons.volume_up_outlined),
              )
            : audioButton(
                isChoice && !feedback ? cue?.text ?? t.text : t.text,
                requiredIdentity:
                    isChoice && !feedback ? approval?.identity : null,
                label: isChoice && !feedback ? '听题目' : '听示范',
                iconOnly: true,
                enabled: !_oralWorking,
              ),
      ],
    );
    final children = <Widget>[
      if (isChoice) ...[
        Text(prompt, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: SpacingTokens.md),
      ],
    ];
    if (!isChoice || feedback || s.hinted) {
      children.add(
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: SpacingTokens.xxl + SpacingTokens.sm,
              ),
              Flexible(
                child: ColoredCard(
                  key: const ValueKey('recognition-practice-character-card'),
                  color: Theme.of(context).colorScheme.primary,
                  width: SpacingTokens.xxl * 3 +
                      SpacingTokens.md +
                      (MediaQuery.textScalerOf(context)
                                  .scale(SpacingTokens.xxl) -
                              SpacingTokens.xxl)
                          .clamp(0, SpacingTokens.xxl * 2),
                  constraints:
                      const BoxConstraints(minHeight: SpacingTokens.xxl * 3),
                  padding: const EdgeInsets.all(SpacingTokens.sm),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: SpacingTokens.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showPinyin)
                          Text(
                            t.pinyin,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        Text(
                          t.text,
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              SizedBox(width: SpacingTokens.xxl, child: audioControls),
            ],
          ),
        ),
      );
    } else {
      children.add(Align(alignment: Alignment.topRight, child: audioControls));
    }
    if (!feedback) {
      if (q.kind == RecognitionQuestionKind.read) {
        children.addAll([
          const SizedBox(height: SpacingTokens.md),
          if (_oralMessage != null) Text(_oralMessage!),
          if (recognitionPronunciation(t.pinyin) != null &&
              _oralSettings?.settings.hasCredentials == true) ...[
            FilledButton.icon(
              onPressed: busy || _starting || _evaluating
                  ? null
                  : () => unawaited(
                        _recording ? _finishRecording() : _startRecording(),
                      ),
              icon: Icon(
                _recording ? Icons.stop_circle_outlined : Icons.mic_none,
              ),
              label: Text(
                _starting
                    ? '正在准备麦克风…'
                    : _evaluating
                        ? '正在听你认读…'
                        : _recording
                            ? '读完了，听听结果'
                            : '读一读',
              ),
            ),
            if (_recording) const Text('正在录音，10 秒后自动结束并识别。'),
          ],
          if (_oralWorking)
            TextButton(
              onPressed: () => unawaited(stopAudio()),
              child: const Text('取消本次录音'),
            ),
        ]);
      }
      if (q.kind == RecognitionQuestionKind.listen) {
        children.add(
          Wrap(
            spacing: SpacingTokens.md,
            runSpacing: SpacingTokens.md,
            children: [
              for (final id in q.options)
                OutlinedButton(
                  onPressed: busy ||
                          !heard ||
                          heardText != cue?.text ||
                          approval == null
                      ? null
                      : () => _answer(
                            id == t.id
                                ? RecognitionEvidence.correct
                                : RecognitionEvidence.incorrect,
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Text(
                      targets.firstWhere((t) => t.id == id).text,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                ),
            ],
          ),
        );
      } else if (q.kind == RecognitionQuestionKind.context) {
        final contextCue = t.cues.firstWhere((c) => c.key == q.options.single);
        final runes = contextCue.text.runes.toList();
        children.add(
          ColoredCard(
            color: Theme.of(context).colorScheme.secondary,
            child: Wrap(
              spacing: SpacingTokens.xs,
              runSpacing: SpacingTokens.sm,
              children: [
                for (var i = 0; i < runes.length; i++)
                  if (recognitionIsHan(runes[i]))
                    OutlinedButton(
                      onPressed: busy ||
                              !heard ||
                              heardText != cue?.text ||
                              approval == null
                          ? null
                          : () => _answer(
                                q.positions.contains(i)
                                    ? RecognitionEvidence.correct
                                    : RecognitionEvidence.incorrect,
                              ),
                      child: Text(
                        String.fromCharCode(runes[i]),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    )
                  else
                    Text(
                      String.fromCharCode(runes[i]),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
              ],
            ),
          ),
        );
      } else if (q.kind == RecognitionQuestionKind.study) {
        children.add(
          FilledButton(
            onPressed: busy ? null : () => _answer(RecognitionEvidence.study),
            child: const Text('试过了，开始练习'),
          ),
        );
      }
      if (isChoice &&
          (audioError != null ||
              approval == null ||
              audioStatus == NarrationStatus.failed)) {
        children.add(
          TextButton(
            onPressed: busy ? null : _next,
            child: const Text('先跳过这道听音题'),
          ),
        );
      }
    } else {
      if (q.kind == RecognitionQuestionKind.context) {
        final contextCue = t.cues.firstWhere((c) => c.key == q.options.single);
        final runes = contextCue.text.runes.toList();
        children.add(
          ColoredCard(
            color: Theme.of(context).colorScheme.secondary,
            child: Wrap(
              children: [
                for (var i = 0; i < runes.length; i++)
                  Text(
                    String.fromCharCode(runes[i]),
                    key: ValueKey('recognition-context-$i'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          backgroundColor: q.positions.contains(i)
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                  ),
              ],
            ),
          ),
        );
      }
      children.add(
        Text(
          switch (s.feedback!) {
            RecognitionEvidence.correct => s.hinted ? '借助提示找到了，下次再试试' : '找对了！',
            RecognitionEvidence.incorrect => '一起再看看这个字，稍后再练',
            RecognitionEvidence.selfCorrect => '已经对照读过了，之后再检查认读',
            RecognitionEvidence.selfAgain => '没关系，下次再练一练',
            RecognitionEvidence.oralCorrect =>
              s.hinted || q.repeat || !s.recognitionFirst
                  ? '跟着提示读出来了，隔天再独立试试'
                  : '这次自己认出来了！过几天再来认一认',
            RecognitionEvidence.oralAgain => '一起听听这个字，稍后再试试',
            _ => '先练一练，慢慢记住'
          },
        ),
      );
      children.add(
        FilledButton(
          onPressed: busy ? null : _next,
          child: Text(s.index + 1 == s.questions.length ? '看看这一轮' : '下一步'),
        ),
      );
    }
    return frame('认字', children, compact: !isChoice);
  }
}
