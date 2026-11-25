import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/domain/english_practice.dart';

import '../../../helpers/english_fixture.dart';
import '../../../helpers/english_phrase_fixture.dart';
import '../../../helpers/hive_test_helper.dart';

void main() {
  late Directory root;
  late EnglishCourseRepository repo;
  late EnglishCourse initial;
  setUp(() async {
    await setUpHiveForTesting();
    root = await Directory.systemTemp.createTemp('english-phrases-');
    repo = EnglishCourseRepository(directoryProvider: () async => root);
    initial = phraseCourse();
    await repo.seed(englishBook(), initial, check: () {});
  });
  tearDown(() async {
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });
  Future<EnglishCourse> append({int revision = 0, void Function()? check}) =>
      repo.appendPhrases(
        englishBook(),
        lessonId: initial.lessons.single.id,
        expectedRevision: revision,
        phrases: phraseTargets(initial),
        check: check ?? () {},
      );

  test('追加、重开、重复、原书重新整理与采用候选均保留稳定短语及原词草稿', () async {
    final oldQuestion = buildEnglishQuestions(
      initial,
      EnglishPracticeKind.meaning,
    ).first;
    final saved = await append();
    final phraseJson = saved.lessons.single.phrases
        .map((t) => t.toJson())
        .toList();
    expect(saved.schemaVersion, 2);
    expect(saved.lessons.single.edited, isFalse);
    expect(saved.lessons.single.approvedCount, 0);
    final reloaded = (await EnglishCourseRepository(
      directoryProvider: () async => root,
    ).load(englishBook()))!;
    expect(reloaded.toJson(), saved.toJson());
    expect((await append(revision: saved.revision)).revision, saved.revision);
    validateEnglishQuestion(reloaded, oldQuestion);
    final progress = EnglishProgressRepository(englishBook(), repo);
    await progress.complete(
      EnglishAttempt(
        id: 'old-draft',
        lessonId: oldQuestion.lessonId,
        title: '词义',
        kind: 'practice',
        completedAt: DateTime(2026, 11, 25),
        durationSeconds: 3,
        answers: [
          EnglishAnswer(
            question: oldQuestion,
            answer: oldQuestion.answers.single,
            correct: true,
          ),
        ],
      ),
    );
    final history = progress.load().toJson();
    var current = await repo.saveGenerated(
      englishBook(),
      initial.lessons.single,
      check: () {},
    );
    expect(current.lessons.single.phrases.map((t) => t.toJson()), phraseJson);
    current = await repo.saveLesson(
      englishBook(),
      initial.lessons.single,
      expectedRevision: current.revision,
      check: () {},
    );
    current = await repo.saveGenerated(
      englishBook(),
      initial.lessons.single,
      check: () {},
    );
    expect(current.pending, hasLength(1));
    current = await repo.saveLesson(
      englishBook(),
      current.pending.single,
      expectedRevision: current.revision,
      adopt: true,
      check: () {},
    );
    expect(current.lessons.single.phrases.map((t) => t.toJson()), phraseJson);
    expect(progress.load().toJson(), history);
  });

  test('旧 revision、取消、原词伪造与删书后的响应不能写入', () async {
    await expectLater(
      append(check: () => throw StateError('cancelled')),
      throwsStateError,
    );
    expect((await repo.load(englishBook()))!.toJson(), initial.toJson());
    await append();
    await expectLater(append(), throwsFormatException);
    final invalid = phraseTargets(initial).first.change({
      'phraseSource': {
        ...phraseTargets(initial).first.phraseSource!.toJson(),
        'text': 'mother',
      },
      'text': 'my mother',
    });
    await expectLater(
      repo.appendPhrases(
        englishBook(),
        lessonId: initial.lessons.single.id,
        expectedRevision: 1,
        phrases: [invalid],
        check: () {},
      ),
      throwsFormatException,
    );
    await repo.clear(englishBook(), check: () {});
    await expectLater(append(revision: 1), throwsFormatException);
    expect(await repo.load(englishBook()), isNull);
  });

  test('取消发生于临时文件写入后也不替换课程，队列可继续保存', () async {
    var checks = 0;
    await expectLater(
      append(
        check: () {
          if (++checks == 5) throw StateError('cancelled');
        },
      ),
      throwsStateError,
    );
    expect((await repo.load(englishBook()))!.toJson(), initial.toJson());
    expect(
      await File(
        '${root.path}/textbooks/english-courses/${initial.bookId}.json.pending',
      ).exists(),
      isFalse,
    );
    expect((await append()).lessons.single.phrases, hasLength(2));
  });
}
