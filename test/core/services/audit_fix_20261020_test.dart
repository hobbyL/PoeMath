import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

import '../../helpers/hive_test_helper.dart';

class _FailingMeta extends Fake implements Box<dynamic> {
  _FailingMeta(this.real);
  final Box<dynamic> real;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      real.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) =>
      Future.error(StateError('marker write failed'));
}

class _FailingStats extends Fake implements Box<UserStats> {
  _FailingStats(this.real);
  final Box<UserStats> real;
  @override
  UserStats? get(dynamic key, {UserStats? defaultValue}) =>
      real.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, UserStats value) =>
      Future.error(StateError('business write failed'));
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('四类业务记录在 meta 写入失败后重试均只结算一次', () async {
    final problem = LlmProblem(
      id: 'p',
      profileId: 'default',
      questionText: '1 + 1',
      unit: '个',
      operands: [1, 1],
      operators: ['+'],
      answer: 2,
      explanation: '相加',
      batchId: 'b',
      createdAt: DateTime(2026, 10, 20),
      grade: 1,
      semester: '上',
      topic: '生活',
      difficulty: 1,
    );
    await LlmProblemRepository().addAll([problem]);
    final actions = <Future<void> Function()>[
      () => CheckInRepository()
          .updateToday(activityId: 'daily', addMathTotal: 10),
      () => UserStatsRepository().addStars(3, activityId: 'stars'),
      () => MathMistakeRepository().recordWrong(
          problemText: '1+1=?',
          correctAnswer: '2',
          userAnswer: '3',
          problemType: 'arithmetic',
          grade: 1,
          activityId: 'wrong',),
      () => LlmProblemRepository()
          .recordAttempt('p', correct: true, activityId: 'attempt'),
    ];
    final original = HiveBoxes.meta;
    HiveBoxes.meta = _FailingMeta(original);
    try {
      for (final action in actions) {
        await expectLater(action(), throwsStateError);
        await action();
      }
    } finally {
      HiveBoxes.meta = original;
    }
    expect(CheckInRepository().getToday()!.mathTotalCount, 10);
    expect(UserStatsRepository().get().totalStars, 3);
    expect(MathMistakeRepository().getAll().single.wrongCount, 1);
    expect(LlmProblemRepository().getById('p')!.attempts, 1);
    // Force adapter round trips, then replay again with no meta completion marks.
    await HiveBoxes.close();
    await HiveBoxes.init();
    for (final action in actions) {
      await action();
    }
    expect(CheckInRepository().getToday()!.mathTotalCount, 10);
    expect(UserStatsRepository().get().totalStars, 3);
    expect(MathMistakeRepository().getAll().single.wrongCount, 1);
    expect(LlmProblemRepository().getById('p')!.attempts, 1);
  });

  test('业务写入失败不污染原对象或提前记录结算', () async {
    final repo = UserStatsRepository();
    await repo.addStars(4);
    final old = repo.get();
    final real = HiveBoxes.userStats;
    HiveBoxes.userStats = _FailingStats(real);
    try {
      await expectLater(
          repo.settleMathChallenge(
              activityId: 'challenge',
              problems: 5,
              correct: 3,
              bestStreak: 2,
              stars: 6,),
          throwsStateError,);
      expect(old.totalStars, 4);
      expect(old.mathTotalProblems, 0);
      expect(old.appliedActivityIds, isEmpty);
    } finally {
      HiveBoxes.userStats = real;
    }
    await repo.settleMathChallenge(
        activityId: 'challenge',
        problems: 5,
        correct: 3,
        bestStreak: 2,
        stars: 6,);
    expect(repo.get().totalStars, 10);
    expect(repo.get().mathTotalProblems, 5);
  });

  test('不同活动与普通更新并发时不丢统计及幂等事实', () async {
    final repo = UserStatsRepository();
    await Future.wait([
      repo.addStars(3, activityId: 'one'),
      repo.addStars(4, activityId: 'two'),
      repo.addMathResults(problems: 5, correct: 3),
      repo.updateStreak(2),
    ]);
    expect(repo.get().totalStars, 7);
    expect(repo.get().mathTotalProblems, 5);
    expect(repo.get().currentStreak, 2);
    expect(repo.get().appliedActivityIds, containsAll(['one', 'two']));
  });

  test('冻结完成日跨日重试不写入重试日，备份保留结算事实', () async {
    final date = DateTime(2026, 10, 19, 23, 59);
    final repo = CheckInRepository();
    await repo.updateForDate(date, activityId: 'yesterday', addMathTotal: 10);
    final backup = BackupService();
    final json = await backup.exportToJson();
    expect((jsonDecode(json) as Map)['checkIns'].single['appliedActivityIds'],
        ['yesterday'],);
    await backup.restoreFromJson(json);
    await repo.updateForDate(date, activityId: 'yesterday', addMathTotal: 10);
    expect(repo.getByDate(date)!.mathTotalCount, 10);
    expect(repo.getByDate(DateTime(2026, 10, 20)), isNull);
  });

  test('同日未完成 3 题加已完成 10 题日报始终为 13 题', () async {
    final now = DateTime(2026, 10, 20, 12);
    await HiveBoxes.mathSessions.put(
        'default_partial',
        MathSession(
            id: 'partial',
            profileId: 'default',
            grade: 1,
            problemType: 'mixed',
            totalProblems: 3,
            correctCount: 2,
            durationSeconds: 20,
            startedAt: now,
            finishedAt: now,
            isComplete: false,),);
    expect(buildDailyStats(days: 1, now: now).single.mathTotal, 3);
    await CheckInRepository().updateForDate(now,
        activityId: 'complete',
        addMathTotal: 10,
        addMathCorrect: 8,
        addDuration: 60,);
    final report = buildDailyStats(days: 1, now: now).single;
    expect(report.mathTotal, 13);
    expect(report.mathCorrect, 10);
    expect(report.durationSeconds, 80);
  });
}
