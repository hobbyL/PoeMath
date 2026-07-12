// test/domain/achievement_checker_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/domain/achievement_checker.dart';

void main() {
  group('AchievementDefinitions', () {
    test('all definitions have unique IDs', () {
      final ids = AchievementDefinitions.all.map((d) => d.id).toSet();
      expect(ids.length, AchievementDefinitions.all.length);
    });

    test('all definitions have non-empty titles', () {
      for (final def in AchievementDefinitions.all) {
        expect(def.title, isNotEmpty, reason: 'id=${def.id}');
      }
    });

    test('progressFn returns 0.0 for fresh stats', () {
      final stats = UserStats(profileId: 'test');
      for (final def in AchievementDefinitions.all) {
        expect(
          def.progressFn(stats),
          0.0,
          reason: 'id=${def.id} should be 0.0 for fresh stats',
        );
      }
    });

    test('streak_3 reaches 1.0 at 3 days', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'streak_3');
      final stats = UserStats(profileId: 'test', currentStreak: 3);
      expect(def.progressFn(stats), 1.0);
    });

    test('poems_10 reaches 1.0 at 10 poems', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'poems_10');
      final stats = UserStats(profileId: 'test', poemsLearned: 10);
      expect(def.progressFn(stats), 1.0);
    });

    test('math_100 reaches 1.0 at 100 problems', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'math_100');
      final stats = UserStats(profileId: 'test', mathTotalProblems: 100);
      expect(def.progressFn(stats), 1.0);
    });

    test('math_accuracy_90 returns 0.0 when under 50 problems', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_accuracy_90');
      final stats = UserStats(
        profileId: 'test',
        mathTotalProblems: 30,
        mathTotalCorrect: 30,
      );
      expect(def.progressFn(stats), 0.0);
    });

    test('math_accuracy_90 reaches 1.0 at 90% with 50+ problems', () {
      final def = AchievementDefinitions.all
          .firstWhere((d) => d.id == 'math_accuracy_90');
      final stats = UserStats(
        profileId: 'test',
        mathTotalProblems: 100,
        mathTotalCorrect: 90,
      );
      expect(def.progressFn(stats), 1.0);
    });

    test('stars_50 reaches 1.0 at 50 stars', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'stars_50');
      final stats = UserStats(profileId: 'test', totalStars: 50);
      expect(def.progressFn(stats), 1.0);
    });

    test('level_3 reaches 1.0 at level 3', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'level_3');
      final stats = UserStats(profileId: 'test', level: 3);
      expect(def.progressFn(stats), 1.0);
    });

    test('progress clamps to 1.0 when exceeding target', () {
      final def =
          AchievementDefinitions.all.firstWhere((d) => d.id == 'streak_3');
      final stats = UserStats(profileId: 'test', currentStreak: 100);
      expect(def.progressFn(stats), 1.0);
    });
  });
}
