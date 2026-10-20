import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/poem_identity.dart';

/// 先持久化确定的目标快照，再写目标和删别名；崩溃后不重新累加。
class PoemIdentityMigration {
  const PoemIdentityMigration._();
  static const pendingKey = 'poem_identity_pending_v1';

  static Future<void> run() async {
    final pending = HiveBoxes.meta.get(pendingKey);
    if (pending is Map) await _apply(Map<String, dynamic>.from(pending));
    final sources = <String, List<Map<String, dynamic>>>{
      'progress':
          HiveBoxes.poemProgress.values.map(PoemIdentity.progressMap).toList(),
      'favorite':
          HiveBoxes.poemFavorites.values.map(PoemIdentity.favoriteMap).toList(),
      'review':
          HiveBoxes.reviewSchedules.values.map(PoemIdentity.reviewMap).toList(),
    };
    for (final entry in sources.entries) {
      final affected = entry.value
          .where((m) => PoemIdentity.aliases.containsKey(m['poemId']))
          .map(
            (m) =>
                '${m['profileId']}_${PoemIdentity.canonical(m['poemId'] as String)}',
          )
          .toSet();
      for (final key in affected) {
        final group = entry.value
            .where(
              (m) =>
                  '${m['profileId']}_${PoemIdentity.canonical(m['poemId'] as String)}' ==
                  key,
            )
            .toList();
        final plan = <String, dynamic>{
          'kind': entry.key,
          'key': key,
          'value': PoemIdentity.merge(entry.key, group).single,
          'delete': group
              .where((m) => PoemIdentity.aliases.containsKey(m['poemId']))
              .map((m) => '${m['profileId']}_${m['poemId']}')
              .toList(),
        };
        await HiveBoxes.meta.put(pendingKey, plan);
        await _apply(plan);
      }
    }
    // 历史活动保留原 ID 和结算标记；外键在读取/比较时归一化即可。
    await refreshCounts();
  }

  static Future<void> _apply(Map<String, dynamic> plan) async {
    final m = Map<String, dynamic>.from(plan['value'] as Map);
    final deletes = (plan['delete'] as List).cast<String>();
    switch (plan['kind']) {
      case 'progress':
        await HiveBoxes.poemProgress.put(plan['key'], PoemIdentity.progress(m));
        await HiveBoxes.poemProgress.deleteAll(deletes);
      case 'favorite':
        await HiveBoxes.poemFavorites
            .put(plan['key'], PoemIdentity.favorite(m));
        await HiveBoxes.poemFavorites.deleteAll(deletes);
      case 'review':
        await HiveBoxes.reviewSchedules
            .put(plan['key'], PoemIdentity.review(m));
        await HiveBoxes.reviewSchedules.deleteAll(deletes);
    }
    await HiveBoxes.meta.delete(pendingKey);
  }

  static Future<void> refreshCounts() async {
    for (final entry in HiveBoxes.userStats.toMap().entries) {
      final s = entry.value.copy();
      final records = HiveBoxes.poemProgress.values
          .where((p) => p.profileId == s.profileId);
      s.poemsLearned =
          records.where((p) => p.status != LearningStatus.notStarted).length;
      s.poemsMastered =
          records.where((p) => p.status == LearningStatus.mastered).length;
      await HiveBoxes.userStats.put(entry.key, s);
    }
  }
}
