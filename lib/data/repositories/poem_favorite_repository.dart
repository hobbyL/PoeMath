// lib/data/repositories/poem_favorite_repository.dart
//
// 层级：data/repositories
// 职责：诗词收藏仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem_favorite.dart';

class PoemFavoriteRepository {
  /// 判断是否已收藏
  bool isFavorite(String poemId) {
    return HiveBoxes.poemFavorites.containsKey(ProfileScope.key(poemId));
  }

  /// 切换收藏状态（收藏/取消收藏）
  Future<bool> toggle(String poemId) async {
    final key = ProfileScope.key(poemId);
    if (HiveBoxes.poemFavorites.containsKey(key)) {
      await HiveBoxes.poemFavorites.delete(key);
      return false; // 取消收藏
    } else {
      final fav = PoemFavorite(
        poemId: poemId,
        profileId: ProfileScope.currentId,
      );
      await HiveBoxes.poemFavorites.put(key, fav);
      return true; // 已收藏
    }
  }

  /// 获取所有收藏
  List<PoemFavorite> getAll() {
    return HiveBoxes.poemFavorites.values
        .where((f) => f.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取收藏的诗词 ID 列表
  List<String> getFavoriteIds() {
    return getAll().map((f) => f.poemId).toList();
  }

  /// 收藏总数
  int get count => getAll().length;
}
