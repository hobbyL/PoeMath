import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';

import '../../../helpers/english_fixture.dart';
import '../../../helpers/hive_test_helper.dart';

void main() {
  late Directory root;
  late EnglishCourseRepository courses;
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    root = await Directory.systemTemp.createTemp('english-repos-');
    courses = EnglishCourseRepository(directoryProvider: () async => root);
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });
  test('新稿不覆盖人工稿、显式采用候选、版本冲突与锁定不写入', () async {
    final book = englishBook(), initial = englishCourse();
    await courses.seed(book, initial, check: () {});
    final current = await courses.saveLesson(
      book,
      initial.lessons.single,
      expectedRevision: 0,
      check: () {},
    );
    final generated = englishLesson(
      targets: [englishWord(text: 'new words', approved: false)],
    );
    final pending = await courses.saveGenerated(book, generated, check: () {});
    expect(pending.lessons.single.targets.first.text, 'red kite');
    expect(pending.pending.single.targets.first.text, 'new words');
    await expectLater(
      courses.saveLesson(
        book,
        generated,
        expectedRevision: current.revision,
        check: () {},
      ),
      throwsFormatException,
    );
    await expectLater(
      courses.saveLesson(
        book,
        generated,
        expectedRevision: pending.revision,
        check: () => throw StateError('locked'),
      ),
      throwsStateError,
    );
    final saved = await courses.saveLesson(
      book,
      generated,
      expectedRevision: pending.revision,
      check: () {},
      adopt: true,
    );
    expect(saved.pending, isEmpty);
    expect(saved.lessons.single.approvedCount, 0);
    expect(
      (await EnglishCourseRepository(directoryProvider: () async => root)
              .load(book))!
          .toJson(),
      saved.toJson(),
    );
    expect(
      await File(
        '${root.path}/textbooks/english-courses/${book.pdfSha256}.json.pending',
      ).exists(),
      isFalse,
    );
  });
  test('保存幂等、版本失效、档案切换及恢复 epoch 不能写旧会话', () async {
    final book = englishBook(), course = englishCourse();
    await courses.seed(book, course, check: () {});
    final repository = EnglishProgressRepository(book, courses);
    final q = buildEnglishQuestions(course, EnglishPracticeKind.meaning).first;
    EnglishAttempt attempt(String id) => EnglishAttempt(
      id: id,
      lessonId: q.lessonId,
      title: '词义练习',
      kind: 'practice',
      completedAt: DateTime(2026, 11, 23),
      durationSeconds: 20,
      answers: [
        EnglishAnswer(question: q, answer: q.answers.first, correct: true),
      ],
    );
    await repository.complete(attempt('same'));
    await repository.complete(attempt('same'));
    expect(repository.load().attempts, hasLength(1));
    expect(HiveBoxes.learningActivities.length, 1);
    final saved = repository.load().toJson();
    await courses.saveLesson(
      book,
      englishLesson(
        targets: [
          englishWord(text: 'changed'),
          englishWord(id: 'other'),
        ],
      ),
      expectedRevision: 0,
      check: () {},
    );
    await expectLater(
      repository.complete(attempt('changed')),
      throwsFormatException,
    );
    expect(repository.load().toJson(), saved);
    ProfileScope.switchTo('other');
    await expectLater(repository.complete(attempt('other')), throwsStateError);
    ProfileScope.reset();
    expect(() => repository.load(), throwsStateError);
    final reopened = EnglishProgressRepository(book, courses);
    await PracticeDraftRepository.whileRestoring(() async {
      await HiveBoxes.meta.put('practice_draft_epoch', 1);
    });
    expect(() => reopened.load(), throwsStateError);
    expect(jsonDecode(HiveBoxes.settings.get(reopened.key) as String), saved);
  });
  test('错项与提示项只按最新有效版本再练，伪造答案不能结算', () async {
    final book = englishBook(), course = englishCourse();
    await courses.seed(book, course, check: () {});
    final repository = EnglishProgressRepository(book, courses);
    final q = buildEnglishQuestions(course, EnglishPracticeKind.meaning).first;
    EnglishAttempt attempt(
      String id,
      EnglishQuestion question, {
      bool correct = false,
      bool hint = false,
    }) => EnglishAttempt(
      id: id,
      lessonId: q.lessonId,
      title: '词义',
      kind: 'practice',
      completedAt: DateTime(2026, 11, 23),
      durationSeconds: 10,
      answers: [
        EnglishAnswer(
          question: question,
          answer: correct ? q.answers.first : '错误答案',
          correct: correct,
          hinted: hint,
        ),
      ],
    );
    await repository.complete(attempt('incorrect', q));
    expect(repository.retryKeys(course), {q.recordKey});
    expect(repository.dueKeys(course, DateTime(2026, 11, 23)), isEmpty);
    expect(repository.dueKeys(course, DateTime(2026, 11, 24)), {q.recordKey});
    await repository.complete(attempt('hint', q, correct: true, hint: true));
    expect(repository.retryKeys(course), {q.recordKey});
    await repository.complete(attempt('independent', q, correct: true));
    expect(repository.retryKeys(course), isEmpty);
    final forged = EnglishQuestion.fromJson({
      ...q.toJson(),
      'answers': ['错误答案'],
    });
    await expectLater(
      repository.complete(attempt('forged', forged)),
      throwsFormatException,
    );
    expect(repository.load().attempts, hasLength(3));
  });
}
