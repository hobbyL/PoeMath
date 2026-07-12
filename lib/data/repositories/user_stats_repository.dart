// lib/data/repositories/user_stats_repository.dart
//
// 层级：data/repositories
// 职责：用户统计数据仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/user_stats.dart';

class UserStatsRepository {
  /// 获取当前 profile 的统计数据
  UserStats get() {
    final key = ProfileScope.key('stats');
    var stats = HiveBoxes.userStats.get(key);
    if (stats == null) {
      stats = UserStats(profileId: ProfileScope.currentId);
      HiveBoxes.userStats.put(key, stats);
    }
    return stats;
  }

  /// 保存统计数据
  Future<void> save(UserStats stats) async {
    final key = ProfileScope.key('stats');
    await HiveBoxes.userStats.put(key, stats);
  }

  /// 增加星星
  Future<void> addStars(int count) async {
    final stats = get();
    stats.totalStars += count;
    await stats.save();
  }

  /// 更新连续打卡
  Future<void> updateStreak(int currentStreak) async {
    final stats = get();
    stats.currentStreak = currentStreak;
    if (currentStreak > stats.longestStreak) {
      stats.longestStreak = currentStreak;
    }
    await stats.save();
  }

  /// 更新诗词学习统计
  Future<void> updatePoemStats({int? learned, int? mastered}) async {
    final stats = get();
    if (learned != null) stats.poemsLearned = learned;
    if (mastered != null) stats.poemsMastered = mastered;
    await stats.save();
  }

  /// 更新口算统计
  Future<void> addMathResults({
    required int problems,
    required int correct,
  }) async {
    final stats = get();
    stats.mathTotalProblems += problems;
    stats.mathTotalCorrect += correct;
    await stats.save();
  }

  /// 更新等级
  Future<void> updateLevel(int level) async {
    final stats = get();
    stats.level = level;
    await stats.save();
  }
}
