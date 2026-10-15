// lib/features/poem/providers/poem_providers.dart
//
// 诗词模块 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/poem_favorite_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/poem_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';

// ============ Repositories ============
//
// 仓储 Provider 的唯一来源是 `data/providers/repository_providers.dart`。
// 本文件曾各自再定义一份同类型 Provider，导致「test 里覆写其中一个、业务
// 实际读另一个」——类型相同但实例不同，覆写看似生效实则落空。此处改为
// **纯别名赋值**（`final a = b;`），两个名字指向同一 Provider 实例，
// `ref.invalidate` 任一名即失效同一实例。
//
// 新代码请直接用数据层的 `xxxRepositoryProvider` 命名。

// 显式标注类型：顶层 `final` 靠赋值推断，但该文件与数据层互相 import 时
// 推断会形成环，跨文件读到的可能是 `dynamic`（表现为 `ref.watch` 类型
// 无法推断、返回值退化为 dynamic）。标注后类型立即稳定。

final Provider<PoemRepository> poemRepoProvider = poemRepositoryProvider;

final Provider<PoemProgressRepository> poemProgressRepoProvider =
    poemProgressRepositoryProvider;

final Provider<PoemFavoriteRepository> poemFavoriteRepoProvider =
    poemFavoriteRepositoryProvider;

final Provider<ReviewRepository> reviewRepoProvider = reviewRepositoryProvider;

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

/// 当前选中层级筛选（null = 全部，'core'/'extended'/'explore'）
final selectedLayerFilterProvider = StateProvider<String?>((ref) => null);

/// 筛选后的诗词列表
final filteredPoemsProvider = Provider<List<Poem>>((ref) {
  final repo = ref.watch(poemRepoProvider);
  final grade = ref.watch(selectedGradeProvider);
  final query = ref.watch(poemSearchQueryProvider);
  final statusFilter = ref.watch(selectedStatusFilterProvider);
  final authorFilter = ref.watch(selectedAuthorFilterProvider);
  final dynastyFilter = ref.watch(selectedDynastyFilterProvider);
  final layerFilter = ref.watch(selectedLayerFilterProvider);

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
              p.author.toLowerCase().contains(lower) ||
              // 名句与标签也参与命中（如搜「思乡」命中标签、搜名句片段命中原诗）
              p.famousLines.any((l) => l.toLowerCase().contains(lower)) ||
              p.tags.any((t) => t.toLowerCase().contains(lower)),
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

  // 按层级筛选
  if (layerFilter != null) {
    poems = poems.where((p) => p.layer == layerFilter).toList();
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
