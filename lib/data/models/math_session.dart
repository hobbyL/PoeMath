// lib/data/models/math_session.dart
//
// 层级：data/models
// 职责：口算练习会话模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'math_session.g.dart';

@HiveType(typeId: 9)
class MathSession extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String profileId;

  /// 年级
  @HiveField(2)
  final int grade;

  /// 题型标识
  @HiveField(3)
  final String problemType;

  /// 总题数
  @HiveField(4)
  final int totalProblems;

  /// 正确数
  @HiveField(5)
  int correctCount;

  /// 用时（秒）
  @HiveField(6)
  int durationSeconds;

  /// 获得的星星
  @HiveField(7)
  int starsEarned;

  /// 开始时间
  @HiveField(8)
  final DateTime startedAt;

  /// 结束时间
  @HiveField(9)
  DateTime? finishedAt;

  /// 学期（'上' 或 '下'）
  @HiveField(10)
  String? semester;

  /// 难度（'easy' / 'medium' / 'hard'）
  @HiveField(11)
  String? difficulty;

  MathSession({
    required this.id,
    required this.profileId,
    required this.grade,
    required this.problemType,
    required this.totalProblems,
    this.correctCount = 0,
    this.durationSeconds = 0,
    this.starsEarned = 0,
    DateTime? startedAt,
    this.finishedAt,
    this.semester,
    this.difficulty,
  }) : startedAt = startedAt ?? DateTime.now();

  double get accuracy =>
      totalProblems > 0 ? correctCount / totalProblems : 0.0;
}
