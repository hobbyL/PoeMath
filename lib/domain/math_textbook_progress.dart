import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/domain/math_textbook_practice.dart';

class MathTextbookLessonProgress {
  const MathTextbookLessonProgress({
    required this.ready,
    required this.read,
    required this.originalTotal,
    required this.originalPassed,
    required this.pendingParent,
    required this.plansTotal,
    required this.plansPassed,
  });
  final bool ready, read;
  final int originalTotal,
      originalPassed,
      pendingParent,
      plansTotal,
      plansPassed;
  bool get complete =>
      ready &&
      read &&
      originalPassed == originalTotal &&
      plansPassed == plansTotal &&
      pendingParent == 0;
  String get label => complete
      ? '本课练习已完成'
      : !ready
      ? (read ? '已读' : '未读')
      : '${read ? '已读 · ' : ''}原题 $originalPassed/$originalTotal · 巩固 $plansPassed/$plansTotal${pendingParent > 0 ? ' · $pendingParent 题待核对' : ''}';
}

MathTextbookLessonProgress mathTextbookLessonProgress(
  MathTextbookLesson lesson,
  String bookId,
  MathTextbookProgress progress, {
  MathTextbookPracticeAvailability? availability,
}) {
  final learning = lesson.learning;
  final access =
      availability ?? mathTextbookPracticeAvailability(lesson, bookId);
  var originalPassed = 0, pending = 0, plansPassed = 0;
  for (final exercise in learning?.exercises ?? <MathTextbookExercise>[]) {
    final record = progress
        .targets[MathTextbookProgress.targetKey(lesson.id, null, exercise.id)];
    if (record == null ||
        record.scopeDigest !=
            mathTextbookTargetDigest(lesson, null, exercise.id)) {
      continue;
    }
    if (record.passed) originalPassed++;
    if (record.result == MathTextbookResult.pendingParent) pending++;
  }
  for (final plan in learning?.practicePlans ?? <MathTextbookPracticePlan>[]) {
    final count = plan.kind == MathTextbookPracticeKind.parentTask
        ? 1
        : plan.count;
    String? sessionId;
    var passed = true;
    String? digest;
    for (var i = 0; i < count; i++) {
      final record =
          progress.targets[MathTextbookProgress.targetKey(
            lesson.id,
            plan.id,
            '${plan.id}-$i',
          )];
      if (record == null) {
        passed = false;
        continue;
      }
      digest ??= mathTextbookTargetDigest(lesson, plan.id, '${plan.id}-0');
      if (record.scopeDigest != digest) {
        passed = false;
        continue;
      }
      if (record.result == MathTextbookResult.pendingParent) pending++;
      if (!record.passed ||
          sessionId != null && sessionId != record.sessionId) {
        passed = false;
      }
      sessionId ??= record.sessionId;
    }
    if (passed) plansPassed++;
  }
  return MathTextbookLessonProgress(
    ready: access.ready,
    read:
        progress.readLessons.containsKey(lesson.id) &&
        progress.readLessons[lesson.id] == mathTextbookReadingDigest(lesson),
    originalTotal: learning?.exercises.length ?? 0,
    originalPassed: originalPassed,
    pendingParent: pending,
    plansTotal: learning?.practicePlans.length ?? 0,
    plansPassed: plansPassed,
  );
}
