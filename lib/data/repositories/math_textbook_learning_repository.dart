import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/models/math_textbook_session_context.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/activity_settlement_ledger.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/domain/math_textbook_grading.dart';
import 'package:poemath/domain/math_textbook_practice.dart';

/// 课程锁、档案代次和恢复屏障覆盖一次学习写入及其跨 box 结算。
class MathTextbookLearningRepository {
  MathTextbookLearningRepository({
    required this.book,
    required this.courses,
    this.findBook,
    this.isActive,
    Box<dynamic>? box,
    DateTime Function()? clock,
    this.recordStatistics = true,
  }) : profileId = ProfileScope.currentId,
       _profileRevision = ProfileScope.revision,
       _generation = courses.generation(book.pdfSha256),
       _box = box ?? HiveBoxes.settings,
       _clock = clock ?? DateTime.now;

  final Textbook book;
  final MathTextbookCourseRepository courses;
  final Textbook? Function(String id)? findBook;
  final bool Function()? isActive;
  final String profileId;
  final int _profileRevision, _generation;
  final Box<dynamic> _box;
  final DateTime Function() _clock;
  final bool recordStatistics;
  final drafts = PracticeDraftRepository();
  final _validatedSessions = <String, String>{};
  final _finishedSessions = <String, ({String digest, MathSession session})>{};
  static final _tails = <String, Future<void>>{};
  static const draftKind = 'mathTextbook';
  static final _ids = Random.secure();
  static String _newId() => base64Url
      .encode(List.generate(18, (_) => _ids.nextInt(256)))
      .replaceAll('=', '');

  String get key => MathTextbookProgress.keyFor(
    profileId,
    book.pdfSha256,
    book.learningEditionId,
  );

  void _current() {
    drafts.assertCurrent();
    courses.checkGeneration(book.pdfSha256, _generation);
    if (isActive?.call() == false) throw StateError('练习页面已关闭，迟到的操作不会继续写入');
    if (ProfileScope.currentId != profileId ||
        ProfileScope.revision != _profileRevision) {
      throw StateError('孩子档案已切换，请重新打开本课');
    }
    final current = findBook?.call(book.pdfSha256);
    if (book.subject != TextbookSubject.math ||
        findBook != null &&
            (current == null ||
                current.subject != TextbookSubject.math ||
                current.learningEditionId != book.learningEditionId)) {
      throw StateError('数学教材已移除或版本已变化，请重新打开');
    }
  }

