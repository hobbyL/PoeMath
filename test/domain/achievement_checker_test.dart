// test/domain/achievement_checker_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/domain/achievement_checker.dart';

import '../helpers/hive_test_helper.dart';

/// 构建一个最小化的检查上下文。
AchievementCheckContext _ctx({
  UserStats? stats,
  MathSession? latestSession,
  int resolvedMistakes = 0,
  int completedReviewRounds = 0,
  int formulaFavorites = 0,
  int hardModeTotalProblems = 0,
}) {
  return AchievementCheckContext(
    stats: stats ?? UserStats(profileId: 'test'),
    latestSession: latestSession,
    resolvedMistakes: resolvedMistakes,
    completedReviewRounds: completedReviewRounds,
    formulaFavorites: formulaFavorites,
    hardModeTotalProblems: hardModeTotalProblems,
  );
}

void main() {
  group('AchievementChecker persistence', () {
    setUp(() async {
      await setUpHiveForTesting();
    });

    tearDown(() async {
      await tearDownHiveForTesting();
    });

    test('完成五轮复习后持久化并解锁复习成就', () async {
      final repo = AchievementRepository();
      final newlyUnlocked = await AchievementChecker(repo).check(
        _ctx(completedReviewRounds: 5),
      );

      final achievement = repo.getById('review_complete_5');
      expect(achievement, isNotNull);
      expect(achievement!.isUnlocked, isTrue);
      expect(
        newlyUnlocked.map((item) => item.id),
        contains('review_complete_5'),
      );
    });
  });

  group('AchievementDefinitions', () {
    test('all definitions have unique IDs', () {
      final ids = AchievementDefinitions.all.map((d) => d.id).toSet();
      expect(ids.length, AchievementDefinitions.all.length);
    });

    test('total count is 44', () {
      expect(AchievementDefinitions.all.length, 44);
    });

    test('all definitions have non-empty titles', () {
      for (final def in AchievementDefinitions.all) {
        expect(def.title, isNotEmpty, reason: 'id=${def.id}');
      }
    });

    test('progressFn returns 0.0 for fresh context', () {
      final ctx = _ctx();
      for (final def in AchievementDefinitions.all) {
        expect(
          def.progressFn(ctx),
          0.0,
          reason: 'id=${def.id} should be 0.0 for fresh context',
        );
      }
    });

    // ======== 打卡 ========
    test('streak_3 reaches 1.0 at 3 days', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'streak_3');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', currentStreak: 3),
          ),
        ),
        1.0,
      );
    });

    // ======== 诗词 ========
    test('poems_10 reaches 1.0 at 10 poems', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'poems_10');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', poemsLearned: 10),
          ),
        ),
        1.0,
      );
    });

    test('poems_1000 shows partial progress', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'poems_1000');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', poemsLearned: 500),
          ),
        ),
        0.5,
      );
    });

    // ======== 口算题量 ========
    test('math_100 reaches 1.0 at 100 problems', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'math_100');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', mathTotalProblems: 100),
          ),
        ),
        1.0,
      );
    });

    // ======== 口算正确率 ========
    test('math_accuracy_90 returns 0.0 when under 50 problems', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_accuracy_90');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(
              profileId: 'test',
              mathTotalProblems: 30,
              mathTotalCorrect: 30,
            ),
          ),
        ),
        0.0,
      );
    });

    test('math_accuracy_90 reaches 1.0 at 90% with 50+ problems', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_accuracy_90');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(
              profileId: 'test',
              mathTotalProblems: 100,
              mathTotalCorrect: 90,
            ),
          ),
        ),
        1.0,
      );
    });

    test('math_accuracy_95 requires 200+ problems', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_accuracy_95');
      // 100 题虽然 100% 正确率也不够
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(
              profileId: 'test',
              mathTotalProblems: 100,
              mathTotalCorrect: 100,
            ),
          ),
        ),
        0.0,
      );
      // 200 题 95% 才行
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(
              profileId: 'test',
              mathTotalProblems: 200,
              mathTotalCorrect: 190,
            ),
          ),
        ),
        1.0,
      );
    });

    // ======== 单次全对 ========
    test('math_perfect_15 unlocks with 15-problem perfect session', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_perfect_15');
      final session = MathSession(
        id: 's1',
        profileId: 'test',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 15,
        correctCount: 15,
      );
      expect(def.progressFn(_ctx(latestSession: session)), 1.0);
    });

    test('math_perfect_30 does not unlock with 20-problem session', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_perfect_30');
      final session = MathSession(
        id: 's1',
        profileId: 'test',
        grade: 1,
        problemType: 'mixed',
        totalProblems: 20,
        correctCount: 20,
      );
      expect(def.progressFn(_ctx(latestSession: session)), 0.0);
    });

    // ======== 连击 ========
    test('math_combo_30 reaches 1.0 at 30 best streak', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'math_combo_30');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', mathBestStreak: 30),
          ),
        ),
        1.0,
      );
    });

    // ======== 困难挑战 ========
    test('math_hard_perfect unlocks with hard + perfect session', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_hard_perfect');
      final session = MathSession(
        id: 's1',
        profileId: 'test',
        grade: 3,
        problemType: 'mixed',
        totalProblems: 10,
        correctCount: 10,
        difficulty: 'hard',
      );
      expect(def.progressFn(_ctx(latestSession: session)), 1.0);
    });

    test('math_hard_100 tracks hard mode total', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'math_hard_100');
      expect(def.progressFn(_ctx(hardModeTotalProblems: 50)), 0.5);
      expect(def.progressFn(_ctx(hardModeTotalProblems: 100)), 1.0);
    });

    // ======== 错题 ========
    test('mistakes_resolve_10 tracks resolved mistakes', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'mistakes_resolve_10');
      expect(def.progressFn(_ctx(resolvedMistakes: 5)), 0.5);
      expect(def.progressFn(_ctx(resolvedMistakes: 10)), 1.0);
    });

    // ======== 复习 ========
    test('review_complete_5 tracks completed rounds', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'review_complete_5');
      expect(
        def.progressFn(_ctx(completedReviewRounds: 3)),
        closeTo(0.6, 0.01),
      );
      expect(def.progressFn(_ctx(completedReviewRounds: 5)), 1.0);
    });

    // ======== 公式 ========
    test('formula_fav_10 tracks formula favorites', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'formula_fav_10');
      expect(def.progressFn(_ctx(formulaFavorites: 10)), 1.0);
    });

    // ======== 星星/等级 ========
    test('stars_50 reaches 1.0 at 50 stars', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'stars_50');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', totalStars: 50),
          ),
        ),
        1.0,
      );
    });

    test('level_3 reaches 1.0 at level 3', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'level_3');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', level: 3),
          ),
        ),
        1.0,
      );
    });

    test('progress clamps to 1.0 when exceeding target', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'streak_3');
      expect(
        def.progressFn(
          _ctx(
            stats: UserStats(profileId: 'test', currentStreak: 100),
          ),
        ),
        1.0,
      );
    });
  });
}
