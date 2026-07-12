// lib/data/repositories/formula_repository.dart
//
// 层级：data/repositories
// 职责：公式数据仓储。

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula.dart';

class FormulaRepository {
  /// 按 ID 获取
  Formula? getById(String id) => HiveBoxes.formulas.get(id);

  /// 获取所有公式
  List<Formula> getAll() => HiveBoxes.formulas.values.toList();

  /// 按分类筛选
  List<Formula> byCategory(String category) {
    return HiveBoxes.formulas.values
        .where((f) => f.category == category)
        .toList();
  }

  /// 按年级筛选
  List<Formula> byGrade(int grade) {
    return HiveBoxes.formulas.values
        .where((f) => f.grade <= grade)
        .toList();
  }

  /// 获取所有分类
  List<String> get availableCategories {
    final categories = <String>{};
    for (final f in HiveBoxes.formulas.values) {
      categories.add(f.category);
    }
    return categories.toList();
  }

  /// 搜索（名称或公式文本包含关键词）
  List<Formula> search(String keyword) {
    if (keyword.isEmpty) return [];
    final lower = keyword.toLowerCase();
    return HiveBoxes.formulas.values
        .where((f) =>
            f.name.toLowerCase().contains(lower) ||
            f.formulaText.toLowerCase().contains(lower) ||
            f.category.toLowerCase().contains(lower),)
        .toList();
  }

  /// 总公式数
  int get totalCount => HiveBoxes.formulas.length;
}
