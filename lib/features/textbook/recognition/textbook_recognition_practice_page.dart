import 'dart:async';
import 'package:flutter/material.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';
import 'package:poemath/domain/textbook_recognition_session.dart';
import 'package:poemath/features/textbook/recognition/recognition_page_state.dart';

class TextbookRecognitionPracticePage extends RecognitionPage {
  const TextbookRecognitionPracticePage({
    super.key,
    required super.bookId,
    required super.lessonId,
    super.routeObserver,
  });
  @override
  RecognitionPageState<TextbookRecognitionPracticePage> createState() =>
      _PracticeState();
}

class _PracticeState
    extends RecognitionPageState<TextbookRecognitionPracticePage> {
  bool noRound = false;
  @override
  Future<void> onLoaded() async {
    final p = progress!;
    if (p.session?.lessonId == widget.lessonId && !p.session!.finished) return;
    final at = DateTime.now();
    final id = '${repository!.epoch}/${at.microsecondsSinceEpoch}';
    final s = buildRecognitionSession(
      progress: p,
      lessonId: widget.lessonId,
      targets: targets,
      id: id,
      now: at,
      epoch: repository!.epoch,
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
      success: () => unawaited(stopAudio()),
    );
  }

  void _hint() => _writeSession(
        'hint',
        (p, _) => p.copy(session: p.session!.copy(hinted: true)),
      );
  @override
  Widget build(BuildContext context) {
    final s = progress?.session;
    final ready = targets.where((t) => t.ready).toList();
    if (ready.isEmpty) return frame('认一认', [const Text('请家长先核对本课生字，再开始学习。')]);
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
                '${recognitionRecordLabel(recognitionCurrentRecord(progress!, widget.lessonId, t))} · 下次 ${recognitionCurrentRecord(progress!, widget.lessonId, t)?.nextDay ?? '稍后'}',
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
    final showPinyin =
        s.hinted || feedback || q.kind == RecognitionQuestionKind.read && heard;
    final prompt = switch (q.kind) {
      RecognitionQuestionKind.study => '先自己试着认一认',
      RecognitionQuestionKind.read => '自己读一读，再听示范对照',
      RecognitionQuestionKind.listen => '听一听，选出这个字',
      RecognitionQuestionKind.context => '听一听，在词句里找到这个字'
    };
    final isChoice = q.kind == RecognitionQuestionKind.listen ||
        q.kind == RecognitionQuestionKind.context;
    final children = <Widget>[
      Text('第 ${s.index + 1} / ${s.questions.length} 步 · ${lesson!.title}'),
      const SizedBox(height: SpacingTokens.lg),
      Text(
        switch (q.kind) {
          RecognitionQuestionKind.study => '先自己试着认一认',
          RecognitionQuestionKind.read => '自己读一读，再听示范对照',
          RecognitionQuestionKind.listen => '听一听，选出这个字',
          RecognitionQuestionKind.context => '听一听，在词句里找到这个字'
        },
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: SpacingTokens.md),
    ];
    if (!isChoice || feedback || s.hinted) {
      children.add(
        ColoredCard(
          color: Theme.of(context).colorScheme.primary,
          child: Column(
            children: [
              Text(t.text, style: Theme.of(context).textTheme.displayLarge),
              if (showPinyin)
                Text(
                  t.pinyin,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
            ],
          ),
        ),
      );
    }
    if (!feedback) {
      children.add(
        TextButton.icon(
          onPressed: busy ? null : () => playAudio(prompt),
          icon: const Icon(Icons.help_outline),
          label: const Text('听说明'),
        ),
      );
      children.add(
        audioButton(
          isChoice ? cue?.text ?? t.text : t.text,
          requiredIdentity: isChoice ? approval?.identity : null,
          label: isChoice ? '听题目' : '听示范',
        ),
      );
      if (!showPinyin) {
        children.add(
          TextButton(
            onPressed: busy ? null : _hint,
            child: const Text('看拼音提示'),
          ),
        );
      }
      children.add(const SizedBox(height: SpacingTokens.md));
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
      } else {
        children.add(
          FilledButton(
            onPressed: busy || !heard || heardText != t.text
                ? null
                : () => _answer(RecognitionEvidence.selfCorrect),
            child: const Text('对照示范，我读对了'),
          ),
        );
        children.add(
          TextButton(
            onPressed:
                busy ? null : () => _answer(RecognitionEvidence.selfAgain),
            child: const Text('还要练一练'),
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
      children.add(audioButton(t.text, label: '再听示范'));
      children.add(
        Text(
          switch (s.feedback!) {
            RecognitionEvidence.correct => s.hinted ? '借助提示找到了，下次再试试' : '找对了！',
            RecognitionEvidence.incorrect => '一起再看看这个字，稍后再练',
            RecognitionEvidence.selfCorrect => '已经对照读过了，之后再检查认读',
            RecognitionEvidence.selfAgain => '没关系，下次再练一练',
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
    return frame('认一认', children);
  }
}
