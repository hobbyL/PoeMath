import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookTextDigest;
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

class EnglishProgressRepository {
  EnglishProgressRepository(
    this.book,
    this.courses, {
    Box<dynamic>? box,
    LearningActivityRepository? activities,
  }) : profileId = ProfileScope.currentId,
       revision = ProfileScope.revision,
       _box = box ?? HiveBoxes.settings,
       _activities = activities ?? LearningActivityRepository();
  final Textbook book;
  final EnglishCourseRepository courses;
  final String profileId;
  final int revision;
  final Box<dynamic> _box;
  final LearningActivityRepository _activities;
  final _guard = PracticeDraftRepository();
  static final Map<String, Future<void>> _tails = {};
  static String keyFor(String profileId, String bookId, String editionId) =>
      '${EnglishProgress.prefix}${textbookTextDigest(jsonEncode([profileId, bookId, editionId]))}';
  String get key => keyFor(profileId, book.pdfSha256, book.learningEditionId);

  /// 原书未下载或尚未登记时，恢复的文字记录依然可以独立浏览。
  static List<EnglishProgress> savedForProfile() {
    final result = <EnglishProgress>[];
    for (final key in HiveBoxes.settings.keys.whereType<String>()) {
      if (!key.startsWith(EnglishProgress.prefix)) continue;
      final raw = HiveBoxes.settings.get(key);
      if (raw is! String) continue;
      try {
        final value = EnglishProgress.fromJson(jsonDecode(raw));
        if (value.profileId == ProfileScope.currentId &&
            key == keyFor(value.profileId, value.bookId, value.editionId)) {
          result.add(value);
        }
      } on Object {
        /* 无法识别归属的损坏记录不展示给其他档案。 */
      }
    }
    return result;
  }

  void check() {
    _guard.assertCurrent();
    if (profileId != ProfileScope.currentId ||
        revision != ProfileScope.revision) {
      throw StateError('档案已切换，请重新进入英语');
    }
  }

  EnglishProgress load() {
    check();
    final raw = _box.get(key);
    final p = raw == null
        ? EnglishProgress(
            profileId: profileId,
            bookId: book.pdfSha256,
            editionId: book.learningEditionId,
          )
        : EnglishProgress.fromJson(jsonDecode(raw as String));
    if (p.profileId != profileId ||
        p.bookId != book.pdfSha256 ||
        p.editionId != book.learningEditionId) {
      throw const FormatException('英语记录归属无效');
    }
    return p;
  }

