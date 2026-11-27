// lib/features/home/providers/home_providers.dart
//
// 首页 / 游戏化 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/poem_identity.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/daily_practice_providers.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/domain/daily_goal_activity.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

export 'package:poemath/data/providers/daily_practice_providers.dart'
    show DayKeyNotifier, dayKeyProvider;

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
// 目标计数监听完成活动、进度和档案变化，并通过 dayKeyProvider 跨天重算。
// 口算等未监听 box 的统计仍需在结算点显式失效；诗词结算保留原有失效，
// 确保回首页时立即读取已保存的结果。

/// 今日可计入目标的诗词数：同一首诗五个自然日内只计入一天。
final todayPoemCountProvider = Provider<int>((ref) {
  return ref.watch(poemDailyPracticeSpacingProvider).countedToday;
});

/// 今日口算做题数
final todayMathCountProvider = Provider<int>((ref) {
  ref.watch(dayKeyProvider); // 跨天失效：dayKey 变化时重建
  final sessionRepo = ref.watch(mathSessionRepositoryProvider);
  final challengeRepo = ref.watch(challengeRecordRepositoryProvider);
  return sessionRepo.todayProblems + challengeRepo.todayProblems;
});

class TodayLearningActivityCounts {
  const TodayLearningActivityCounts({
    this.textbookRecognition = 0,
    this.textbookWriting = 0,
    this.pictureStoryExpression = 0,
    this.english = 0,
  });

  final int textbookRecognition;
  final int textbookWriting;
  final int pictureStoryExpression;
  final int english;
}

final todayLearningActivityCountsProvider =
    Provider<TodayLearningActivityCounts>((ref) {
      final today = DateTime.parse(ref.watch(dayKeyProvider));
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final activities = ref.watch(learningActivityHistoryProvider);
      var recognition = 0;
      var writing = 0;
      var english = 0;
      for (final activity in activities) {
        if (activity.completedAt.isBefore(today) ||
            !activity.completedAt.isBefore(tomorrow)) {
          continue;
        }
        switch (activity.typeOrNull) {
          case LearningActivityType.textbookRecognition:
            recognition++;
          case LearningActivityType.textbookWriting:
            writing++;
          case LearningActivityType.englishPractice ||
              LearningActivityType.englishSpeaking:
            english++;
          default:
            break;
        }
      }
      return TodayLearningActivityCounts(
        textbookRecognition: recognition,
        textbookWriting: writing,
        pictureStoryExpression: ref
            .watch(pictureStoryDailyPracticeSpacingProvider)
            .countedToday,
        english: english,
      );
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

final dailyGoalTypesProvider = Provider<Set<DailyGoalActivity>>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return settings.dailyGoalTypes;
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
  final hidden = ref.watch(poemDailyPracticeSpacingProvider).hiddenContentIds;
  final allPoems = poemRepo
      .getAll()
      .where((poem) => !hidden.contains(PoemIdentity.canonical(poem.id)))
      .toList();
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
  final daysSinceEpoch = DateTime.now().difference(DateTime(2024)).inDays;

  if (unlearned.isNotEmpty) {
    return unlearned[daysSinceEpoch % unlearned.length];
  }
  // 全部学过 → 从全部诗词中推荐
  return candidates[daysSinceEpoch % candidates.length];
});
