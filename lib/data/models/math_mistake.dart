// lib/data/models/math_mistake.dart
//
// 层级：data/models
// 职责：口算错题模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'math_mistake.g.dart';

@HiveType(typeId: 8)
class MathMistake extends HiveObject {
  @HiveField(0)
  final String id; // 自动生成 UUID

  @HiveField(1)
  final String profileId;

  /// 题目文本，如 "25 + 38 = ?"
  @HiveField(2)
  final String problemText;

  /// 正确答案
  @HiveField(3)
  final String correctAnswer;

  /// 用户给出的错误答案
  @HiveField(4)
  final String userAnswer;

  /// 题型标识（arithmetic / vertical / fraction / ...）
  @HiveField(5)
  final String problemType;

  /// 年级
  @HiveField(6)
  final int grade;

  /// 错因标识（carry / borrow / multiplication_table / order / remainder / decimal）
  @HiveField(7)
  final String? errorType;

  /// 解题步骤 JSON（序列化的 List<Map>）
  @HiveField(8)
  final String? solutionStepsJson;

  /// 创建时间
  @HiveField(9)
  final DateTime createdAt;

  /// 是否已重练通过
  @HiveField(10)
  bool isResolved;

  /// 重练次数
  @HiveField(11)
  int retryCount;

  MathMistake({
    required this.id,
    required this.profileId,
    required this.problemText,
    required this.correctAnswer,
    required this.userAnswer,
    required this.problemType,
    required this.grade,
    this.errorType,
    this.solutionStepsJson,
    DateTime? createdAt,
    this.isResolved = false,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();
}
