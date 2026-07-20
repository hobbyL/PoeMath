// lib/data/repositories/user_stats_repository.dart
//
// 层级：data/repositories
// 职责：用户统计数据仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/domain/level_calculator.dart';

class UserStatsRepository {
  /// 获取当前 profile 的统计数据
  ///
  /// 若不存在则返回一个默认值（不立即写入 Hive，
  /// 避免在同步 Provider 中触发 unawaited Future 导致测试挂起）。
  UserStats get() {
    final key = ProfileScope.key('stats');
    return HiveBoxes.userStats.get(key) ??
        UserStats(profileId: ProfileScope.currentId);
  }

  /// 获取当前 profile 的统计数据，若不存在则创建并持久化。
  Future<UserStats> getOrCreate() async {
    final key = ProfileScope.key('stats');
    var stats = HiveBoxes.userStats.get(key);
    if (stats == null) {
      stats = UserStats(profileId: ProfileScope.currentId);
      await HiveBoxes.userStats.put(key, stats);
    }
    return stats;
  }

  /// 保存统计数据
  Future<void> save(UserStats stats) async {
    final key = ProfileScope.key('stats');
    await HiveBoxes.userStats.put(key, stats);
  }

  /// 增加星星，并同步更新由总星星数派生的等级。
  Future<void> addStars(int count) async {
    final stats = await getOrCreate();
    stats.totalStars += count;
    stats.level = LevelCalculator.calculate(stats.totalStars);
    await stats.save();
  }

  /// 更新连续打卡
  Future<void> updateStreak(int currentStreak) async {
    final stats = await getOrCreate();
    stats.currentStreak = currentStreak;
    if (currentStreak > stats.longestStreak) {
      stats.longestStreak = currentStreak;
    }
    await stats.save();
  }

  /// 更新诗词学习统计
  Future<void> updatePoemStats({int? learned, int? mastered}) async {
    final stats = await getOrCreate();
    if (learned != null) stats.poemsLearned = learned;
    if (mastered != null) stats.poemsMastered = mastered;
    await stats.save();
  }

  /// 更新口算统计
  Future<void> addMathResults({
    required int problems,
    required int correct,
  }) async {
    final stats = await getOrCreate();
    stats.mathTotalProblems += problems;
    stats.mathTotalCorrect += correct;
    await stats.save();
  }

  /// 更新口算最佳连续答对数（仅在新纪录超过旧纪录时更新）
  Future<void> updateMathBestStreak(int streak) async {
    final stats = await getOrCreate();
    if (streak > stats.mathBestStreak) {
      stats.mathBestStreak = streak;
      await stats.save();
    }
  }
}