  Future<T> _serial<T>(Future<T> Function() action) => _guard.guard(() async {
    final previous = _tails[key];
    final work = () async {
      if (previous != null) {
        try {
          await previous;
        } on Object {
          /* retry */
        }
      }
      check();
      return action();
    }();
    final tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    try {
      return await work;
    } finally {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  });
  Future<void> _save(EnglishProgress value) async {
    check();
    EnglishProgress.fromJson(value.toJson());
    await _box.put(key, jsonEncode(value.toJson()));
    check();
  }

  Future<void> remember(String lessonId, {String? targetId}) => _serial(
    () => courses.withCurrent(book, (course) async {
      check();
      if (course?.lesson(lessonId) == null ||
          (targetId != null &&
              course?.target(lessonId, targetId)?.approved != true)) {
        throw const FormatException('学习内容已变化，请重新打开课时');
      }
      final p = load();
      await _save(
        EnglishProgress(
          profileId: profileId,
          bookId: book.pdfSha256,
          editionId: book.learningEditionId,
          lastLessonId: lessonId,
          lastTargetId: targetId,
          reviews: p.reviews,
          attempts: p.attempts,
        ),
      );
    }),
  );

  Future<void> complete(EnglishAttempt attempt) => _serial(
    () => courses.withCurrent(book, (course) async {
      check();
      final p = load();
      final existing = p.attempts.where((a) => a.id == attempt.id).firstOrNull;
      if (existing == null) {
        if (course == null) throw const FormatException('课程内容已移除，请重新打开');
        EnglishAttempt.fromJson(attempt.toJson());
        if (attempt.answers.map((a) => a.question.id).toSet().length !=
                attempt.answers.length ||
            attempt.kind == 'practice' && attempt.answers.isEmpty) {
          throw const FormatException('本轮练习记录无效');
        }
        if (attempt.kind == 'speaking') {
          if (attempt.spokenTexts.isEmpty ||
              attempt.recordingIds.length != attempt.spokenTexts.length ||
              attempt.spokenFingerprints.length != attempt.spokenTexts.length) {
            throw const FormatException('跟读录音未保存完整');
          }
          for (final entry in attempt.spokenFingerprints.entries) {
            final target = course.target(attempt.lessonId, entry.key);
            if (target == null ||
                !target.approved ||
                target.fingerprint != entry.value ||
                !attempt.spokenTexts.contains(target.text)) {
              throw const FormatException('跟读内容已更新，请重新开始');
            }
          }
        }
        for (final answer in attempt.answers) {
          final q = answer.question, t = course.target(q.lessonId, q.target.id);
          validateEnglishQuestion(course, q);
          if (answer.parentPassed != null ||
              answer.skipped && answer.correct != null ||
              q.parentCheck && answer.correct != null) {
            throw const FormatException('此作答不能标为已核对');
          }
          if (t == null ||
              !t.approved ||
              t.fingerprint != q.target.fingerprint ||
              q.voiceKey != null && !t.audioApproved(q.voiceKey!)) {
            throw const FormatException('题目内容已更新，请重新开始本轮');
          }
          if (!answer.skipped &&
              !q.parentCheck &&
              answer.correct != q.accepts(answer.answer)) {
            throw const FormatException('作答结果与答案不符');
          }
        }
        final records = {...p.reviews};
        for (final answer in attempt.answers) {
          records[answer.question.recordKey] = updateEnglishReview(
            records[answer.question.recordKey],
            answer,
            attempt.completedAt,
          );
        }
        await _save(
          EnglishProgress(
            profileId: profileId,
            bookId: book.pdfSha256,
            editionId: book.learningEditionId,
            lastLessonId: attempt.lessonId,
            lastTargetId: p.lastTargetId,
            reviews: records,
            attempts: [...p.attempts, attempt],
          ),
        );
      } else if (jsonEncode(existing.toJson()) !=
          jsonEncode(attempt.toJson())) {
        throw const FormatException('这次学习已经保存，请查看原记录');
      }
      check();
      await _activities.record(
        id: 'english:${book.pdfSha256}:${attempt.id}',
        activityType: attempt.kind == 'speaking'
            ? LearningActivityType.englishSpeaking
            : LearningActivityType.englishPractice,
        totalItems: attempt.kind == 'speaking'
            ? attempt.spokenTexts.length
            : attempt.answers.length,
        successfulItems: attempt.kind == 'speaking' ? 0 : attempt.correct,
        starsEarned: 0,
        durationSeconds: attempt.durationSeconds,
        completedAt: attempt.completedAt,
      );
      check();
    }),
  );

  Future<void> parentCheck(
    String attemptId,
    int index,
    bool passed,
    void Function() authorize,
  ) => _serial(
    () => courses.withCurrent(book, (course) async {
      authorize();
      final p = load();
      final attempt = p.attempts.where((a) => a.id == attemptId).first;
      final old = attempt.answers[index];
      if (old.skipped) throw const FormatException('已跳过的题不能标为完成');
      if (!old.question.parentCheck) throw const FormatException('此题由客观答案核对');
      final answers = [...attempt.answers];
      answers[index] = EnglishAnswer(
        question: old.question,
        answer: old.answer,
        correct: old.correct,
        hinted: old.hinted,
        skipped: old.skipped,
        parentPassed: passed,
      );
      final next = EnglishAttempt(
        id: attempt.id,
        lessonId: attempt.lessonId,
        title: attempt.title,
        kind: attempt.kind,
        completedAt: attempt.completedAt,
        durationSeconds: attempt.durationSeconds,
        answers: answers,
        spokenTexts: attempt.spokenTexts,
        recordingIds: attempt.recordingIds,
        spokenFingerprints: attempt.spokenFingerprints,
      );
      final records = {...p.reviews};
      final current = course?.target(
        old.question.lessonId,
        old.question.target.id,
      );
      if (old.parentPassed != passed &&
          current?.approved == true &&
          current!.fingerprint == old.question.target.fingerprint) {
        records[old.question.recordKey] = updateEnglishReview(
          records[old.question.recordKey],
          answers[index],
          DateTime.now(),
        );
      }
      authorize();
      await _save(
        EnglishProgress(
          profileId: profileId,
          bookId: book.pdfSha256,
          editionId: book.learningEditionId,
          lastLessonId: p.lastLessonId,
          lastTargetId: p.lastTargetId,
          reviews: records,
          attempts: p.attempts
              .map((a) => a.id == attemptId ? next : a)
              .toList(),
        ),
      );
    }),
  );

  Set<String> retryKeys(EnglishCourse course) {
    final latest = <String, EnglishAnswer>{};
    for (final attempt in load().attempts) {
      for (final answer in attempt.answers) {
        if (!answer.skipped) latest[answer.question.recordKey] = answer;
      }
    }
    return {
      for (final entry in latest.entries)
        if ((entry.value.correct == false ||
                entry.value.parentPassed == false ||
                entry.value.hinted) &&
            course
                    .target(
                      entry.value.question.lessonId,
                      entry.value.question.target.id,
                    )
                    ?.fingerprint ==
                entry.value.question.target.fingerprint)
          entry.key,
    };
  }

  Set<String> dueKeys(EnglishCourse course, DateTime now) {
    final day = englishDay(now), p = load();
    return {
      for (final e in p.reviews.entries)
        if (e.value.nextDay != null &&
            e.value.nextDay!.compareTo(day) <= 0 &&
            course.lessons.any(
              (l) => l.targets.any(
                (t) =>
                    t.approved &&
                    e.key.startsWith('${l.id}/${t.id}/') &&
                    t.fingerprint == e.value.fingerprint,
              ),
            ))
          e.key,
    };
  }
}
