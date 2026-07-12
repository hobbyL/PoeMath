// lib/data/providers/repository_providers.dart
//
// 层级：data/providers
// 职责：所有 Repository 的 Riverpod Provider。
//       全局单例，App 生命周期内不销毁。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/repositories/poem_repository.dart';
import 'package:poemath/data/repositories/author_repository.dart';
import 'package:poemath/data/repositories/formula_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/poem_favorite_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/formula_favorite_repository.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

// ============ 静态数据 Repository ============

final poemRepositoryProvider = Provider<PoemRepository>((ref) {
  return PoemRepository();
});

final authorRepositoryProvider = Provider<AuthorRepository>((ref) {
  return AuthorRepository();
});

final formulaRepositoryProvider = Provider<FormulaRepository>((ref) {
  return FormulaRepository();
});

// ============ 动态数据 Repository ============

final poemProgressRepositoryProvider =
    Provider<PoemProgressRepository>((ref) {
  return PoemProgressRepository();
});

final poemFavoriteRepositoryProvider =
    Provider<PoemFavoriteRepository>((ref) {
  return PoemFavoriteRepository();
});

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository();
});

final mathMistakeRepositoryProvider =
    Provider<MathMistakeRepository>((ref) {
  return MathMistakeRepository();
});

final mathSessionRepositoryProvider =
    Provider<MathSessionRepository>((ref) {
  return MathSessionRepository();
});

final formulaFavoriteRepositoryProvider =
    Provider<FormulaFavoriteRepository>((ref) {
  return FormulaFavoriteRepository();
});

final achievementRepositoryProvider =
    Provider<AchievementRepository>((ref) {
  return AchievementRepository();
});

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  return CheckInRepository();
});

final userStatsRepositoryProvider = Provider<UserStatsRepository>((ref) {
  return UserStatsRepository();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});
