// lib/data/models/challenge_record.dart
//
// 层级：data/models
// 职责：挑战模式记录模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'challenge_record.g.dart';

@HiveType(typeId: 14)
class ChallengeRecord extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  final String id;

  /// 所属 profile
  @HiveField(1)
  final String profileId;

  /// 挑战模式：'fixed'（固定时间）或 'extending'（续命模式）
  @HiveField(2)
  final String mode;

  /// 得分
  @HiveField(3)
  final int score;

  /// 总答题数
  @HiveField(4)
  final int totalAnswered;

  /// 正确数
  @HiveField(5)
  final int correctCount;

  /// 最佳连击
  @HiveField(6)
  final int bestCombo;

  /// 年级
  @HiveField(7)
  final int grade;

  /// 学期（'上' / '下'）
  @HiveField(8)
  final String semester;

  /// 难度（'easy' / 'medium' / 'hard'）
  @HiveField(9)
  final String difficulty;

  /// 实际用时（秒）
  @HiveField(10)
  final int durationSeconds;

  /// 创建时间
  @HiveField(11)
  final DateTime createdAt;

  /// 本次挑战获得的星星
  @HiveField(12, defaultValue: 0)
  final int starsEarned;

  ChallengeRecord({
    required this.id,
    required this.profileId,
    required this.mode,
    required this.score,
    required this.totalAnswered,
    required this.correctCount,
    required this.bestCombo,
    required this.grade,
    required this.semester,
    required this.difficulty,
    required this.durationSeconds,
    this.starsEarned = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 正确率
  double get accuracy =>
      totalAnswered > 0 ? correctCount / totalAnswered : 0.0;

  /// 模式标签
  String get modeLabel => mode == 'fixed' ? '固定时间' : '续命模式';
}
