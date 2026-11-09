import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/repositories/challenge_record_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  for (final now in [
    DateTime(2026, 11, 9, 12),
    DateTime(2026, 3, 8, 12), // 纽约夏令时开始：23 小时的一天。
    DateTime(2026, 11, 1, 12), // 纽约夏令时结束：25 小时的一天。
  ]) {
    test('今日统计包含零点、排除次日及未来，兼容 UTC 存储：$now', () async {
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day + 1);
      final math = MathSessionRepository(now: () => now.toUtc());
      final poems = PoemProgressRepository(now: () => now.toUtc());
      final challenge = ChallengeRecordRepository(now: () => now.toUtc());

      for (final entry in [
        (id: 'midnight', time: start),
        (id: 'during', time: end.subtract(const Duration(milliseconds: 1))),
        (id: 'utc', time: now.toUtc()),
        (id: 'tomorrow', time: end.toUtc()),
        (id: 'future', time: DateTime(now.year, now.month, now.day + 2)),
        (
          id: 'yesterday',
          time: start.subtract(const Duration(milliseconds: 1)),
        ),
      ]) {
        await math.save(
          MathSession(
            id: 'math-${entry.id}',
            profileId: 'default',
            grade: 2,
            problemType: 'mixed',
            totalProblems: 1,
            finishedAt: entry.time,
          ),
        );
        await poems.save(
          PoemProgress(
            poemId: 'poem-${entry.id}',
            profileId: 'default',
            lastStudiedAt: entry.time,
            status: LearningStatus.learning,
          ),
        );
        await challenge.save(
          ChallengeRecord(
            id: 'challenge-${entry.id}',
            profileId: 'default',
            mode: 'fixed',
            score: 1,
            totalAnswered: 1,
            correctCount: 1,
            bestCombo: 1,
            grade: 2,
            semester: '上',
            difficulty: 'easy',
            durationSeconds: 1,
            createdAt: entry.time,
          ),
        );
      }

      expect(math.todayProblems, 3);
      expect(poems.todayStudiedCount, 3);
      expect(challenge.todayProblems, 3);
    });
  }
}