  Future<T> _serial<T>(Future<T> Function(MathTextbookCourse? course) action) =>
      drafts.guard(
        () => ActivitySettlementLedger.withGuard(_current, () async {
          final previous = _tails[key];
          final work = () async {
            if (previous != null) await previous;
            _current();
            return courses.withCurrentCourse(book, (course) async {
              _current();
              final result = await action(course);
              _current();
              return result;
            });
          }();
          final tail = work.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          );
          _tails[key] = tail;
          try {
            return await work;
          } finally {
            if (identical(_tails[key], tail)) _tails.remove(key);
          }
        }),
      );

  MathTextbookProgress _read() {
    final raw = _box.get(key);
    if (raw != null &&
        (raw is! String ||
            utf8.encode(raw).length > MathTextbookProgress.maxBytes)) {
      throw const FormatException('数学学习记录超过容量或格式无效');
    }
    final progress = raw == null
        ? MathTextbookProgress(
            profileId: profileId,
            bookId: book.pdfSha256,
            editionId: book.learningEditionId,
          )
        : MathTextbookProgress.fromJson(jsonDecode(raw as String));
    if (progress.key != key ||
        progress.profileId != profileId ||
        progress.bookId != book.pdfSha256 ||
        progress.editionId != book.learningEditionId) {
      throw const FormatException('数学学习记录与本书或孩子档案不匹配');
    }
    return progress;
  }

  Future<MathTextbookProgress> load() => _serial((_) async => _read());

  Future<MathTextbookProgress> _write(MathTextbookProgress progress) async {
    var bounded = progress.copyWith(
      history: progress.history.take(MathTextbookProgress.maxHistory).toList(),
      operations: progress.operations.reversed
          .take(1000)
          .toList()
          .reversed
          .toList(),
    );
    var encoded = jsonEncode(bounded.toJson());
    while (utf8.encode(encoded).length > MathTextbookProgress.maxBytes &&
        bounded.history.length > 1) {
      bounded = bounded.copyWith(
        history: bounded.history.take(bounded.history.length - 1).toList(),
      );
      encoded = jsonEncode(bounded.toJson());
    }
    if (utf8.encode(encoded).length > MathTextbookProgress.maxBytes) {
      throw const FormatException('本书学习记录已达到容量上限，作答仍保留在本机练习草稿中');
    }
    MathTextbookProgress.fromJson(jsonDecode(encoded));
    _current();
    await _box.put(key, encoded);
    return bounded;
  }

  MathTextbookLesson _lesson(
    MathTextbookCourse? course,
    String id, {
    String? digest,
    bool requireLearning = true,
    String? planId,
    Set<String>? exerciseIds,
  }) {
    final lesson = course?.lessons.where((l) => l.id == id).firstOrNull;
    if (lesson == null ||
        digest != null && lesson.contentDigest(book.pdfSha256) != digest) {
      throw StateError('本课内容已更新，旧记录已保留，请重新打开本课');
    }
    if (requireLearning) {
      _practiceAccess(lesson, planId: planId, exerciseIds: exerciseIds);
    }
    return lesson;
  }

  MathTextbookPracticeAvailability _practiceAccess(
    MathTextbookLesson lesson, {
    String? planId,
    Set<String>? exerciseIds,
  }) {
    if (lesson.learning == null) throw StateError('家长还没有补齐本课知识点、题目和巩固计划');
    final access = mathTextbookPracticeAvailability(lesson, book.pdfSha256);
    final selected = exerciseIds ?? access.exerciseIds;
    final allowed = planId != null
        ? access.planIds.contains(planId)
        : selected.isNotEmpty && selected.every(access.exerciseIds.contains);
    if (!allowed) {
      throw StateError('本题自动练习的答案或范围尚未核对，可以先阅读本课内容或做纸上练习');
    }
    return access;
  }

  Future<MathTextbookProgress> markRead(String lessonId, String digest) =>
      _serial((course) async {
        final lesson = _lesson(
          course,
          lessonId,
          digest: digest,
          requireLearning: false,
        );
        final progress = _read(), reading = mathTextbookReadingDigest(lesson);
        if (progress.readLessons[lessonId] == reading) return progress;
        return _write(
          progress.copyWith(
            revision: progress.revision + 1,
            readLessons: {...progress.readLessons, lessonId: reading},
          ),
        );
      });

  String scopeFor(String lessonId, String? planId) =>
      jsonEncode([book.pdfSha256, lessonId, planId]);

  Future<MathTextbookPracticeDraft?> loadDraft(
    String lessonId, {
    String? planId,
  }) => _serial((course) async {
    final scope = scopeFor(lessonId, planId);
    drafts.claim(draftKind, scope: scope);
    final raw = drafts.get(draftKind, scope: scope);
    if (raw == null) return null;
    final draft = MathTextbookPracticeDraft.fromJson(raw);
    _validateDraft(course, draft);
    return draft;
  });

  Future<MathTextbookPracticeDraft> start(
    String lessonId, {
    String? planId,
    Set<String>? exerciseIds,
  }) => _serial((course) async {
    final lesson = _lesson(course, lessonId, requireLearning: false);
    final access = _practiceAccess(
      lesson,
      planId: planId,
      exerciseIds: exerciseIds,
    );
    final plan = planId == null
        ? null
        : lesson.learning!.practicePlans
              .where((p) => p.id == planId)
              .firstOrNull;
    if (planId != null && plan == null) throw StateError('本课巩固计划已更新');
    final seed = plan == null ? null : Random.secure().nextInt(2147483647);
    final items = plan == null
        ? originalMathTextbookItems(lesson)
              .where(
                (item) => (exerciseIds ?? access.exerciseIds).contains(
                  item.exercise.id,
                ),
              )
              .toList()
        : generateMathTextbookPractice(
            lesson: lesson,
            plan: plan,
            grade: book.grade,
            semester: book.semester,
            random: Random(seed!),
          );
    if (items.isEmpty) throw StateError('本课没有可练习的题目');
    final draft = MathTextbookPracticeDraft(
      sessionId: _newId(),
      profileId: profileId,
      bookId: book.pdfSha256,
      editionId: book.learningEditionId,
      lessonId: lessonId,
      lessonDigest: lesson.contentDigest(book.pdfSha256),
      planId: planId,
      planDigest: plan?.digest,
      seed: seed,
      items: items,
      operationIds: List.generate(items.length, (_) => _newId()),
      startedAt: _clock(),
    );
    drafts.claim(draftKind, scope: draft.scope);
    _validateDraft(course, draft, newSession: true);
    await drafts.save(draftKind, draft.toJson(), scope: draft.scope);
    return draft;
  });

  MathTextbookLesson _validateDraft(
    MathTextbookCourse? course,
    MathTextbookPracticeDraft draft, {
    bool newSession = false,
  }) {
    if (utf8.encode(jsonEncode(draft.toJson())).length >
        MathTextbookProgress.maxBytes) {
      throw const FormatException('本次练习草稿超过容量，请家长拆分题组');
    }
    MathTextbookPracticeDraft.fromJson(draft.toJson());
    drafts.assertOwner(draftKind, scope: draft.scope);
    if (draft.profileId != profileId ||
        draft.bookId != book.pdfSha256 ||
        draft.editionId != book.learningEditionId) {
      throw StateError('本机草稿属于其他孩子或教材版本');
    }
    if (!newSession) {
      final stored = drafts.get(draftKind, scope: draft.scope);
      if (stored == null) throw StateError('本次练习已结束或已替换，请重新打开');
      final previous = MathTextbookPracticeDraft.fromJson(stored);
      if (previous.fingerprint != draft.fingerprint ||
          draft.elapsedSeconds < previous.elapsedSeconds ||
          previous.finishedAt != null &&
              draft.finishedAt?.millisecondsSinceEpoch !=
                  previous.finishedAt!.millisecondsSinceEpoch ||
          draft.index < previous.index ||
          draft.index > previous.index + 1) {
        throw StateError('本次练习的题目、提交标识或冻结范围已变化');
      }
      for (var i = 0; i < previous.items.length; i++) {
        if (previous.results[i] != null &&
            (previous.results[i] != draft.results[i] ||
                textbookContentDigest(previous.answers[i]) !=
                    textbookContentDigest(draft.answers[i]))) {
          throw StateError('已提交的作答不能修改，请重新练习');
        }
      }
    }
    final lesson = _lesson(
      course,
      draft.lessonId,
      digest: draft.lessonDigest,
      planId: draft.planId,
      exerciseIds: draft.items.map((item) => item.exercise.id).toSet(),
    );
    final snapshotDigest = textbookContentDigest({
      'lesson': draft.lessonDigest,
      'plan': draft.planDigest,
      'seed': draft.seed,
      'items': draft.items.map((i) => i.toJson()).toList(),
    });
    if (_validatedSessions[draft.sessionId] == snapshotDigest) return lesson;
    final plan = draft.planId == null
        ? null
        : lesson.learning!.practicePlans
              .where((p) => p.id == draft.planId)
              .firstOrNull;
    if (draft.planId != null &&
        (plan == null ||
            plan.digest != draft.planDigest ||
            draft.seed == null)) {
      throw StateError('巩固范围已更新，请重新开始；已有作答保留');
    }
    final expected = plan == null
        ? originalMathTextbookItems(lesson)
        : generateMathTextbookPractice(
            lesson: lesson,
            plan: plan,
            grade: book.grade,
            semester: book.semester,
            random: Random(draft.seed!),
          );
    if (draft.items.map((i) => i.exercise.id).toSet().length !=
            draft.items.length ||
        plan != null && draft.items.length != expected.length ||
        draft.items.any(
          (item) => !expected.any(
            (value) => jsonEncode(value.toJson()) == jsonEncode(item.toJson()),
          ),
        )) {
      throw const FormatException('练习题目或答案规则与已审核课程不一致');
    }
    _validatedSessions[draft.sessionId] = snapshotDigest;
    return lesson;
  }

  Future<void> saveDraft(MathTextbookPracticeDraft draft) =>
      _serial((course) async {
        MathTextbookPracticeDraft.fromJson(draft.toJson());
        _validateDraft(course, draft);
        await drafts.save(draftKind, draft.toJson(), scope: draft.scope);
      });

  Future<MathTextbookAttempt> submit(
    MathTextbookPracticeDraft draft,
    int index,
  ) => _serial((course) async {
    final lesson = _validateDraft(course, draft);
    if (index < 0 || index >= draft.items.length || index != draft.index) {
      throw RangeError.index(index, draft.items);
    }
    final item = draft.items[index], answers = draft.answers[index];
    if (!mathTextbookAnswersComplete(item.exercise, answers)) {
      throw const FormatException('请填写本题全部答案；在纸上完成的题也请记下完成情况');
    }
    final evaluation = gradeMathTextbookExercise(item.exercise, answers);
    final attempt = MathTextbookAttempt.fromJson(
      MathTextbookAttempt(
        id: draft.operationIds[index],
        sessionId: draft.sessionId,
        lessonId: lesson.id,
        lessonTitle: lesson.title,
        lessonDigest: draft.lessonDigest,
        scopeDigest: mathTextbookTargetDigest(
          lesson,
          draft.planId,
          item.exercise.id,
        ),
        planId: draft.planId,
        item: item,
        answers: answers,
        fieldResults: evaluation.fields,
        result: evaluation.result,
        createdAt: _clock(),
      ).toJson(),
    );
    final progress = _read();
    final existing = progress.history
        .where((a) => a.id == attempt.id)
        .firstOrNull;
    if (existing != null &&
        (existing.sessionId != attempt.sessionId ||
            existing.scopeDigest != attempt.scopeDigest ||
            textbookContentDigest(existing.answers) !=
                textbookContentDigest(attempt.answers))) {
      throw StateError('本题已经提交；重新练习会建立新的作答记录');
    }
    final automatic = !item.exercise.needsParent;
    if (!progress.operations.contains(attempt.id)) {
      final old = progress.targets[attempt.targetKey];
      await _write(
        progress.copyWith(
          revision: progress.revision + 1,
          history: [attempt, ...progress.history],
          operations: [...progress.operations, attempt.id],
          targets: {
            ...progress.targets,
            attempt.targetKey: MathTextbookTargetRecord(
              scopeDigest: attempt.scopeDigest,
              sessionId: draft.sessionId,
              attemptId: attempt.id,
              result: attempt.result,
              attempts: (old?.attempts ?? 0) + 1,
              automaticCorrect:
                  (old?.automaticCorrect ?? 0) +
                  (automatic && attempt.result == MathTextbookResult.correct
                      ? 1
                      : 0),
              automaticIncorrect:
                  (old?.automaticIncorrect ?? 0) +
                  (automatic && attempt.result == MathTextbookResult.incorrect
                      ? 1
                      : 0),
              parentChecks: old?.parentChecks ?? 0,
            ),
          },
        ),
      );
    }
    _current();
    // 保存记录后统计可重试，稳定操作 ID 避免部分写入重复计数。
    if (recordStatistics && automatic) {
      await _recordAutomatic(
        draft,
        index,
        evaluation.result == MathTextbookResult.correct,
      );
    }
    return existing ?? attempt;
  });

  MathTextbookSessionContext _context(
    MathTextbookPracticeDraft draft,
    int index,
  ) => MathTextbookSessionContext.fromJson(
    MathTextbookSessionContext(
      bookId: book.pdfSha256,
      bookTitle: book.title,
      editionId: book.learningEditionId,
      lessonId: draft.lessonId,
      lessonDigest: draft.lessonDigest,
      planId: draft.planId,
      item: draft.items[index],
      answers: draft.answers[index],
    ).toJson(),
  );

  Future<void> _recordAutomatic(
    MathTextbookPracticeDraft draft,
    int index,
    bool correct,
  ) async {
    var streak = 0, best = 0;
    for (var i = 0; i <= index; i++) {
      final passed = i == index
          ? correct
          : draft.results[i] == MathTextbookResult.correct;
      streak = passed && !draft.items[i].exercise.needsParent ? streak + 1 : 0;
      best = max(best, streak);
    }
    _current();
    await UserStatsRepository().recordMathAttempt(
      isCorrect: correct,
      bestStreak: best,
      activityId: 'math_textbook_attempt:${draft.operationIds[index]}',
    );
    final problem = draft.items[index].problem;
    if (!correct && problem != null) {
      _current();
      final source = _context(draft, index);
      final answer = source.answers.values.single;
      final judgement = MathEngine.judge(problem, answer);
      await MathMistakeRepository().recordWrong(
        problemText: problem.problemText,
        correctAnswer: problem.answerText,
        userAnswer: answer,
        problemType: problem.mode.name,
        grade: problem.grade,
        semester: problem.semester,
        skillId: problem.skillId,
        problemJson: jsonEncode(problem.toJson()),
        errorType: judgement.diagnosis?.category,
        solutionStepsJson: judgement.correctSteps.isEmpty
            ? null
            : judgement.correctSteps
                  .map(
                    (step) =>
                        '${step.description}|||${step.expression}|||${step.resultHint}',
                  )
                  .join('\n'),
        activityId: 'math_textbook_mistake:${draft.operationIds[index]}',
        textbookSource: source,
      );
    }
  }

  Future<MathTextbookProgress> parentCheck({
    required String attemptId,
    required bool passed,
    required String reviewer,
    required void Function() authorize,
  }) => _serial((course) async {
    authorize();
    final progress = _read(),
        previous = progress.history.where((a) => a.id == attemptId).firstOrNull;
    if (previous == null || !previous.item.exercise.needsParent) {
      throw StateError('这份作答没有待核对的开放项');
    }
    final lesson = _lesson(
      course,
      previous.lessonId,
      planId: previous.planId,
      exerciseIds: {previous.item.exercise.id},
    );
    if (mathTextbookTargetDigest(
          lesson,
          previous.planId,
          previous.item.exercise.id,
        ) !=
        previous.scopeDigest) {
      throw StateError('原题或规则已更新，请使用新课程重新练习，历史作答仍保留');
    }
    if (passed && previous.fieldResults.values.any((v) => v == false)) {
      throw StateError('还有自动核对未通过的作答项，请孩子改正后重新练习');
    }
    if (reviewer.trim().isEmpty) throw const FormatException('请填写核对人');
    final target = progress.targets[previous.targetKey];
    if (target?.attemptId != attemptId) throw StateError('孩子已有新的作答，请核对最新记录');
    final checked = MathTextbookAttempt.fromJson(
      previous
          .checked(passed: passed, reviewer: reviewer.trim(), at: _clock())
          .toJson(),
    );
    if (previous.result == checked.result) return progress;
    authorize();
    return _write(
      progress.copyWith(
        revision: progress.revision + 1,
        history: progress.history
            .map((a) => a.id == attemptId ? checked : a)
            .toList(),
        targets: {
          ...progress.targets,
          previous.targetKey: MathTextbookTargetRecord(
            scopeDigest: target!.scopeDigest,
            sessionId: target.sessionId,
            attemptId: target.attemptId,
            result: checked.result,
            attempts: target.attempts,
            automaticCorrect: target.automaticCorrect,
            automaticIncorrect: target.automaticIncorrect,
            parentChecks: target.parentChecks + 1,
          ),
        },
      ),
    );
  });

  Future<MathSession> finish(MathTextbookPracticeDraft draft) =>
      _serial((course) async {
        final finished = _finishedSessions[draft.sessionId];
        if (finished != null) {
          if (finished.digest != textbookContentDigest(draft.toJson())) {
            throw StateError('本次练习已经结算，不能修改结果');
          }
          return finished.session;
        }
        _validateDraft(course, draft);
        if (draft.results.any((r) => r == null) || draft.finishedAt == null) {
          throw StateError('请先完成本次题目');
        }
        final progress = _read();
        if (draft.operationIds.any((id) => !progress.operations.contains(id))) {
          throw StateError('还有作答没有保存，请重试核对');
        }
        final records = <ProblemRecord>[];
        for (var i = 0; i < draft.items.length; i++) {
          final item = draft.items[i];
          if (item.exercise.needsParent) continue;
          final saved = progress.history
              .where((attempt) => attempt.id == draft.operationIds[i])
              .firstOrNull;
          if (saved != null &&
              (saved.sessionId != draft.sessionId ||
                  textbookContentDigest(saved.answers) !=
                      textbookContentDigest(draft.answers[i]))) {
            throw StateError('已保存作答与本次结算不一致');
          }
          if (recordStatistics) {
            await _recordAutomatic(
              draft,
              i,
              draft.results[i] == MathTextbookResult.correct,
            );
          }
          records.add(
            ProblemRecord(
              problemText: item.blocks.map((b) => b.text).join('\n'),
              answerText: item.exercise.fields
                  .map(
                    (f) => f.rule.kind == MathTextbookAnswerKind.choice
                        ? f.rule.correctChoices.join('、')
                        : '${f.rule.expected}${f.rule.unit}',
                  )
                  .join('；'),
              userAnswer: item.exercise.fields
                  .map((f) => draft.answers[i][f.id] ?? '')
                  .join('；'),
              isCorrect: draft.results[i] == MathTextbookResult.correct,
              skillId: item.problem?.skillId,
              problem: item.problem?.toJson(),
              textbookContext: _context(draft, i).toJson(),
            ),
          );
        }
        final correct = records.where((r) => r.isCorrect).length;
        final stars = LearningRewardCalculator.calculateStars(
          activityType: LearningActivityType.mathPractice,
          totalItems: records.length,
          successfulItems: correct,
        );
        final session = MathSession(
          id: draft.sessionId,
          profileId: profileId,
          grade: book.grade,
          semester: book.semester,
          problemType: 'textbook',
          totalProblems: records.length,
          correctCount: correct,
          durationSeconds: draft.elapsedSeconds,
          starsEarned: stars,
          startedAt: draft.startedAt,
          finishedAt: draft.finishedAt,
          problemsJson: jsonEncode(records.map((r) => r.toJson()).toList()),
        );
        if (recordStatistics) {
          final activityId = 'math_textbook:${session.id}';
          _current();
          await MathSessionRepository().save(session);
          _current();
          await LearningActivityRepository().record(
            id: activityId,
            activityType: LearningActivityType.mathPractice,
            totalItems: records.length,
            successfulItems: correct,
            starsEarned: stars,
            durationSeconds: draft.elapsedSeconds,
            completedAt: draft.finishedAt!,
          );
          _current();
          await UserStatsRepository().addStars(stars, activityId: activityId);
          _current();
          await CheckInRepository().updateForDate(
            draft.finishedAt!,
            activityId: activityId,
            addMathTotal: records.length,
            addMathCorrect: correct,
            addStars: stars,
            addDuration: draft.elapsedSeconds,
          );
        }
        _current();
        await drafts.remove(
          draftKind,
          scope: draft.scope,
          sessionId: draft.sessionId,
        );
        _finishedSessions[draft.sessionId] = (
          digest: textbookContentDigest(draft.toJson()),
          session: session,
        );
        return session;
      });
}
