import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/domain/math_textbook_progress.dart';

import '../helpers/math_textbook_fixture.dart';
import '../helpers/math_textbook_learning_fixture.dart';

class _NoDigestLesson extends MathTextbookLesson {
  _NoDigestLesson(MathTextbookLesson source)
    : super(
        id: source.id,
        title: source.title,
        startPage: source.startPage,
        endPage: source.endPage,
        blocks: source.blocks,
        learning: source.learning,
      );

  @override
  String contentDigest(String pdfSha256) => throw StateError('未审核的课时不应生成完整摘要');
}

class _NoSerializationBlock extends MathTextbookBlock {
  _NoSerializationBlock(MathTextbookBlock source)
    : super(
        id: source.id,
        kind: source.kind,
        spans: source.spans,
        sources: source.sources,
      );

  @override
  Map<String, dynamic> toJson() => throw StateError('没有学习记录时不应序列化正文来比较摘要');
}

class _ApprovalProbeLesson extends MathTextbookLesson {
  _ApprovalProbeLesson(MathTextbookLesson source)
    : super(
        id: source.id,
        title: source.title,
        startPage: source.startPage,
        endPage: source.endPage,
        blocks: source.blocks.map(_NoSerializationBlock.new).toList(),
        learning: source.learning,
      );

  int approvalChecks = 0;
  @override
  bool isApproved(String pdfSha256) {
    approvalChecks++;
    return true;
  }
}

void main() {
  final book = mathTextbookFixture();
  final lesson = mathLearningFixture().approve(
    pdfSha256: book.pdfSha256,
    reviewer: '测试家长',
    editingMilliseconds: 1000,
  );

  MathTextbookProgress progress({
    Map<String, String> reads = const {},
    Map<String, MathTextbookTargetRecord> targets = const {},
  }) => MathTextbookProgress(
    profileId: 'child',
    bookId: book.pdfSha256,
    editionId: book.learningEditionId,
    readLessons: reads,
    targets: targets,
  );

  MathTextbookTargetRecord record(
    String? planId,
    String exerciseId, {
    MathTextbookResult result = MathTextbookResult.correct,
    String session = 'same-session',
    String? digest,
  }) => MathTextbookTargetRecord(
    scopeDigest: digest ?? mathTextbookTargetDigest(lesson, planId, exerciseId),
    sessionId: session,
    attemptId: '$exerciseId-attempt',
    result: result,
  );

  String key(String? plan, String exercise) =>
      MathTextbookProgress.targetKey(lesson.id, plan, exercise);

  test('未审核课时的阅读独立有效，内容改变后不继承已读', () {
    final pending = mathLearningFixture();
    final saved = progress(
      reads: {pending.id: mathTextbookReadingDigest(pending)},
    );
    final summary = mathTextbookLessonProgress(pending, book.pdfSha256, saved);
    expect(summary.read, isTrue);
    expect(summary.ready, isFalse);
    expect(summary.label, '已读');
    expect(summary.complete, isFalse);
    final changed = mathTextbookLessonProgress(
      pending.edit(title: '内容已改变'),
      book.pdfSha256,
      saved,
    );
    expect(changed.read, isFalse);
  });

  test('未审核的大课时不会为确定为假的审核状态生成摘要', () {
    final draft = _NoDigestLesson(denseMathLearningFixture());
    expect(draft.isApproved(book.pdfSha256), isFalse);
    final summary = mathTextbookLessonProgress(
      draft,
      book.pdfSha256,
      progress(),
    );
    expect(summary.ready, isFalse);
    expect(summary.read, isFalse);
    expect(summary.complete, isFalse);
  });

  test('空学习记录不摘要正文和目标，一个进度只检查一次审核', () {
    final probe = _ApprovalProbeLesson(mathLearningFixture());
    final summary = mathTextbookLessonProgress(
      probe,
      book.pdfSha256,
      progress(),
    );
    expect(probe.approvalChecks, 1);
    expect(summary.ready, isTrue);
    expect(summary.read, isFalse);
    expect(summary.originalTotal, 1);
    expect(summary.originalPassed, 0);
    expect(summary.plansTotal, 1);
    expect(summary.plansPassed, 0);
    expect(summary.pendingParent, 0);
    expect(summary.complete, isFalse);
  });

  test('匹配的阅读、原题和同一轮巩固仍判定完整完成', () {
    final summary = mathTextbookLessonProgress(
      lesson,
      book.pdfSha256,
      progress(
        reads: {lesson.id: mathTextbookReadingDigest(lesson)},
        targets: {
          key(null, 'ex'): record(null, 'ex'),
          key('plan', 'plan-0'): record('plan', 'plan-0'),
          key('plan', 'plan-1'): record('plan', 'plan-1'),
        },
      ),
    );
    expect(summary.read, isTrue);
    expect(summary.originalPassed, 1);
    expect(summary.plansPassed, 1);
    expect(summary.complete, isTrue);
  });

  test('旧摘要和缺失的目标不继承阅读或巩固完成', () {
    final summary = mathTextbookLessonProgress(
      lesson,
      book.pdfSha256,
      progress(
        reads: {lesson.id: 'b' * 64},
        targets: {
          key(null, 'ex'): record(null, 'ex', digest: 'b' * 64),
          key('plan', 'plan-0'): record('plan', 'plan-0'),
        },
      ),
    );
    expect(summary.ready, isTrue);
    expect(summary.read, isFalse);
    expect(summary.originalPassed, 0);
    expect(summary.plansPassed, 0);
    expect(summary.complete, isFalse);
  });

  test('待家长核对与不同轮次的巩固不会被优化成已完成', () {
    final summary = mathTextbookLessonProgress(
      lesson,
      book.pdfSha256,
      progress(
        targets: {
          key(null, 'ex'): record(
            null,
            'ex',
            result: MathTextbookResult.pendingParent,
          ),
          key('plan', 'plan-0'): record(
            'plan',
            'plan-0',
            result: MathTextbookResult.pendingParent,
          ),
          key('plan', 'plan-1'): record(
            'plan',
            'plan-1',
            session: 'another-session',
          ),
        },
      ),
    );
    expect(summary.originalPassed, 0);
    expect(summary.pendingParent, 2);
    expect(summary.plansPassed, 0);
    expect(summary.complete, isFalse);
  });
}
