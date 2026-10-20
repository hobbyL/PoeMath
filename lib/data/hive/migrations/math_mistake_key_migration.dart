// lib/data/hive/migrations/math_mistake_key_migration.dart
//
// 层级：data/hive/migrations
// 职责：错题 id 迁移为题面归一化 key 的一次性迁移。
//       同题面多条合并计数；meta box 版本标记保证幂等；
//       异常记日志不阻断启动（下次启动重试）。
//
// 合并字段口径：
//   createdAt   取组内最早（首次答错时间）
//   wrongCount  = 组内已累计的答错次数之和（旧记录默认一次）
//   lastWrongAt 取组内最晚的 lastWrongAt ?? createdAt
//   retryCount  取组内最大
//   作答快照（userAnswer / errorType / grade / problemType / 解题步骤）与
//   掌握状态取最近一条，与 recordWrong 的「最近一次覆盖」语义一致
//   —— 旧记录的已掌握不应覆盖后来的再次答错。

import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';

class MathMistakeKeyMigration {
  const MathMistakeKeyMigration._();

  static const String _tag = 'MathMistakeKeyMigration';

  static Future<void> run() async {
    final metaBox = HiveBoxes.meta;
    if (metaBox.get(HiveKeys.metaMistakeKeyMigrated) == true) return;

    try {
      final stats = await _migrate();
      AppLogger.d(
        '错题 key 迁移完成：合并 ${stats.$1} 组、重写 ${stats.$2} 条',
        tag: _tag,
      );
      await metaBox.put(HiveKeys.metaMistakeKeyMigrated, true);
    } catch (error, stack) {
      // 迁移失败不阻断启动；未置位版本标记，下次启动重试。
      AppLogger.e(
        '错题 key 迁移失败，将在下次启动重试',
        tag: _tag,
        error: error,
        stackTrace: stack,
      );
    }
  }

  /// 返回 (合并组数, 单条重写数)。
  static Future<(int, int)> _migrate() async {
    final box = HiveBoxes.mathMistakes;

    // 先收集再改动：遍历过程中不修改 box。
    final entries = <MapEntry<dynamic, MathMistake>>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) entries.add(MapEntry(key, value));
    }

    // 同 profile 内按归一化 key 分组；不跨 profile 合并。
    final groups = <String, List<MapEntry<dynamic, MathMistake>>>{};
    for (final entry in entries) {
      groups.putIfAbsent(_groupKey(entry.value), () => []).add(entry);
    }

    var mergedGroups = 0;
    var rewrittenSingles = 0;

    for (final group in groups.values) {
      // 升序：首条 = 最早答错，末条 = 最近一次作答。
      group.sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      final earliest = group.first.value;
      final latest = group.last.value;
      final newId = MathMistakeRepository.problemKey(
        problemText: earliest.problemText,
        correctAnswer: earliest.correctAnswer,
      );

      // HiveObject 实例与 key 绑定（同实例换 key 会抛 HiveError），
      // 因此换 key 必须换实例：先删旧 key 释放旧实例，再写入聚合拷贝。
      final migrated = MathMistake(
        id: newId,
        appliedActivityIds:
            group.expand((e) => e.value.appliedActivityIds).toSet().toList(),
        profileId: earliest.profileId,
        problemText: earliest.problemText,
        correctAnswer: earliest.correctAnswer,
        userAnswer: latest.userAnswer,
        problemType: latest.problemType,
        grade: latest.grade,
        errorType: latest.errorType,
        solutionStepsJson: latest.solutionStepsJson,
        skillId: latest.skillId,
        semester: latest.semester,
        problemJson: latest.problemJson,
        attemptJson: latest.attemptJson,
        createdAt: earliest.createdAt,
        isResolved: latest.isResolved,
        retryCount: group
            .map((e) => e.value.retryCount)
            .reduce((a, b) => a > b ? a : b),
        wrongCount: group.fold(0, (sum, e) => sum + e.value.wrongCount),
        consolidationRound: latest.consolidationRound,
        nextConsolidationDate: latest.nextConsolidationDate,
        lastWrongAt: group
            .map((e) => e.value.lastWrongAt ?? e.value.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
      );

      await box.deleteAll(group.map((e) => e.key).toList());
      await box.put('${migrated.profileId}_$newId', migrated);

      if (group.length > 1) {
        mergedGroups++;
      } else {
        rewrittenSingles++;
      }
    }

    return (mergedGroups, rewrittenSingles);
  }

  static String _groupKey(MathMistake mistake) {
    final key = MathMistakeRepository.problemKey(
      problemText: mistake.problemText,
      correctAnswer: mistake.correctAnswer,
    );
    return '${mistake.profileId}|$key';
  }
}
