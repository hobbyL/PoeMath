// lib/data/models/poem_progress.dart
//
// 层级：data/models
// 职责：诗词学习进度模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'poem_progress.g.dart';

/// 学习状态枚举。
@HiveType(typeId: 20)
enum LearningStatus {
  @HiveField(0)
  notStarted,

  @HiveField(1)
  learning,

  @HiveField(2)
  reviewing,

  @HiveField(3)
  mastered,
}

@HiveType(typeId: 5)
class PoemProgress extends HiveObject {
  @HiveField(0)
  final String poemId;

  @HiveField(1)
  final String profileId;

  @HiveField(2)
  LearningStatus status;

  /// 背诵模式最高通过等级（0=未通过, 1=首字, 2=半隐, 3=全隐, 4=默写）
  @HiveField(3)
  int masteryLevel;

  /// 累计学习次数
  @HiveField(4)
  int studyCount;

  /// 最后一次学习时间
  @HiveField(5)
  DateTime? lastStudiedAt;

  /// 首次学习时间
  @HiveField(6)
  DateTime? firstStudiedAt;

  /// 获得的星星数
  @HiveField(7)
  int stars;

  PoemProgress({
    required this.poemId,
    required this.profileId,
    this.status = LearningStatus.notStarted,
    this.masteryLevel = 0,
    this.studyCount = 0,
    this.lastStudiedAt,
    this.firstStudiedAt,
    this.stars = 0,
  });
}
