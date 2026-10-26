import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/domain/textbook_recognition_review.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_session.dart';
import 'package:poemath/features/textbook/recognition/recognition_page_state.dart';

class TextbookRecognitionCheckPage extends RecognitionPage {
  const TextbookRecognitionCheckPage({
    super.key,
    required super.bookId,
    required super.lessonId,
    super.routeObserver,
  });
  @override
  RecognitionPageState<TextbookRecognitionCheckPage> createState() =>
      _CheckState();
}

class _CheckState extends RecognitionPageState<TextbookRecognitionCheckPage> {
  int index = 0;
  bool revealed = false;
  List<RecognitionTarget> sample = const [];
  @override
  Future<void> onLoaded() async {
    final candidates = targets.where((t) => t.ready).toList()
      ..shuffle(Random(DateTime.now().microsecondsSinceEpoch));
    candidates.sort(
      (a, b) =>
          (recognitionCurrentRecord(progress!, widget.lessonId, a)?.parentDay ??
                  '')
              .compareTo(
        recognitionCurrentRecord(progress!, widget.lessonId, b)?.parentDay ??
            '',
      ),
    );
    setState(() {
      sample = candidates.take(RecognitionPolicy.roundSize).toList();
      index = 0;
      revealed = false;
    });
  }

  void _record(bool passed) {
    final list = sample;
    final t = list[index], p = progress!, repo = repository!, fp = fingerprint;
    final at = DateTime.now(), day = recognitionDay(DateTime.now());
    final key = RecognitionProgress.targetKey(widget.lessonId, t.id);
    final hinted = revealed;
    unawaited(
      runWrite(
        () => repo.change(
          lessonId: widget.lessonId,
          fingerprint: fp,
          operationId: 'parent/${at.microsecondsSinceEpoch}/$key',
          expectedRevision: p.revision,
          authorize: ParentAccessService.instance.assertAllowed,
          reduce: (latest, _) => latest.copy(
            records: {
              ...latest.records,
              key: recognitionRecordResult(
                recognitionCurrentRecord(latest, widget.lessonId, t) ??
                    RecognitionRecord(fingerprint: t.fingerprint),
                passed
                    ? RecognitionEvidence.parentCorrect
                    : RecognitionEvidence.parentAgain,
                day: day,
                hinted: hinted,
              ),
            },
          ),
        ),
        success: () {
          index++;
          revealed = false;
          unawaited(stopAudio());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = sample;
    return ParentAccessBoundary(
      child: frame('家长抽查', [
        const Text('先让孩子独立读，再听示范对照。查看提示后通过，会记为需要再确认。'),
        const SizedBox(height: SpacingTokens.lg),
        if (index >= list.length) ...[
          const Text('这次抽查完成了'),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回本课'),
          ),
        ] else ...[
          Text('${index + 1} / ${list.length}'),
          ColoredCard(
            color: Theme.of(context).colorScheme.primary,
            child: Column(
              children: [
                Text(
                  list[index].text,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                if (revealed)
                  Text(
                    list[index].pinyin,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
              ],
            ),
          ),
          audioButton(list[index].text),
          TextButton(
            onPressed: busy ? null : () => setState(() => revealed = true),
            child: const Text('查看拼音提示'),
          ),
          FilledButton(
            onPressed: busy ? null : () => _record(true),
            child: const Text('孩子独立读对了'),
          ),
          TextButton(
            onPressed: busy ? null : () => _record(false),
            child: const Text('还需要练习'),
          ),
        ],
      ]),
    );
  }
}
