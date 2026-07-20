import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('口算首页总题数和正确率读取包含挑战的主统计', () async {
    await HiveBoxes.userStats.put(
      'default_stats',
      UserStats(
        profileId: 'default',
        mathTotalProblems: 25,
        mathTotalCorrect: 20,
      ),
    );
    await HiveBoxes.mathSessions.put(
      'default_legacy',
      MathSession(
        id: 'legacy',
        profileId: 'default',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 10,
        correctCount: 10,
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(totalProblemsCountProvider), 25);
    expect(container.read(overallAccuracyProvider), 0.8);
  });

  test('今日口算题量合并普通练习与限时挑战', () async {
    final now = DateTime.now();
    await HiveBoxes.mathSessions.put(
      'default_session',
      MathSession(
        id: 'session',
        profileId: 'default',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 8,
        correctCount: 7,
        finishedAt: now,
      ),
    );
    await HiveBoxes.challengeRecords.put(
      'default_challenge',
      ChallengeRecord(
        id: 'challenge',
        profileId: 'default',
        mode: 'fixed',
        score: 50,
        totalAnswered: 6,
        correctCount: 5,
        bestCombo: 3,
        grade: 1,
        semester: '上',
        difficulty: 'medium',
        durationSeconds: 60,
        createdAt: now,
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(todayMathCountProvider), 14);
  });
}
