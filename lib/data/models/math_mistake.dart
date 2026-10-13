// lib/data/models/math_mistake.dart
//
// 层级：data/models
// 职责：口算错题模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'math_mistake.g.dart';

@HiveType(typeId: 8)
class MathMistake extends HiveObject {
  @HiveField(0)
  String id; // 题面归一化 key（迁移期由旧 id 改写）

  @HiveField(1)
  final String profileId;

  /// 题目文本，如 "25 + 38 = ?"
  @HiveField(2)
  final String problemText;

  /// 正确答案
  @HiveField(3)
  final String correctAnswer;

  /// 用户给出的错误答案（同题再错时被最近一次作答覆盖）
  @HiveField(4)
  String userAnswer;

  /// 题型标识（arithmetic / vertical / fraction / ...）
  @HiveField(5)
  String problemType;

  /// 年级
  @HiveField(6)
  int grade;

  /// 错因标识（carry / borrow / multiplication_table / order / remainder / decimal）
  @HiveField(7)
  String? errorType;

  /// 解题步骤 JSON（序列化的 List<Map>）
  @HiveField(8)
  String? solutionStepsJson;

  /// 创建时间
  @HiveField(9)
  final DateTime createdAt;

  /// 是否已重练通过
  @HiveField(10)
  bool isResolved;

  /// 重练次数
  @HiveField(11)
  int retryCount;

  /// 累计答错次数（同题面聚合，每次答错 +1）
  @HiveField(12)
  int wrongCount;

  /// 最近一次答错时间（旧数据迁移时回填 createdAt）
  @HiveField(13)
  DateTime? lastWrongAt;

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
    this.wrongCount = 1,
    this.lastWrongAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
