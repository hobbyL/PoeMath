import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
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
    courses = TextbookCourseRepository(
      directoryProvider: () async => directory,
    );
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
      fingerprint: (await courses.load(book))!
          .lessons
          .single
          .exercises
          .single
          .contentDigest,
      answer: const TextbookExerciseAnswer.oral(),
      day: '2026-10-29',
      operationId: 'attempt-1',
      expectedRevision: first.revision,
    );
    expect(attempted.revision, 1);
    final key = TextbookExerciseProgress.targetKey(
      'lesson-001',
      'exercise-001',
    );
    expect(
      attempted.records[key]!.lastResult,
      TextbookExerciseResult.parentPending,
    );

    final checked = await repository.recordParentCheck(
      lessonId: 'lesson-001',
      exerciseId: 'exercise-001',
      fingerprint: (await courses.load(book))!
          .lessons
          .single
          .exercises
          .single
          .contentDigest,
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

  test('重新导入同 ID 的已审核新题后拒绝旧页面的提交', () async {
    final old = await courses.load(book);
    final raw = courseFixture(reviewed: true, permitted: true);
    final lesson = (raw['lessons'] as List).single as Map;
    final exercise = (lesson['exercises'] as List).single as Map;
    exercise['prompt'] = '请说说另一幅画里的故事。';
    final changed = TextbookCoursePack.fromJson(
      reviewTextbookCourse(
        input: raw,
        nodeId: 'exercise-001',
        reviewer: '合成审核者',
        decision: 'approved',
        checks: ['sourcePages', 'content', 'answer'],
        notes: '',
      ),
    );
    expect(changed.lessons.single.exercises.single.isApproved, isTrue);
    expect(
      changed.lessons.single.exercises.single.contentDigest,
      isNot(old!.lessons.single.exercises.single.contentDigest),
    );
    await courses.importDraft(book, changed);
    await expectLater(
      repository.recordAttempt(
        lessonId: 'lesson-001',
        exerciseId: 'exercise-001',
        fingerprint: old.lessons.single.exercises.single.contentDigest,
        answer: const TextbookExerciseAnswer.oral(),
        day: '2026-11-11',
        operationId: 'old-question',
        expectedRevision: 0,
      ),
      throwsStateError,
    );
    expect((await repository.load()).records, isEmpty);
  });

  test('单题审核通过即可保存作答，其他内容审核不影响当前题目记录', () async {
    final pack = TextbookCoursePack.fromJson(
      courseFixtureWithReviewedExercise(),
    );
    await courses.importDraft(book, pack);
    final first = await repository.load();
    final attempted = await repository.recordAttempt(
      lessonId: 'lesson-001',
      exerciseId: 'exercise-001',
      fingerprint: (await courses.load(book))!
          .lessons
          .single
          .exercises
          .single
          .contentDigest,
      answer: const TextbookExerciseAnswer.oral(),
      day: '2026-11-01',
      operationId: 'single-approved-attempt',
      expectedRevision: first.revision,
    );
    final key = TextbookExerciseProgress.targetKey(
      'lesson-001',
      'exercise-001',
    );
    expect(attempted.revision, 1);
    expect(attempted.records[key]!.attempts, 1);
    expect(
      attempted.records[key]!.lastResult,
      TextbookExerciseResult.parentPending,
    );

    final checked = await repository.recordParentCheck(
      lessonId: 'lesson-001',
      exerciseId: 'exercise-001',
      fingerprint: (await courses.load(book))!
          .lessons
          .single
          .exercises
          .single
          .contentDigest,
      passed: true,
      day: '2026-11-01',
      operationId: 'single-approved-parent-check',
      expectedRevision: attempted.revision,
    );
    expect(checked.records[key]!.parentConfirms, 1);
    expect(
      checked.records[key]!.lastResult,
      TextbookExerciseResult.parentCorrect,
    );

    final edited = editTextbookCourseNode(pack, 'paragraph-001', {
      'text': '月𠀀，星。',
      'pinyin': ['yuè', 'hē', '，', 'xīng', '。'],
    });
    await courses.save(book, edited, previous: pack);
    final reopened = TextbookExerciseRepository(
      book: book,
      editionId: pack.edition.id,
      courses: courses,
    );
    expect((await reopened.load()).toJson(), checked.toJson());

    final changedQuestion = editTextbookCourseNode(edited, 'exercise-001', {
      'prompt': '请描述你看到的内容。',
    });
    await courses.save(book, changedQuestion, previous: edited);
    expect((await reopened.load()).records, isEmpty);
    await expectLater(
      reopened.recordAttempt(
        lessonId: 'lesson-001',
        exerciseId: 'exercise-001',
        fingerprint: (await courses.load(book))!
            .lessons
            .single
            .exercises
            .single
            .contentDigest,
        answer: const TextbookExerciseAnswer.oral(),
        day: '2026-11-01',
        operationId: 'stale-exercise-attempt',
        expectedRevision: checked.revision,
      ),
      throwsStateError,
    );
  });
}
