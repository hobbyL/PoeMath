// lib/data/models/math_session.dart
//
// 层级：data/models
// 职责：口算练习会话模型。Profile-scoped。

import 'dart:convert';

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

  /// 每道题的详细记录（JSON 序列化）
  /// 格式：[{"q":"1+2=?","a":"3","u":"3","c":true}, ...]
  @HiveField(12)
  String? problemsJson;

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
    this.problemsJson,
  }) : startedAt = startedAt ?? DateTime.now();

  double get accuracy =>
      totalProblems > 0 ? correctCount / totalProblems : 0.0;

  /// 解析每道题的详细记录。
  List<ProblemRecord> get problemRecords {
    if (problemsJson == null || problemsJson!.isEmpty) return [];
    try {
      final list = jsonDecode(problemsJson!) as List<dynamic>;
      return list
          .map((e) => ProblemRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// 单道题的作答记录。
class ProblemRecord {
  /// 题目文本
  final String problemText;

  /// 正确答案
  final String answerText;

  /// 用户作答
  final String userAnswer;

  /// 是否正确
  final bool isCorrect;

  const ProblemRecord({
    required this.problemText,
    required this.answerText,
    required this.userAnswer,
    required this.isCorrect,
  });

  Map<String, dynamic> toJson() => {
        'q': problemText,
        'a': answerText,
        'u': userAnswer,
        'c': isCorrect,
      };

  factory ProblemRecord.fromJson(Map<String, dynamic> json) {
    return ProblemRecord(
      problemText: json['q'] as String? ?? '',
      answerText: json['a'] as String? ?? '',
      userAnswer: json['u'] as String? ?? '',
      isCorrect: json['c'] as bool? ?? false,
    );
  }
}
