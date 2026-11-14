import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/math_textbook_learning_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/textbook_progress_cleanup.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/domain/math_textbook_progress.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_learning_fixture.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  final book = mathTextbookFixture();
  final now = DateTime.utc(2026, 11, 13, 8);
  late Directory root;
  late MathTextbookCourseRepository courses;
  late TextbookRepository books;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    root = await Directory.systemTemp.createTemp('math-learning-test-');
    courses = MathTextbookCourseRepository(directoryProvider: () async => root);
    books = TextbookRepository();
    await books.addIfAbsent(book);
  });
  tearDown(() async {
    await courses.drain();
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });

  MathTextbookLearningRepository repository({bool Function()? active}) =>
      MathTextbookLearningRepository(
        book: book,
        courses: courses,
        findBook: books.find,
        isActive: active,
        clock: () => now,
      );

  Future<void> reopenStorage() async {
    await HiveBoxes.close();
    await HiveBoxes.init();
    books = TextbookRepository();
  }

  Future<MathTextbookLesson> saveLesson(
    MathTextbookLesson lesson, {
    bool reviewed = true,
  }) async {
    final previous =
        await courses.load(book) ??
        await courses.saveGenerated(
          book,
          lesson,
          generation: courses.generation(book.pdfSha256),
          authorize: () {},
        );
    final next = reviewed
        ? lesson.approve(
            pdfSha256: book.pdfSha256,
            reviewer: '测试妈妈',
            editingMilliseconds: 1000,
            at: now,
          )
        : lesson;
    return (await courses.saveLesson(
      book,
      next,
      expectedRevision: previous.revision,
      generation: courses.generation(book.pdfSha256),
      authorize: () {},
    )).lessons.single;
  }

  Future<MathTextbookPracticeDraft> answer(
    MathTextbookLearningRepository repo,
    MathTextbookPracticeDraft draft,
    String text,
  ) async {
    final answers = draft.answers.map((a) => <String, String>{...a}).toList();
    answers[draft.index] = {'answer': text};
    final pending = draft.copyWith(answers: answers);
    await repo.saveDraft(pending);
    final attempt = await repo.submit(pending, pending.index);
    final results = [...pending.results]..[pending.index] = attempt.result;
    final submitted = pending.copyWith(results: results);
    await repo.saveDraft(submitted);
    return submitted;
  }

  Future<MathTextbookPracticeDraft> complete(
    MathTextbookLearningRepository repo,
    MathTextbookPracticeDraft draft,
  ) async {
    final finished = draft.copyWith(
      index: draft.items.length,
      elapsedSeconds: 30,
      finishedAt: now.add(const Duration(seconds: 30, microseconds: 123)),
    );
    await repo.saveDraft(finished);
    await repo.finish(finished);
    return finished;
  }

  test('未审核课时可阅读，重复只保存一次，重启保留PDF与档案进度', () async {
    final lesson = await saveLesson(mathLearningFixture(), reviewed: false);
    final repo = repository();
    await expectLater(repo.start(lesson.id), throwsStateError);
    lockParentForTesting();
    final first = await repo.markRead(
      lesson.id,
      lesson.contentDigest(book.pdfSha256),
    );
    final second = await repo.markRead(
      lesson.id,
      lesson.contentDigest(book.pdfSha256),
    );
    expect(second.toJson(), first.toJson());
    expect(second.revision, 1);
    await reopenStorage();
    final reopened = repository();
    expect((await reopened.load()).toJson(), first.toJson());
    expect(
      mathTextbookLessonProgress(
        lesson,
        book.pdfSha256,
        await reopened.load(),
      ).read,
      isTrue,
    );
    ProfileScope.switchTo('another-child');
    expect((await repository().load()).readLessons, isEmpty);
  });

  test('内容审核可持久完成，未配置的自动练习仍不能开始', () async {
    final source = mathLearningFixture();
    final incomplete = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {...source.learning!.toJson(), 'coverageConfirmed': false},
    });
    final reviewed = await saveLesson(incomplete);
    final reopened = await MathTextbookCourseRepository(
      directoryProvider: () async => root,
    ).load(book);
    expect(reopened!.lessons.single.isApproved(book.pdfSha256), isTrue);
    expect(reopened.lessons.single.learning!.coverageConfirmed, isFalse);
    await expectLater(repository().start(reviewed.id), throwsStateError);
    await expectLater(
      repository().start(reviewed.id, planId: 'plan'),
      throwsStateError,
    );
  });

  test('未审核的大课时141组纸上题可启动和重开，旧内容不能续写', () async {
    final source = mathLearningFixture(
      manual: true,
      kind: MathTextbookPracticeKind.parentTask,
    );
    final exercise = source.learning!.exercises.single;
    final pending = MathTextbookLesson.fromJson({
      ...source.toJson(),
      'learning': {
        ...source.learning!.toJson(),
        'coverageConfirmed': false,
        'exercises': [
          for (var i = 0; i < 141; i++)
            {...exercise.toJson(), 'id': 'paper-$i', 'number': '${i + 1}'},
        ],
      },
    });
    final lesson = await saveLesson(pending, reviewed: false);
    final repo = repository();
    final started = await repo.start(lesson.id);
    final draft = started.copyWith(
      answers: [
        {'answer': '已在纸上画好5个圆'},
        ...started.answers.skip(1),
      ],
      elapsedSeconds: 17,
    );
    expect(draft.items, hasLength(141));
    await repo.saveDraft(draft);
    await reopenStorage();
    final reopened = repository();
    expect((await reopened.loadDraft(lesson.id))!.toJson(), draft.toJson());
    await saveLesson(lesson.edit(title: '原书范围已更新'), reviewed: false);
    await expectLater(reopened.saveDraft(draft), throwsStateError);
  });

  test('同一原题并发重复提交和重复结算只计一次，保存答案不能被修改', () async {
    final lesson = await saveLesson(mathLearningFixture());
    final repo = repository();
    final draft = (await repo.start(lesson.id)).copyWith(
      answers: [
        {'answer': '5'},
      ],
    );
    await repo.saveDraft(draft);
    final results = await Future.wait([
      repo.submit(draft, 0),
      repo.submit(draft, 0),
    ]);
    expect(results[0].toJson(), results[1].toJson());
    var progress = await repo.load();
    expect(progress.history, hasLength(1));
    expect(progress.targets.values.single.attempts, 1);
    expect(UserStatsRepository().get().mathTotalProblems, 1);
    expect(UserStatsRepository().get().mathTotalCorrect, 1);
    final committed = draft.copyWith(results: [MathTextbookResult.correct]);
    await repo.saveDraft(committed);
    await expectLater(
      repo.saveDraft(
        committed.copyWith(
          answers: [
            {'answer': '4'},
          ],
        ),
      ),
      throwsFormatException,
    );
    final finished = await complete(repo, committed);
    await repo.finish(finished);
    expect(HiveBoxes.mathSessions.length, 1);
    expect(HiveBoxes.learningActivities.length, 1);
    expect(UserStatsRepository().get().mathTotalProblems, 1);
    expect(UserStatsRepository().get().totalStars, 3);
    expect(HiveBoxes.checkIns.values.single.mathTotalCount, 1);
    expect(HiveBoxes.checkIns.values.single.mathCorrectCount, 1);
    expect(HiveBoxes.checkIns.values.single.durationSeconds, 30);
    progress = await repo.load();
    expect(progress.history.single.answers, {'answer': '5'});
    expect(await repo.loadDraft(lesson.id), isNull);
  });

  test('引擎错题和完整巩固历史经真实适配器重开后仍保留题目、规则、作答来源', () async {
    final lesson = await saveLesson(mathLearningFixture());
    var repo = repository();
    var draft = await repo.start(lesson.id, planId: 'plan');
    draft = await answer(repo, draft, '-999');
    draft = draft.copyWith(index: 1);
    await repo.saveDraft(draft);
    draft = await answer(
      repo,
      draft,
      draft.items[1].exercise.fields.single.rule.expected,
    );
    final finished = await complete(repo, draft);
    final sessionJson = HiveBoxes.mathSessions.values.single.problemsJson;
    final mistakeJson =
        HiveBoxes.mathMistakes.values.single.textbookSourcesJson;
    final progressJson = (await repo.load()).toJson();
    expect(HiveBoxes.mathSessions.values.single.totalProblems, 2);
    expect(HiveBoxes.mathSessions.values.single.correctCount, 1);
    expect(
      HiveBoxes.mathMistakes.values.single.textbookSources.single.bookId,
      book.pdfSha256,
    );
    expect(
      HiveBoxes.mathMistakes.values.single.textbookSources.single.answers,
      {'answer': '-999'},
    );
    await reopenStorage();
    repo = repository();
    expect(HiveBoxes.mathSessions.values.single.problemsJson, sessionJson);
    expect(
      HiveBoxes.mathMistakes.values.single.textbookSourcesJson,
      mistakeJson,
    );
    expect((await repo.load()).toJson(), progressJson);
    expect((await repo.load()).history.map((a) => a.sessionId).toSet(), {
      finished.sessionId,
    });
    expect(UserStatsRepository().get().mathTotalProblems, 2);
    expect(UserStatsRepository().get().mathTotalCorrect, 1);
  });

  test('纸上题只保存家长核对状态，授权撤销和重复核对不污染自动正确率', () async {
    final lesson = await saveLesson(
      mathLearningFixture(manual: true),
      reviewed: false,
    );
    final repo = repository();
    final draft = await answer(repo, await repo.start(lesson.id), '已在纸上画5个圆');
    await complete(repo, draft);
    var progress = await repo.load();
    final id = progress.history.single.id;
    expect(progress.history.single.result, MathTextbookResult.pendingParent);
    await expectLater(
      repo.parentCheck(
        attemptId: id,
        passed: true,
        reviewer: '妈妈',
        authorize: () => throw StateError('家长已锁定'),
      ),
      throwsStateError,
    );
    expect((await repo.load()).toJson(), progress.toJson());
    progress = await repo.parentCheck(
      attemptId: id,
      passed: true,
      reviewer: '妈妈',
      authorize: () {},
    );
    final repeated = await repo.parentCheck(
      attemptId: id,
      passed: true,
      reviewer: '妈妈',
      authorize: () {},
    );
    expect(repeated.toJson(), progress.toJson());
    expect(progress.targets.values.single.parentChecks, 1);
    expect(progress.targets.values.single.automaticCorrect, 0);
    expect(progress.history.single.result, MathTextbookResult.parentCorrect);
    expect(UserStatsRepository().get().mathTotalProblems, 0);
    expect(UserStatsRepository().get().mathTotalCorrect, 0);
    expect(UserStatsRepository().get().totalStars, 0);
    expect(HiveBoxes.mathSessions.values.single.totalProblems, 0);
  });

  test('未审核且覆盖未确认的纸上巩固可作答，结果等待家长核对', () async {
    final source = mathLearningFixture(
      manual: true,
      kind: MathTextbookPracticeKind.parentTask,
    );
    final lesson = await saveLesson(
      MathTextbookLesson.fromJson({
        ...source.toJson(),
        'learning': {...source.learning!.toJson(), 'coverageConfirmed': false},
      }),
      reviewed: false,
    );
    final repo = repository();
    final started = await repo.start(lesson.id, planId: 'plan');
    expect(started.items, hasLength(1));
    final answered = await answer(repo, started, '已在纸上完成合并数量的任务。');
    await complete(repo, answered);
    final progress = await repo.load();
    expect(progress.history.single.result, MathTextbookResult.pendingParent);
    expect(progress.history.single.planId, 'plan');
    expect(UserStatsRepository().get().mathTotalProblems, 0);
    expect(UserStatsRepository().get().mathTotalCorrect, 0);
    expect(UserStatsRepository().get().totalStars, 0);
    expect((await courses.load(book))!.lessons.single.review, isNull);
  });

  test('修改课程使旧练习不能继续写入，重新审核保留旧答案但不继承改变的目标', () async {
    final lesson = await saveLesson(mathLearningFixture());
    final repo = repository();
    final draft = await answer(repo, await repo.start(lesson.id), '5');
    final previous = await repo.load();
    final changed = lesson.edit(
      blocks: [
        lesson.blocks.first,
        MathTextbookBlock(
          id: 'exercise',
          kind: MathTextbookBlockKind.exercise,
          spans: [const MathTextbookSpan.text('3 + 2 = ?')],
          sources: lesson.blocks.last.sources,
        ),
      ],
    );
    final reviewed = await saveLesson(changed);
    await expectLater(repo.submit(draft, 0), throwsStateError);
    expect((await repo.load()).toJson(), previous.toJson());
    final current = mathTextbookLessonProgress(
      reviewed,
      book.pdfSha256,
      await repo.load(),
    );
    expect(current.ready, isTrue);
    expect(current.originalPassed, 0);
    expect(
      (await repo.load()).history.single.item.blocks.single.text,
      '2 + 3 = ?',
    );
  });

  test('中断后恢复完全相同的题目和草稿，新页面接管后旧页面不能覆盖', () async {
    final lesson = await saveLesson(mathLearningFixture());
    final first = repository();
    final draft = (await first.start(lesson.id, planId: 'plan')).copyWith(
      answers: [
        {'answer': '未完成输入'},
        {},
      ],
      elapsedSeconds: 12,
    );
    await first.saveDraft(draft);
    await reopenStorage();
    final restored = repository();
    expect(
      (await restored.loadDraft(lesson.id, planId: 'plan'))!.toJson(),
      draft.toJson(),
    );
    final second = repository();
    expect(
      (await second.loadDraft(lesson.id, planId: 'plan'))!.toJson(),
      draft.toJson(),
    );
    await expectLater(restored.saveDraft(draft), throwsStateError);
    expect(
      (await second.loadDraft(lesson.id, planId: 'plan'))!.toJson(),
      draft.toJson(),
    );
  });

  test('切走再切回同一档案和页面关闭都使旧仓储失效', () async {
    final lesson = await saveLesson(mathLearningFixture());
    var active = true;
    final repo = repository(active: () => active);
    final draft = await repo.start(lesson.id);
    ProfileScope.switchTo('another-child');
    await expectLater(repo.saveDraft(draft), throwsStateError);
    ProfileScope.reset();
    await expectLater(repo.saveDraft(draft), throwsStateError);
    final next = repository(active: () => active);
    final recovered = await next.loadDraft(lesson.id);
    expect(recovered!.sessionId, draft.sessionId);
    active = false;
    await expectLater(
      next.submit(
        recovered.copyWith(
          answers: [
            {'answer': '5'},
          ],
        ),
        0,
      ),
      throwsStateError,
    );
    expect(HiveBoxes.userStats.length, 0);
  });

  test('恢复屏障排空已进入的操作并阻止新提交，恢复后旧草稿不能继续写入', () async {
    final lesson = await saveLesson(mathLearningFixture());
    final repo = repository();
    final draft = await repo.start(lesson.id);
    final entered = Completer<void>(), release = Completer<void>();
    final held = courses.withCurrentCourse(book, (_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final saving = repo.saveDraft(draft);
    final savingResult = expectLater(saving, throwsStateError);
    final restored = PracticeDraftRepository.whileRestoring(() async {
      await PracticeDraftRepository.clearAll();
    });
    await expectLater(
      repo.submit(
        draft.copyWith(
          answers: [
            {'answer': '5'},
          ],
        ),
        0,
      ),
      throwsStateError,
    );
    release.complete();
    await held;
    await savingResult;
    await restored;
    await expectLater(repo.saveDraft(draft), throwsStateError);
    expect(await repository().loadDraft(lesson.id), isNull);
    expect(HiveBoxes.userStats.length, 0);
  });

  test('数学进度、错题和会话完整备份往返，旧备份保留数学数据且新空段显式清空', () async {
    final lesson = await saveLesson(mathLearningFixture());
    var repo = repository();
    var draft = await repo.start(lesson.id, planId: 'plan');
    draft = await answer(repo, draft, '-999');
    draft = draft.copyWith(index: 1);
    await repo.saveDraft(draft);
    draft = await answer(
      repo,
      draft,
      draft.items[1].exercise.fields.single.rule.expected,
    );
    await complete(repo, draft);
    final backup = BackupService();
    final exported = await backup.exportToJson(includeCredentials: false);
    final raw = jsonDecode(exported) as Map<String, dynamic>;
    final progress = (await repo.load()).toJson();
    final course = (await courses.load(book))!.toJson();
    final mistake = HiveBoxes.mathMistakes.values.single.textbookSourcesJson;
    final session = HiveBoxes.mathSessions.values.single.problemsJson;
    expect(raw['mathTextbookProgressVersion'], 1);
    expect(raw['textbookLearning'], {repo.key: jsonEncode(progress)});
    expect(
      raw['settings'].keys.where((String key) => key.startsWith('textbook_')),
      isEmpty,
    );
    await HiveBoxes.settings.delete(repo.key);
    await HiveBoxes.mathSessions.clear();
    await HiveBoxes.mathMistakes.clear();
    await backup.restoreFromJson(exported);
    repo = repository();
    expect((await repo.load()).toJson(), progress);
    expect(HiveBoxes.mathMistakes.values.single.textbookSourcesJson, mistake);
    expect(HiveBoxes.mathSessions.values.single.problemsJson, session);
    expect((await courses.load(book))!.toJson(), course);
    final legacy = Map<String, dynamic>.from(raw)
      ..remove('mathTextbookProgressVersion')
      ..['textbookLearning'] = <String, String>{};
    await backup.restoreFromJson(jsonEncode(legacy));
    repo = repository();
    expect((await repo.load()).toJson(), progress);
    await backup.restoreFromJson(
      jsonEncode({...raw, 'textbookLearning': <String, String>{}}),
    );
    expect((await repository().load()).history, isEmpty);
    expect((await courses.load(book))!.toJson(), course);
  });

  test('损坏或伪造判分的备份在预检拒绝，原进度与统计保持完整', () async {
    final lesson = await saveLesson(mathLearningFixture());
    final repo = repository();
    await answer(repo, await repo.start(lesson.id), '5');
    final backup = BackupService();
    final raw = jsonDecode(
      await backup.exportToJson(includeCredentials: false),
    ) as Map<String, dynamic>;
    final progress = (await repo.load()).toJson();
    final corrupted = jsonDecode(jsonEncode(progress)) as Map<String, dynamic>;
    corrupted['history'][0]['answers']['answer'] = '4';
    final invalid = {
      ...raw,
      'textbookLearning': {repo.key: jsonEncode(corrupted)},
    };
    await expectLater(
      backup.restoreFromJson(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect((await repo.load()).toJson(), progress);
    expect(UserStatsRepository().get().mathTotalCorrect, 1);
    final wrongKey = {
      ...raw,
      'textbookLearning': {
        '${MathTextbookProgress.prefix}${'b' * 64}': jsonEncode(progress),
      },
    };
    expect(
      () => backup.inspectJson(jsonEncode(wrongKey)),
      throwsFormatException,
    );
  });

  test('缓存或PDF移除保留学习，整书清理覆盖各档案草稿与进度并保留已结算历史', () async {
    final lesson = await saveLesson(mathLearningFixture());
    var repo = repository();
    final draft = await answer(repo, await repo.start(lesson.id), '5');
    await complete(repo, draft);
    await repo.start(lesson.id);
    final firstKey = repo.key;
    ProfileScope.switchTo('another-child');
    repo = repository();
    await repo.markRead(lesson.id, lesson.contentDigest(book.pdfSha256));
    await repo.start(lesson.id, planId: 'plan');
    final secondKey = repo.key;
    final files = TextbookFileService(directoryProvider: () async => root);
    await files.clearDerived(book);
    await files.removePdf(book.pdfSha256);
    expect(HiveBoxes.settings.containsKey(firstKey), isTrue);
    expect(HiveBoxes.settings.containsKey(secondKey), isTrue);
    expect((await courses.load(book))!.lessons, hasLength(1));
    expect(PracticeDraftRepository().scopes('mathTextbook'), hasLength(1));
    courses.invalidate(book.pdfSha256);
    await courses.clear(book);
    final removed = await TextbookProgressCleanup(
      box: HiveBoxes.settings,
      metaBox: HiveBoxes.meta,
    ).deleteBookProgress(book.pdfSha256);
    expect(removed, 4);
    expect(HiveBoxes.settings.containsKey(firstKey), isFalse);
    expect(HiveBoxes.settings.containsKey(secondKey), isFalse);
    expect(PracticeDraftRepository().scopes('mathTextbook'), isEmpty);
    ProfileScope.reset();
    expect(PracticeDraftRepository().scopes('mathTextbook'), isEmpty);
    expect(HiveBoxes.mathSessions.length, 1);
    expect(HiveBoxes.learningActivities.length, 1);
    expect(UserStatsRepository().get().mathTotalProblems, 1);
    await expectLater(
      repo.start(lesson.id),
      throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
    );
  });
}
