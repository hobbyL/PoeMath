// lib/data/models/achievement.dart
//
// 层级：data/models
// 职责：成就勋章模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'achievement.g.dart';

@HiveType(typeId: 11)
class Achievement extends HiveObject {
  @HiveField(0)
  final String id; // 如 'streak_7', 'poems_100', 'math_master'

  @HiveField(1)
  final String profileId;

  /// 成就名称
  @HiveField(2)
  final String title;

  /// 描述
  @HiveField(3)
  final String description;

  /// 图标名
  @HiveField(4)
  final String iconName;

  /// 是否已解锁
  @HiveField(5)
  bool isUnlocked;

  /// 解锁时间
  @HiveField(6)
  DateTime? unlockedAt;

  /// 进度（0.0 ~ 1.0），用于显示进度条
  @HiveField(7)
  double progress;

  Achievement({
    required this.id,
    required this.profileId,
    required this.title,
    this.description = '',
    this.iconName = 'trophy',
    this.isUnlocked = false,
    this.unlockedAt,
    this.progress = 0.0,
  });
}
