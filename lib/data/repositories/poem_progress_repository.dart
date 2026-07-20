// lib/data/repositories/poem_progress_repository.dart
//
// 层级：data/repositories
// 职责：诗词学习进度仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem_progress.dart';

class PoemProgressRepository {
  /// 获取某首诗的进度
  PoemProgress? get(String poemId) {
    return HiveBoxes.poemProgress.get(ProfileScope.key(poemId));
  }

  /// 创建或更新进度
  Future<void> save(PoemProgress progress) async {
    final key = ProfileScope.key(progress.poemId);
    await HiveBoxes.poemProgress.put(key, progress);
  }

  /// 获取当前 profile 的所有进度
  List<PoemProgress> getAll() {
    return HiveBoxes.poemProgress.values
        .where((p) => p.profileId == ProfileScope.currentId)
        .toList();
  }

  /// 获取某状态的诗词进度列表
  List<PoemProgress> byStatus(LearningStatus status) {
    return getAll().where((p) => p.status == status).toList();
  }

  /// 已学习的诗词数
  int get learnedCount {
    return getAll()
        .where((p) => p.status != LearningStatus.notStarted)
        .length;
  }

  /// 已掌握的诗词数
  int get masteredCount {
    return getAll()
        .where((p) => p.status == LearningStatus.mastered)
        .length;
  }

  /// 今日学习的诗词数（按 lastStudiedAt 日期判断）
  int get todayStudiedCount {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return getAll()
        .where(
          (p) =>
              p.lastStudiedAt != null &&
              p.lastStudiedAt!.isAfter(todayStart),
        )
        .length;
  }

  /// 记录一次学习
  Future<PoemProgress> recordStudy(String poemId) async {
    return _recordStudy(poemId);
  }

  /// 记录完成一次背诵，并保留历史最高背诵等级（1-4）。
  Future<PoemProgress> recordRecitation(
    String poemId, {
    required int level,
  }) async {
    if (level < 1 || level > 4) {
      throw RangeError.range(level, 1, 4, 'level');
    }
    return _recordStudy(poemId, recitationLevel: level);
  }

  Future<PoemProgress> _recordStudy(
    String poemId, {
    int? recitationLevel,
  }) async {
    var progress = get(poemId);
    progress ??= PoemProgress(
      poemId: poemId,
      profileId: ProfileScope.currentId,
      status: LearningStatus.learning,
      firstStudiedAt: DateTime.now(),
    );
    progress.studyCount++;
    progress.lastStudiedAt = DateTime.now();
    if (progress.status == LearningStatus.notStarted) {
      progress.status = LearningStatus.learning;
    }
    if (recitationLevel != null &&
        recitationLevel > progress.masteryLevel) {
      progress.masteryLevel = recitationLevel;
    }
    await save(progress);
    return progress;
  }

  /// 删除某首诗的进度
  Future<void> delete(String poemId) async {
    final key = ProfileScope.key(poemId);
    await HiveBoxes.poemProgress.delete(key);
  }
}
