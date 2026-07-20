import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/features/profile/providers/stats_chart_providers.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('新版每日聚合保留跨日诗词记录且不与历史明细重复累计', () async {
    final now = DateTime(2026, 7, 20, 12);
    final yesterday = now.subtract(const Duration(days: 1));

    await _putSummary(
      yesterday,
      poemCount: 1,
      mathTotal: 8,
      mathCorrect: 6,
      stars: 4,
      duration: 90,
    );
    await _putSummary(
      now,
      poemCount: 2,
      mathTotal: 10,
      mathCorrect: 9,
      stars: 7,
      duration: 120,
    );

    // 同日明细仍存在，但新版聚合是该日唯一统计来源。
    await HiveBoxes.mathSessions.put(
      'default_duplicate',
      MathSession(
        id: 'duplicate',
        profileId: 'default',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 99,
        correctCount: 99,
        starsEarned: 3,
        durationSeconds: 999,
        startedAt: yesterday,
        finishedAt: yesterday,
      ),
    );
    await HiveBoxes.poemProgress.put(
      'default_same_poem',
      PoemProgress(
        poemId: 'same_poem',
        profileId: 'default',
        status: LearningStatus.learning,
        lastStudiedAt: now,
      ),
    );
    await HiveBoxes.checkIns.put(
      'kid2_${_dateKey(now)}',
      CheckIn(
        profileId: 'kid2',
        date: _dateKey(now),
        poemCount: 999,
        activitySources: CheckIn.poemActivitySource,
      ),
    );

    final stats = buildDailyStats(days: 2, now: now);

    expect(stats[0].poemCount, 1);
    expect(stats[0].mathTotal, 8);
    expect(stats[0].mathCorrect, 6);
    expect(stats[0].starsEarned, 4);
    expect(stats[0].durationSeconds, 90);
    expect(stats[1].poemCount, 2);
    expect(stats[1].mathTotal, 10);
  });

  test('旧版日期从诗词、普通口算和挑战明细回退聚合', () async {
    final now = DateTime(2026, 7, 20, 12);
    final date = now.subtract(const Duration(days: 1));

    await HiveBoxes.poemProgress.put(
      'default_poem',
      PoemProgress(
        poemId: 'poem',
        profileId: 'default',
        status: LearningStatus.learning,
        lastStudiedAt: date,
      ),
    );
    await HiveBoxes.mathSessions.put(
      'default_session',
      MathSession(
        id: 'session',
        profileId: 'default',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 7,
        correctCount: 5,
        starsEarned: 2,
        durationSeconds: 60,
        startedAt: date,
        finishedAt: date,
      ),
    );
    await HiveBoxes.challengeRecords.put(
      'default_challenge',
      ChallengeRecord(
        id: 'challenge',
        profileId: 'default',
        mode: 'fixed',
        score: 20,
        totalAnswered: 3,
        correctCount: 2,
        bestCombo: 2,
        grade: 1,
        semester: '上',
        difficulty: 'medium',
        durationSeconds: 30,
        starsEarned: 2,
        createdAt: date,
      ),
    );
    await HiveBoxes.mathMistakes.put(
      'default_mistake',
      MathMistake(
        id: 'mistake',
        profileId: 'default',
        problemText: '1 + 1 = ?',
        correctAnswer: '2',
        userAnswer: '3',
        problemType: 'arithmetic',
        grade: 1,
        createdAt: date,
      ),
    );
    await HiveBoxes.mathMistakes.put(
      'kid2_mistake',
      MathMistake(
        id: 'mistake',
        profileId: 'kid2',
        problemText: '1 + 1 = ?',
        correctAnswer: '2',
        userAnswer: '3',
        problemType: 'arithmetic',
        grade: 1,
        createdAt: date,
      ),
    );

    final stat = buildDailyStats(days: 2, now: now).first;

    expect(stat.poemCount, 1);
    expect(stat.mathTotal, 10);
    expect(stat.mathCorrect, 7);
    expect(stat.starsEarned, 4);
    expect(stat.durationSeconds, 90);
    expect(stat.mistakeCount, 1);
  });

  test('仅诗词已迁移时仍合并同日旧版口算明细', () async {
    final now = DateTime(2026, 7, 20, 12);
    final dateKey = _dateKey(now);
    await HiveBoxes.checkIns.put(
      'default_$dateKey',
      CheckIn(
        profileId: 'default',
        date: dateKey,
        poemCount: 1,
        starsEarned: 4,
        durationSeconds: 30,
        isCheckedIn: false,
        activitySources: CheckIn.poemActivitySource,
      ),
    );
    await HiveBoxes.mathSessions.put(
      'default_session',
      MathSession(
        id: 'session',
        profileId: 'default',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 5,
        correctCount: 4,
        starsEarned: 2,
        durationSeconds: 60,
        startedAt: now,
        finishedAt: now,
      ),
    );

    final stat = buildDailyStats(days: 1, now: now).single;

    expect(stat.poemCount, 1);
    expect(stat.mathTotal, 5);
    expect(stat.mathCorrect, 4);
    expect(stat.starsEarned, 6);
    expect(stat.durationSeconds, 90);
  });
}

Future<void> _putSummary(
  DateTime date, {
  required int poemCount,
  required int mathTotal,
  required int mathCorrect,
  required int stars,
  required int duration,
}) async {
  final dateKey = _dateKey(date);
  await HiveBoxes.checkIns.put(
    'default_$dateKey',
    CheckIn(
      profileId: 'default',
      date: dateKey,
      poemCount: poemCount,
      mathTotalCount: mathTotal,
      mathCorrectCount: mathCorrect,
      starsEarned: stars,
      durationSeconds: duration,
      isCheckedIn: false,
      activitySources:
          CheckIn.poemActivitySource | CheckIn.mathActivitySource,
    ),
  );
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
