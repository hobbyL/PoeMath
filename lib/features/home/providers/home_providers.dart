// lib/features/home/providers/home_providers.dart
//
// 首页 / 游戏化 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';

// ============ Repositories ============

final checkInRepoProvider = Provider<CheckInRepository>((ref) {
  return CheckInRepository();
});

final userStatsRepoProvider = Provider<UserStatsRepository>((ref) {
  return UserStatsRepository();
});

final achievementRepoProvider = Provider<AchievementRepository>((ref) {
  return AchievementRepository();
});

// ============ 打卡 ============

/// 今日打卡记录
final todayCheckInProvider = Provider<CheckIn?>((ref) {
  final repo = ref.watch(checkInRepoProvider);
  return repo.getToday();
});

/// 是否已打卡
final isCheckedInProvider = Provider<bool>((ref) {
  final repo = ref.watch(checkInRepoProvider);
  return repo.isCheckedInToday();
});

/// 连续打卡天数
final streakProvider = Provider<int>((ref) {
  final repo = ref.watch(checkInRepoProvider);
  return repo.calculateStreak();
});

// ============ 用户统计 ============

/// 用户统计数据
final userStatsProvider = Provider<UserStats>((ref) {
  final repo = ref.watch(userStatsRepoProvider);
  return repo.get();
});

// ============ 今日活动统计 ============

/// 今日诗词学习数
final todayPoemCountProvider = Provider<int>((ref) {
  final repo = PoemProgressRepository();
  return repo.todayStudiedCount;
});

/// 今日口算做题数
final todayMathCountProvider = Provider<int>((ref) {
  final repo = MathSessionRepository();
  return repo.todayProblems;
});

// ============ 每日目标 ============

/// 每日诗词目标
final dailyPoemGoalProvider = Provider<int>((ref) {
  final settings = SettingsRepository();
  return settings.dailyPoemGoal;
});

/// 每日口算目标
final dailyMathGoalProvider = Provider<int>((ref) {
  final settings = SettingsRepository();
  return settings.dailyMathGoal;
});

// ============ 成就 ============

/// 已解锁成就数
final unlockedAchievementsCountProvider = Provider<int>((ref) {
  final repo = ref.watch(achievementRepoProvider);
  return repo.unlockedCount;
});

// ============ 恢复辅助 ============

/// 恢复数据后，刷新所有从 Hive 读取的缓存 Provider。
///
/// 用于备份恢复 / 云端下载后，确保 UI 立即反映最新数据。
void invalidateAllHiveProviders(void Function(ProviderOrFamily) invalidate) {
  invalidate(todayCheckInProvider);
  invalidate(isCheckedInProvider);
  invalidate(streakProvider);
  invalidate(userStatsProvider);
  invalidate(todayPoemCountProvider);
  invalidate(todayMathCountProvider);
  invalidate(dailyPoemGoalProvider);
  invalidate(dailyMathGoalProvider);
  invalidate(unlockedAchievementsCountProvider);
}
