// lib/features/home/providers/home_providers.dart
//
// 首页 / 游戏化 Riverpod providers。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/challenge_record_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/poem_repository.dart';
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

// ============ 日期失效源 ============

/// 今日日期 key（yyyy-MM-dd）。跨天自动失效日相关 Provider。
///
/// Timer 每 30s 比对一次日期字符串，覆盖「前台持续跨午夜」；
/// 「后台跨天再 resumed」由恢复后的首次比对覆盖（最多延迟 30s，可接受）。
/// 日相关 Provider 通过 `ref.watch(dayKeyProvider)` 建立依赖，
/// dayKey 变化时自动重建重算。
class DayKeyNotifier extends Notifier<String> {
  Timer? _timer;

  @override
  String build() {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final today = _todayKey();
      if (state != today) state = today;
    });
    ref.onDispose(_timer!.cancel);
    return _todayKey();
  }
}

final dayKeyProvider = NotifierProvider<DayKeyNotifier, String>(
  DayKeyNotifier.new,
);

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

// ============ 打卡 ============

/// 今日打卡记录
final todayCheckInProvider = Provider<CheckIn?>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final repo = ref.watch(checkInRepoProvider);
  return repo.getToday();
});

/// 是否已打卡
final isCheckedInProvider = Provider<bool>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final repo = ref.watch(checkInRepoProvider);
  return repo.isCheckedInToday();
});

/// 连续打卡天数
final streakProvider = Provider<int>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
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
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final repo = PoemProgressRepository();
  return repo.todayStudiedCount;
});

/// 今日口算做题数
final todayMathCountProvider = Provider<int>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final sessionRepo = MathSessionRepository();
  final challengeRepo = ChallengeRecordRepository();
  return sessionRepo.todayProblems + challengeRepo.todayProblems;
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

// ============ 今日推荐 ============

/// 今日推荐诗词 — 优先推荐未学习的诗词，基于日期做伪随机选择。
final dailyRecommendedPoemProvider = Provider<Poem?>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：跨午夜后自然换诗
  final poemRepo = PoemRepository();
  final progressRepo = PoemProgressRepository();
  final allPoems = poemRepo.getAll();
  if (allPoems.isEmpty) return null;

  // 筛选未学习的诗词
  final unlearned = allPoems.where((p) {
    final progress = progressRepo.get(p.id);
    return progress == null;
  }).toList();

  // 基于日期做伪随机，确保同一天推荐同一首
  final daysSinceEpoch = DateTime.now().difference(
    DateTime(2024),
  ).inDays;

  if (unlearned.isNotEmpty) {
    return unlearned[daysSinceEpoch % unlearned.length];
  }
  // 全部学过 → 从全部诗词中推荐
  return allPoems[daysSinceEpoch % allPoems.length];
});
