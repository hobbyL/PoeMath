// lib/data/models/learning_activity.dart
//
// 层级：data/models
// 职责：记录一次已完成学习活动的不可变历史事实。Profile-scoped。

import 'package:hive/hive.dart';

import 'package:poemath/domain/learning_reward_calculator.dart';

part 'learning_activity.g.dart';

@HiveType(typeId: 15)
class LearningActivity extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String profileId;

  /// [LearningActivityType.name]，使用字符串保证 Hive 枚举兼容性。
  @HiveField(2)
  final String activityType;

  /// 本次活动的总题数或总质量分。
  @HiveField(3)
  final int totalItems;

  /// 本次活动的正确题数或获得的质量分。
  @HiveField(4)
  final int successfulItems;

  /// 诗词类活动对应的诗词 ID。
  @HiveField(5)
  final String? poemId;

  @HiveField(6)
  final int starsEarned;

  @HiveField(7)
  final int durationSeconds;

  @HiveField(8)
  final DateTime completedAt;

  LearningActivity({
    required this.id,
    required this.profileId,
    required this.activityType,
    required this.totalItems,
    required this.successfulItems,
    required this.starsEarned,
    required this.durationSeconds,
    required this.completedAt,
    this.poemId,
  });

  LearningActivityType? get typeOrNull {
    for (final type in LearningActivityType.values) {
      if (type.name == activityType) return type;
    }
    return null;
  }

  LearningActivityType get type =>
      typeOrNull ?? (throw StateError('未知学习活动类型：$activityType'));
}
