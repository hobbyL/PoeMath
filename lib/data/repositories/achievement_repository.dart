// lib/data/repositories/achievement_repository.dart
//
// 层级：data/repositories
// 职责：成就勋章仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/achievement.dart';

class AchievementRepository {
  /// 按 ID 获取
  Achievement? getById(String id) {
    return HiveBoxes.achievements.get(ProfileScope.key(id));
  }

  /// 保存/更新成就
  Future<void> save(Achievement achievement) async {
    final key = ProfileScope.key(achievement.id);
    await HiveBoxes.achievements.put(key, achievement);
  }

  /// 获取当前 profile 所有成就
  List<Achievement> getAll() {
    return HiveBoxes.achievements.values
        .where((a) => a.profileId == ProfileScope.currentId)
        .toList();
  }

  /// 获取已解锁的成就
  List<Achievement> getUnlocked() {
    return getAll().where((a) => a.isUnlocked).toList();
  }

  /// 解锁成就
  Future<void> unlock(String id) async {
    final achievement = getById(id);
    if (achievement == null) return;
    if (achievement.isUnlocked) return;
    achievement.isUnlocked = true;
    achievement.unlockedAt = DateTime.now();
    achievement.progress = 1.0;
    await achievement.save();
  }

  /// 更新进度
  Future<void> updateProgress(String id, double progress) async {
    final achievement = getById(id);
    if (achievement == null) return;
    achievement.progress = progress.clamp(0.0, 1.0);
    if (progress >= 1.0 && !achievement.isUnlocked) {
      achievement.isUnlocked = true;
      achievement.unlockedAt = DateTime.now();
    }
    await achievement.save();
  }

  /// 已解锁成就数
  int get unlockedCount => getUnlocked().length;
}
