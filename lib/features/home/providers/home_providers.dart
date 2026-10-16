// lib/features/home/providers/home_providers.dart
//
// 首页 / 游戏化 Riverpod providers。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';

// ============ Repositories ============
//
// 这三个仓库的 Provider 归 `data/providers/repository_providers.dart` 统一管理。
// 本文件曾各自再定义一份同类型 Provider，导致 test 里覆写其中一个、实际读取
// 另一个（obvious 的类型相同但实例不同）。此处只做转发，保持既有引用可编译，
// 但**所有实例只有一个来源**，覆写任一名即生效。
//
// 新代码请直接用 `repository_providers.dart` 的 `xxxRepositoryProvider`。

final Provider<CheckInRepository> checkInRepoProvider =
    checkInRepositoryProvider;

final Provider<UserStatsRepository> userStatsRepoProvider =
    userStatsRepositoryProvider;

final Provider<AchievementRepository> achievementRepoProvider =
    achievementRepositoryProvider;

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
//
// 这些 Provider 读的是**实时的** Hive 值（仓库方法每次都现查 box），但
// `Provider` 自身不会因为 Hive 写入而失效 —— 缓存的是上一次的计算结果。
// 因此除了 `dayKeyProvider`（跨天）之外，还必须在**活动结算点**显式
// `ref.invalidate`，否则做完题回到首页看到的仍是进入前的旧数字。
// 结算点的既有写法见 `poem_read_along_page.dart` 与该页的练习结算流程。

/// 今日诗词学习数
final todayPoemCountProvider = Provider<int>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final repo = ref.watch(poemProgressRepositoryProvider);
  return repo.todayStudiedCount;
});

/// 今日口算做题数
final todayMathCountProvider = Provider<int>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final sessionRepo = ref.watch(mathSessionRepositoryProvider);
  final challengeRepo = ref.watch(challengeRecordRepositoryProvider);
  return sessionRepo.todayProblems + challengeRepo.todayProblems;
});

// ============ 每日目标 ============

/// 每日诗词目标
final dailyPoemGoalProvider = Provider<int>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return settings.dailyPoemGoal;
});

/// 每日口算目标
final dailyMathGoalProvider = Provider<int>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
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
  final poemRepo = ref.watch(poemRepositoryProvider);
  final progressRepo = ref.watch(poemProgressRepositoryProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final allPoems = poemRepo.getAll();
  if (allPoems.isEmpty) return null;
  final textbookPoems = allPoems
      .where(
        (p) =>
            p.grade == settings.selectedGrade &&
            p.semester == settings.selectedSemester &&
            p.isRequired,
      )
      .toList();
  final candidates = textbookPoems.isEmpty ? allPoems : textbookPoems;

  // 筛选未学习的诗词
  final unlearned = candidates.where((p) {
    final progress = progressRepo.get(p.id);
    return progress == null;
  }).toList();

  // 基于日期做伪随机，确保同一天推荐同一首
  final daysSinceEpoch = DateTime.now()
      .difference(
        DateTime(2024),
      )
      .inDays;

  if (unlearned.isNotEmpty) {
    return unlearned[daysSinceEpoch % unlearned.length];
  }
  // 全部学过 → 从全部诗词中推荐
  return candidates[daysSinceEpoch % candidates.length];
});
