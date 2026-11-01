import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/domain/textbook_exercise.dart';
import 'package:poemath/domain/textbook_lesson_content.dart';

class TextbookExerciseRepository {
  TextbookExerciseRepository({
    required this.book,
    required this.editionId,
    required this.courses,
    Box<dynamic>? box,
  })  : profileId = ProfileScope.currentId,
        _profileRevision = ProfileScope.revision,
        _box = box ?? HiveBoxes.settings,
        epoch =
            HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int;

  final Textbook book;
  final String editionId;
  final String profileId;
  final TextbookCourseRepository courses;
  final Box<dynamic> _box;
  final int epoch;
  final int _profileRevision;
  final _guard = PracticeDraftRepository();
  static final Map<String, Future<void>> _tails = {};

  String get key => 'textbook_exercise_v1:${textbookTextDigest(
        jsonEncode([profileId, book.pdfSha256, editionId]),
      )}';

  void _current() {
    _guard.assertCurrent();
    if (ProfileScope.currentId != profileId ||
        ProfileScope.revision != _profileRevision) {
      throw StateError('档案已切换，请重新进入习题练习');
    }
  }

  TextbookExerciseProgress _read() {
    final raw = _box.get(key);
    final progress = raw == null
        ? TextbookExerciseProgress(
            profileId: profileId,
            bookId: book.pdfSha256,
            editionId: editionId,
          )
        : TextbookExerciseProgress.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          );
    if (progress.profileId != profileId ||
        progress.bookId != book.pdfSha256 ||
        progress.editionId != editionId) {
      throw const FormatException('习题记录教材或档案不匹配');
    }
    return progress;
  }

  List<TextbookCourseExercise> _approvedExercises(
    TextbookCoursePack pack,
    TextbookCourseLesson lesson,
  ) =>
      textbookVisibleTargets(pack, lesson, TextbookContentSection.exercise)
          .cast<TextbookCourseExercise>();

  TextbookExerciseProgress _currentContent(
    TextbookExerciseProgress progress,
    TextbookCoursePack pack,
  ) {
    final records = <String, TextbookExerciseRecord>{};
    for (final lesson in pack.lessons) {
      for (final exercise in _approvedExercises(pack, lesson)) {
        final key = TextbookExerciseProgress.targetKey(lesson.id, exercise.id);
        final old = progress.records[key];
        if (old?.fingerprint == exercise.contentDigest) records[key] = old!;
      }
    }
    return progress.copyWith(records: records);
  }

  Future<T> _serial<T>(Future<T> Function() action) => _guard.guard(() async {
        final previous = _tails[key];
        final work = () async {
          if (previous != null) {
            try {
              await previous;
            } on Object {/* 后续重试不受失败影响。 */}
          }
          _current();
          return action();
        }();
        final tail =
            work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
        _tails[key] = tail;
        try {
          return await work;
        } finally {
          if (identical(_tails[key], tail)) _tails.remove(key);
        }
      });

  Future<TextbookExerciseProgress> load() => _serial(
        () => courses.withCurrentPack(book, (pack) async {
          _current();
          var progress = _read();
          if (pack != null) progress = _currentContent(progress, pack);
          return progress;
        }),
      );

  Future<TextbookExerciseProgress> change({
    required String lessonId,
    required String exerciseId,
    required String operationId,
    required int expectedRevision,
    required TextbookExerciseProgress Function(
      TextbookExerciseProgress progress,
      TextbookCourseExercise exercise,
    ) reduce,
  }) =>
      _serial(
        () => courses.withCurrentPack(book, (pack) async {
          _current();
          if (pack == null || pack.edition.id != editionId) {
            throw StateError('教材内容已更新，请重新进入习题练习');
          }
          final lesson =
              pack.lessons.where((item) => item.id == lessonId).firstOrNull;
          if (lesson == null) throw StateError('课目已更新，请重新进入习题练习');
          final exercise = _approvedExercises(pack, lesson)
              .where((item) => item.id == exerciseId)
              .firstOrNull;
          if (exercise == null) {
            throw StateError('习题尚未审核或已更新，请重新进入');
          }
          var progress = _currentContent(_read(), pack);
          if (progress.operations.contains(operationId)) return progress;
          if (progress.revision != expectedRevision) {
            throw StateError('学习记录已变化，请重新进入习题练习');
          }
          progress = reduce(progress, exercise).copyWith(
            revision: progress.revision + 1,
            operations: [...progress.operations, operationId]
                .reversed
                .take(200)
                .toList()
                .reversed
                .toList(),
          );
          _current();
          await _box.put(key, jsonEncode(progress.toJson()));
          return progress;
        }),
      );

  Future<TextbookExerciseProgress> recordAttempt({
    required String lessonId,
    required String exerciseId,
    required TextbookExerciseAnswer answer,
    required String day,
    required String operationId,
    required int expectedRevision,
  }) =>
      change(
        lessonId: lessonId,
        exerciseId: exerciseId,
        operationId: operationId,
        expectedRevision: expectedRevision,
        reduce: (progress, exercise) {
          final evaluation = evaluateTextbookExercise(exercise, answer);
          final targetKey =
              TextbookExerciseProgress.targetKey(lessonId, exerciseId);
          final old = progress.records[targetKey] ??
              TextbookExerciseRecord(fingerprint: exercise.contentDigest);
          final automatic = evaluation.result == TextbookExerciseResult.correct;
          final incorrect =
              evaluation.result == TextbookExerciseResult.incorrect;
          return progress.copyWith(
            records: {
              ...progress.records,
              targetKey: old.copyWith(
                attempts: old.attempts + 1,
                automaticCorrect: old.automaticCorrect + (automatic ? 1 : 0),
                automaticIncorrect:
                    old.automaticIncorrect + (incorrect ? 1 : 0),
                lastAnswer: answer,
                lastResult: evaluation.result,
                lastItemResults: evaluation.itemResults,
                lastDay: day,
              ),
            },
          );
        },
      );

  Future<TextbookExerciseProgress> recordParentCheck({
    required String lessonId,
    required String exerciseId,
    required bool passed,
    required String day,
    required String operationId,
    required int expectedRevision,
  }) =>
      change(
        lessonId: lessonId,
        exerciseId: exerciseId,
        operationId: operationId,
        expectedRevision: expectedRevision,
        reduce: (progress, exercise) {
          final targetKey =
              TextbookExerciseProgress.targetKey(lessonId, exerciseId);
          final old = progress.records[targetKey] ??
              TextbookExerciseRecord(fingerprint: exercise.contentDigest);
          return progress.copyWith(
            records: {
              ...progress.records,
              targetKey: old.copyWith(
                parentConfirms: old.parentConfirms + (passed ? 1 : 0),
                parentAgain: old.parentAgain + (passed ? 0 : 1),
                lastResult: passed
                    ? TextbookExerciseResult.parentCorrect
                    : TextbookExerciseResult.parentAgain,
                lastParentDay: day,
              ),
            },
          );
        },
      );
}
