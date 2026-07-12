// lib/data/repositories/formula_favorite_repository.dart
//
// 层级：data/repositories
// 职责：公式收藏仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula_favorite.dart';

class FormulaFavoriteRepository {
  /// 判断是否已收藏
  bool isFavorite(String formulaId) {
    return HiveBoxes.formulaFavorites
        .containsKey(ProfileScope.key(formulaId));
  }

  /// 切换收藏状态
  Future<bool> toggle(String formulaId) async {
    final key = ProfileScope.key(formulaId);
    if (HiveBoxes.formulaFavorites.containsKey(key)) {
      await HiveBoxes.formulaFavorites.delete(key);
      return false;
    } else {
      final fav = FormulaFavorite(
        formulaId: formulaId,
        profileId: ProfileScope.currentId,
      );
      await HiveBoxes.formulaFavorites.put(key, fav);
      return true;
    }
  }

  /// 获取所有收藏的公式 ID
  List<String> getFavoriteIds() {
    return HiveBoxes.formulaFavorites.values
        .where((f) => f.profileId == ProfileScope.currentId)
        .map((f) => f.formulaId)
        .toList();
  }

  /// 收藏总数
  int get count {
    return HiveBoxes.formulaFavorites.values
        .where((f) => f.profileId == ProfileScope.currentId)
        .length;
  }
}
