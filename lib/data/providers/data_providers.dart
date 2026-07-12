// lib/data/providers/data_providers.dart
//
// 层级：data/providers
// 职责：面向 UI 层的数据 Provider。
//       封装 Repository 调用，提供便捷的数据访问入口。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/author.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/providers/repository_providers.dart';

// ============ 诗词相关 ============

/// 单首诗词（按 ID）
final poemProvider = Provider.family<Poem?, String>((ref, id) {
  return ref.watch(poemRepositoryProvider).getById(id);
});

/// 按年级获取诗词列表
final poemsByGradeProvider = Provider.family<List<Poem>, int>((ref, grade) {
  return ref.watch(poemRepositoryProvider).byGrade(grade);
});

/// 按作者获取诗词列表
final poemsByAuthorProvider =
    Provider.family<List<Poem>, String>((ref, author) {
  return ref.watch(poemRepositoryProvider).byAuthor(author);
});

/// 按朝代获取诗词列表
final poemsByDynastyProvider =
    Provider.family<List<Poem>, String>((ref, dynasty) {
  return ref.watch(poemRepositoryProvider).byDynasty(dynasty);
});

/// 按标签获取诗词列表
final poemsByTagProvider =
    Provider.family<List<Poem>, String>((ref, tag) {
  return ref.watch(poemRepositoryProvider).byTag(tag);
});

/// 诗词总数
final poemTotalCountProvider = Provider<int>((ref) {
  return ref.watch(poemRepositoryProvider).totalCount;
});

// ============ 作者相关 ============

/// 按名字获取作者
final authorByNameProvider =
    Provider.family<Author?, String>((ref, name) {
  return ref.watch(authorRepositoryProvider).getByName(name);
});

// ============ 公式相关 ============

/// 按分类获取公式列表
final formulasByCategoryProvider =
    Provider.family<List<Formula>, String>((ref, category) {
  return ref.watch(formulaRepositoryProvider).byCategory(category);
});

/// 公式分类列表
final formulaCategoriesProvider = Provider<List<String>>((ref) {
  return ref.watch(formulaRepositoryProvider).availableCategories;
});

// ============ 进度相关 ============

/// 某首诗的学习进度
final poemProgressProvider =
    Provider.family<PoemProgress?, String>((ref, poemId) {
  return ref.watch(poemProgressRepositoryProvider).get(poemId);
});

// ============ 收藏相关 ============

/// 某首诗是否已收藏
final isPoemFavoriteProvider =
    Provider.family<bool, String>((ref, poemId) {
  return ref.watch(poemFavoriteRepositoryProvider).isFavorite(poemId);
});

/// 某公式是否已收藏
final isFormulaFavoriteProvider =
    Provider.family<bool, String>((ref, formulaId) {
  return ref.watch(formulaFavoriteRepositoryProvider).isFavorite(formulaId);
});

// ============ 打卡 / 统计 ============

/// 今日是否已打卡
final isCheckedInTodayProvider = Provider<bool>((ref) {
  return ref.watch(checkInRepositoryProvider).isCheckedInToday();
});

/// 连续打卡天数
final currentStreakProvider = Provider<int>((ref) {
  return ref.watch(checkInRepositoryProvider).calculateStreak();
});

/// 用户统计
final userStatsProvider = Provider<UserStats>((ref) {
  return ref.watch(userStatsRepositoryProvider).get();
});

/// 当前活跃 Profile ID
final activeProfileIdProvider = Provider<String>((ref) {
  return ProfileScope.currentId;
});

// ============ 复习 ============

/// 今日待复习的诗词
final dueReviewsProvider = Provider<List<ReviewSchedule>>((ref) {
  return ref.watch(reviewRepositoryProvider).getDueToday();
});

// ============ 错题 ============

/// 未解决错题数
final unresolvedMistakeCountProvider = Provider<int>((ref) {
  return ref.watch(mathMistakeRepositoryProvider).unresolvedCount;
});
