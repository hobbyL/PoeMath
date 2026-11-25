import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
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
  test('单词自评分离保存；待复习次日进入词义题，客观答对再推进间隔', () async {
    final book = englishBook();
    final course = englishCourse(
      book: book,
      lessons: [
        englishLesson(
          targets: [
            englishWord(approved: false),
            englishWord(
              id: 'word-2',
              text: 'blue bird',
              meaning: '蓝鸟',
              approved: false,
            ),
            EnglishTarget(
              id: 'sentence-1',
              kind: EnglishTargetKind.sentence,
              text: 'Hello.',
              sources: const [EnglishSource(3)],
            ).approve(),
          ],
        ),
      ],
    );
    await courses.seed(book, course, check: () {});
    final repository = EnglishProgressRepository(book, courses),
        lesson = course.lessons.single,
        q = buildEnglishQuestions(
          course,
          EnglishPracticeKind.meaning,
          lessonId: lesson.id,
        ).first,
        recordKey = q.recordKey;

    expect(q.target.approved, isFalse);
    await repository.remember(lesson.id, targetId: q.target.id);
    await repository.selfAssessVocabulary(
      lesson.id,
      q.target.id,
      expectedFingerprint: q.target.fingerprint,
      mastered: true,
      now: DateTime(2026, 11, 23),
    );
    var record = repository.load().reviews[recordKey]!;
    expect(record.selfCorrect, 1);
    expect(record.selfAgain, 0);
    expect(record.lastSelfRating, 'mastered');
    expect(record.correct, 0);
    expect(record.incorrect, 0);
    expect(record.stage, 0);
    expect(record.nextDay, isNull);

    await repository.selfAssessVocabulary(
      lesson.id,
      q.target.id,
      expectedFingerprint: q.target.fingerprint,
      mastered: false,
      now: DateTime(2026, 11, 23),
    );
    record = repository.load().reviews[recordKey]!;
    expect(record.selfCorrect, 1);
    expect(record.selfAgain, 1);
    expect(record.lastSelfRating, 'again');
    expect(record.correct, 0);
    expect(record.incorrect, 0);
    expect(record.stage, 0);
    expect(record.lastDay, '2026-11-23');
    expect(record.nextDay, '2026-11-24');
    expect(repository.dueKeys(course, DateTime(2026, 11, 23)), isEmpty);
    expect(repository.dueKeys(course, DateTime(2026, 11, 24)), {recordKey});
    expect(
      buildEnglishQuestions(
        course,
        EnglishPracticeKind.meaning,
        targetKeys: repository.dueKeys(course, DateTime(2026, 11, 24)),
      ).map((question) => question.recordKey),
      [recordKey],
    );

    await repository.complete(
      EnglishAttempt(
        id: 'due-meaning',
        lessonId: lesson.id,
        title: '词义练习',
        kind: 'practice',
        completedAt: DateTime(2026, 11, 24),
        durationSeconds: 15,
        answers: [
          EnglishAnswer(
            question: q,
            answer: q.answers.first,
            correct: true,
            hinted: false,
            skipped: false,
          ),
        ],
      ),
    );
    record = repository.load().reviews[recordKey]!;
    expect(record.correct, 1);
    expect(record.incorrect, 0);
    expect(record.stage, 1);
    expect(record.nextDay, '2026-11-27');
    expect(record.selfCorrect, 1);
    expect(record.selfAgain, 1);
    expect(record.lastSelfRating, 'again');
    final beforeStaleRating = record;
    await expectLater(
      repository.selfAssessVocabulary(
        lesson.id,
        q.target.id,
        expectedFingerprint: 'stale-fingerprint',
        mastered: true,
      ),
      throwsFormatException,
    );
    expect(
      repository.load().reviews[recordKey]!.toJson(),
      beforeStaleRating.toJson(),
    );
    await expectLater(
      repository.selfAssessVocabulary(
        lesson.id,
        'sentence-1',
        expectedFingerprint: course
            .target(lesson.id, 'sentence-1')!
            .fingerprint,
        mastered: true,
      ),
      throwsFormatException,
    );
  });
  test('词汇被编辑后，同一目标 ID 不继承旧内容的自评', () async {
    final book = englishBook(), course = englishCourse();
    await courses.seed(book, course, check: () {});
    final repository = EnglishProgressRepository(book, courses),
        lesson = course.lessons.single;
    await repository.selfAssessVocabulary(
      lesson.id,
      'word-1',
      expectedFingerprint: course.target(lesson.id, 'word-1')!.fingerprint,
      mastered: true,
      now: DateTime(2026, 11, 23),
    );
    final old = repository.load().reviews['${lesson.id}/word-1/meaning']!;
    final changedLesson = lesson.change({
      'targets': [
        for (final target in lesson.targets)
          (target.id == 'word-1' ? englishWord(text: 'green kite') : target)
              .toJson(),
      ],
    });
    await courses.saveLesson(
      book,
      changedLesson,
      expectedRevision: course.revision,
      check: () {},
    );
    await repository.selfAssessVocabulary(
      lesson.id,
      'word-1',
      expectedFingerprint: changedLesson.targets
          .firstWhere((target) => target.id == 'word-1')
          .fingerprint,
      mastered: true,
      now: DateTime(2026, 11, 24),
    );
    final current = repository.load().reviews['${lesson.id}/word-1/meaning']!;
    expect(current.fingerprint, changedLesson.targets.first.fingerprint);
    expect(current.fingerprint, isNot(old.fingerprint));
    expect(current.selfCorrect, 1);
    expect(current.selfAgain, 0);
    expect(current.correct, 0);
    expect(current.nextDay, isNull);
  });
}
