// lib/data/providers/provider_invalidation.dart
//
// 层级：data/providers
// 职责：备份恢复 / 云端下载后，统一刷新所有从 Hive 读取的缓存 Provider。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// 刷新所有从 Hive 读取的缓存 Provider，确保 UI 立即反映最新数据。
void invalidateAllHiveProviders(void Function(ProviderOrFamily) invalidate) {
  // ---- 首页 / 个人中心 ----
  invalidate(todayCheckInProvider);
  invalidate(isCheckedInProvider);
  invalidate(streakProvider);
  invalidate(userStatsProvider);
  invalidate(todayPoemCountProvider);
  invalidate(todayMathCountProvider);
  invalidate(dailyPoemGoalProvider);
  invalidate(dailyMathGoalProvider);
  invalidate(unlockedAchievementsCountProvider);

  // ---- 口算模块 ----
  invalidate(mistakeCountProvider);
  invalidate(mathMistakesProvider);
  invalidate(unresolvedMistakesProvider);
  invalidate(recentSessionsProvider);
  invalidate(totalProblemsCountProvider);
  invalidate(overallAccuracyProvider);

  // ---- 诗词模块 ----
  invalidate(poemProgressProvider);
  invalidate(isFavoriteProvider);
  invalidate(dueReviewCountProvider);
  invalidate(learnedCountProvider);

  // ---- 设置 ----
  invalidate(settingsRepositoryProvider);
}
