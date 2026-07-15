// lib/domain/achievement_check_helper.dart
//
// 成就检查辅助 — 从 Riverpod Ref 构建完整上下文并检查所有成就。
// 封装重复的 repo 读取和 context 构建逻辑，供各触发点统一调用。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/domain/achievement_checker.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';

/// 从 [ref] 构建完整 [AchievementCheckContext] 并检查所有成就。
///
/// [latestSession] 仅在口算练习完成后传入，用于判定单次全对/困难全对等。
/// 返回本次新解锁的成就列表（可用于弹出庆祝动画）。
Future<List<Achievement>> checkAchievements(
  WidgetRef ref, {
  MathSession? latestSession,
}) async {
  final achievementRepo = ref.read(achievementRepoProvider);
  final statsRepo = ref.read(userStatsRepoProvider);
  final mistakeRepo = ref.read(mathMistakeRepoProvider);
  final sessionRepo = ref.read(mathSessionRepoProvider);
  final formulaFavRepo = ref.read(formulaFavoriteRepositoryProvider);

  final resolvedMistakes =
      mistakeRepo.getAll().where((m) => m.isResolved).length;
  final completedReviewRounds = HiveBoxes.reviewSchedules.values
      .where((s) => s.profileId == ProfileScope.currentId)
      .fold<int>(0, (sum, s) => sum + s.currentRound);
  final hardModeTotal = sessionRepo
      .getAll()
      .where((s) => s.difficulty == 'hard')
      .fold<int>(0, (sum, s) => sum + s.totalProblems);

  final checker = AchievementChecker(achievementRepo);
  return checker.check(
    AchievementCheckContext(
      stats: statsRepo.get(),
      latestSession: latestSession,
      resolvedMistakes: resolvedMistakes,
      completedReviewRounds: completedReviewRounds,
      formulaFavorites: formulaFavRepo.count,
      hardModeTotalProblems: hardModeTotal,
    ),
  );
}
