// lib/features/poem/providers/poem_providers.dart
//
// 诗词模块 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/repositories/poem_favorite_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/poem_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';

// ============ Repositories ============

final poemRepoProvider = Provider<PoemRepository>((ref) {
  final repo = PoemRepository();
  repo.buildIndices();
  return repo;
});

final poemProgressRepoProvider = Provider<PoemProgressRepository>((ref) {
  return PoemProgressRepository();
});

final poemFavoriteRepoProvider = Provider<PoemFavoriteRepository>((ref) {
  return PoemFavoriteRepository();
});

final reviewRepoProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository();
});

// ============ 诗词列表 ============

/// 当前选中年级（null = 全部）
final selectedGradeProvider = StateProvider<int?>((ref) => null);

/// 当前选中学习状态筛选（null = 全部）
final selectedStatusFilterProvider =
    StateProvider<LearningStatus?>((ref) => null);

/// 搜索关键词
final poemSearchQueryProvider = StateProvider<String>((ref) => '');

/// 当前选中作者筛选（null = 全部）
final selectedAuthorFilterProvider = StateProvider<String?>((ref) => null);

/// 当前选中朝代筛选（null = 全部）
final selectedDynastyFilterProvider = StateProvider<String?>((ref) => null);

/// 筛选后的诗词列表
final filteredPoemsProvider = Provider<List<Poem>>((ref) {
  final repo = ref.watch(poemRepoProvider);
  final grade = ref.watch(selectedGradeProvider);
  final query = ref.watch(poemSearchQueryProvider);
  final statusFilter = ref.watch(selectedStatusFilterProvider);
  final authorFilter = ref.watch(selectedAuthorFilterProvider);
  final dynastyFilter = ref.watch(selectedDynastyFilterProvider);

  List<Poem> poems;
  if (grade != null) {
    poems = repo.byGrade(grade);
  } else {
    poems = repo.getAll();
  }

  if (query.isNotEmpty) {
    final lower = query.toLowerCase();
    poems = poems
        .where(
          (p) =>
              p.title.toLowerCase().contains(lower) ||
              p.content.toLowerCase().contains(lower) ||
              p.author.toLowerCase().contains(lower),
        )
        .toList();
  }

  // 按作者筛选
  if (authorFilter != null) {
    poems = poems.where((p) => p.author == authorFilter).toList();
  }

  // 按朝代筛选
  if (dynastyFilter != null) {
    poems = poems.where((p) => p.dynasty == dynastyFilter).toList();
  }

  // 按学习状态筛选
  if (statusFilter != null) {
    final progressRepo = ref.watch(poemProgressRepoProvider);
    poems = poems.where((p) {
      final progress = progressRepo.get(p.id);
      final status = progress?.status ?? LearningStatus.notStarted;
      return status == statusFilter;
    }).toList();
  }

  return poems;
});

/// 可用年级列表
final availableGradesProvider = Provider<List<int>>((ref) {
  final repo = ref.watch(poemRepoProvider);
  return repo.availableGrades;
});

/// 可用作者列表
final availableAuthorsProvider = Provider<List<String>>((ref) {
  final repo = ref.watch(poemRepoProvider);
  return repo.availableAuthors;
});

/// 可用朝代列表
final availableDynastiesProvider = Provider<List<String>>((ref) {
  final repo = ref.watch(poemRepoProvider);
  return repo.availableDynasties;
});

// ============ 诗词详情 ============

/// 当前查看的诗词
final currentPoemProvider = StateProvider<Poem?>((ref) => null);

/// 指定 ID 的诗词
final poemByIdProvider = Provider.family<Poem?, String>((ref, id) {
  final repo = ref.watch(poemRepoProvider);
  return repo.getById(id);
});

/// 诗词进度
final poemProgressProvider =
    Provider.family<PoemProgress?, String>((ref, poemId) {
  final repo = ref.watch(poemProgressRepoProvider);
  return repo.get(poemId);
});

/// 是否已收藏
final isFavoriteProvider = Provider.family<bool, String>((ref, poemId) {
  final repo = ref.watch(poemFavoriteRepoProvider);
  return repo.isFavorite(poemId);
});

// ============ 复习 ============

/// 今日待复习数量
final dueReviewCountProvider = Provider<int>((ref) {
  final repo = ref.watch(reviewRepoProvider);
  return repo.getDueToday().length;
});

// ============ 统计 ============

/// 已学习诗词数
final learnedCountProvider = Provider<int>((ref) {
  final repo = ref.watch(poemProgressRepoProvider);
  return repo.learnedCount;
});

/// 已掌握诗词数
final masteredCountProvider = Provider<int>((ref) {
  final repo = ref.watch(poemProgressRepoProvider);
  return repo.masteredCount;
});
