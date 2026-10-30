import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_exercise_repository.dart';
import 'package:poemath/domain/textbook_exercise.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_course_fixture.dart';

void main() {
  late Directory directory;
  late TextbookCourseRepository courses;
  late TextbookExerciseRepository repository;
  final book = courseFixtureBook();

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    directory = await Directory.systemTemp.createTemp('exercise-repo-');
    courses =
        TextbookCourseRepository(directoryProvider: () async => directory);
    final pack = TextbookCoursePack.fromJson(
      courseFixture(reviewed: true, permitted: true),
    );
    await courses.importDraft(book, pack);
    repository = TextbookExerciseRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
    );
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  test('口答提交、家长核对和最近状态会保存并可重开读取', () async {
    final first = await repository.load();
    expect(first.records, isEmpty);

    final attempted = await repository.recordAttempt(
      lessonId: 'lesson-001',
      exerciseId: 'exercise-001',
      answer: const TextbookExerciseAnswer.oral(),
      day: '2026-10-29',
      operationId: 'attempt-1',
      expectedRevision: first.revision,
    );
    expect(attempted.revision, 1);
    final key =
        TextbookExerciseProgress.targetKey('lesson-001', 'exercise-001');
    expect(
      attempted.records[key]!.lastResult,
      TextbookExerciseResult.parentPending,
    );

    final checked = await repository.recordParentCheck(
      lessonId: 'lesson-001',
      exerciseId: 'exercise-001',
      passed: true,
      day: '2026-10-29',
      operationId: 'parent-1',
      expectedRevision: attempted.revision,
    );
    expect(checked.records[key]!.parentConfirms, 1);
    expect(
      checked.records[key]!.lastResult,
      TextbookExerciseResult.parentCorrect,
    );

    final reopened = TextbookExerciseRepository(
      book: book,
      editionId: checked.editionId,
      courses: courses,
    );
    expect((await reopened.load()).toJson(), checked.toJson());
  });
}
