// lib/features/formula/providers/formula_providers.dart
//
// 公式模块 Riverpod providers。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/repositories/formula_favorite_repository.dart';
import 'package:poemath/data/repositories/formula_repository.dart';

// ============ Repositories ============

final formulaRepoProvider = Provider<FormulaRepository>((ref) {
  return FormulaRepository();
});

final formulaFavoriteRepoProvider = Provider<FormulaFavoriteRepository>((ref) {
  return FormulaFavoriteRepository();
});

// ============ 筛选 ============

/// 当前选中分类（null = 全部）
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

/// 搜索关键词
final formulaSearchQueryProvider = StateProvider<String>((ref) => '');

/// 筛选后的公式列表
final filteredFormulasProvider = Provider<List<Formula>>((ref) {
  final repo = ref.watch(formulaRepoProvider);
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(formulaSearchQueryProvider);

  List<Formula> formulas;
  if (category != null) {
    formulas = repo.byCategory(category);
  } else {
    formulas = repo.getAll();
  }

  if (query.isNotEmpty) {
    formulas = repo.search(query);
    if (category != null) {
      formulas = formulas.where((f) => f.category == category).toList();
    }
  }

  return formulas;
});

/// 可用分类列表
final availableCategoriesProvider = Provider<List<String>>((ref) {
  final repo = ref.watch(formulaRepoProvider);
  return repo.availableCategories;
});

// ============ 详情 ============

/// 指定 ID 的公式
final formulaByIdProvider = Provider.family<Formula?, String>((ref, id) {
  final repo = ref.watch(formulaRepoProvider);
  return repo.getById(id);
});

/// 是否已收藏
final isFormulaFavoriteProvider = Provider.family<bool, String>((ref, id) {
  final repo = ref.watch(formulaFavoriteRepoProvider);
  return repo.isFavorite(id);
});

// ============ 统计 ============

/// 公式总数
final formulaCountProvider = Provider<int>((ref) {
  final repo = ref.watch(formulaRepoProvider);
  return repo.totalCount;
});

/// 收藏数
final formulaFavoriteCountProvider = Provider<int>((ref) {
  final repo = ref.watch(formulaFavoriteRepoProvider);
  return repo.count;
});
