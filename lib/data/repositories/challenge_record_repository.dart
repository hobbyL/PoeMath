// lib/data/repositories/challenge_record_repository.dart
//
// 层级：data/repositories
// 职责：挑战记录仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/challenge_record.dart';

class ChallengeRecordRepository {
  /// 保存挑战记录
  Future<void> save(ChallengeRecord record) async {
    final key = ProfileScope.key(record.id);
    await HiveBoxes.challengeRecords.put(key, record);
  }

  /// 获取当前 profile 的所有记录（按时间倒序）
  List<ChallengeRecord> getAll() {
    return HiveBoxes.challengeRecords.values
        .where((r) => r.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取最近 N 条记录
  List<ChallengeRecord> getRecent({int limit = 10}) {
    final all = getAll();
    return all.take(limit).toList();
  }

  /// 按模式筛选
  List<ChallengeRecord> getByMode(String mode) {
    return getAll().where((r) => r.mode == mode).toList();
  }

  /// 某模式的最高分
  int? bestScore(String mode) {
    final records = getByMode(mode);
    if (records.isEmpty) return null;
    return records.map((r) => r.score).reduce((a, b) => a > b ? a : b);
  }
}
