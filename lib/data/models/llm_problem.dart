// lib/data/models/llm_problem.dart
//
// 层级：data/models
// 职责：家长确认后的应用题入库模型（typeId 16）。Profile-scoped。
//       新题的数学内容、题面和讲解来自本地计划与模板；
//       generationMetadataJson 为空的历史题保留旧数据。

import 'package:hive/hive.dart';

part 'llm_problem.g.dart';

@HiveType(typeId: 16)
class LlmProblem extends HiveObject {
  /// 唯一 ID（毫秒时间戳 + 序号）。
  @HiveField(0)
  final String id;

  /// 所属 profile ID。
  @HiveField(1)
  final String profileId;

  /// 题面文本（新题由本地关系模板生成）。
  @HiveField(2)
  final String questionText;

  /// 答案单位。
  @HiveField(3)
  final String unit;

  /// 操作数（本地生成器）。
  @HiveField(4)
  final List<int> operands;

  /// 运算符（本地生成器，'+'/'-'/'×'/'÷'）。
  @HiveField(5)
  final List<String> operators;

  /// 答案（本地生成器）。
  @HiveField(6)
  final int answer;

  /// 解题讲解（新题由本地数量关系推导）。
  @HiveField(7)
  final String explanation;

  /// 生成批次 ID（一次批量生成一批）。
  @HiveField(8)
  final String batchId;

  /// 入库时间。
  @HiveField(9)
  final DateTime createdAt;

  /// 年级（1-6）。
  @HiveField(10)
  final int grade;

  /// 学期（'上'/'下'）。
  @HiveField(11)
  final String semester;

  /// 知识点（addition/subtraction/multiplication/division/mixed）。
  @HiveField(12)
  final String topic;

  /// 难度（1-5）。
  @HiveField(13)
  final int difficulty;

  /// 是否已做过。
  @HiveField(14)
  bool done;

  /// 做题次数。
  @HiveField(15)
  int attempts;

  /// 答对次数。
  @HiveField(16)
  int correctCount;

  /// 最近一次做题时间。
  @HiveField(17)
  DateTime? lastDoneAt;

  /// 与业务值同次落盘的活动结算事实，避免 meta 写入失败后重复累加。
  @HiveField(18, defaultValue: <String>[])
  List<String> appliedActivityIds;

  /// 版本化本地题意快照，空字符串表示旧版自由题面。
  @HiveField(19, defaultValue: '')
  final String generationMetadataJson;

  LlmProblem({
    required this.id,
    required this.profileId,
    required this.questionText,
    required this.unit,
    required this.operands,
    required this.operators,
    required this.answer,
    required this.explanation,
    required this.batchId,
    required this.createdAt,
    required this.grade,
    required this.semester,
    required this.topic,
    required this.difficulty,
    this.done = false,
    this.attempts = 0,
    this.correctCount = 0,
    this.lastDoneAt,
    List<String> appliedActivityIds = const [],
    this.generationMetadataJson = '',
  }) : appliedActivityIds = List.of(appliedActivityIds);

  /// 组装算式显示文本（如 "12 + 4 = ?"）。
  Map<String, dynamic> toSnapshot() => {
        'id': id,
        'profileId': profileId,
        'questionText': questionText,
        'unit': unit,
        'operands': operands,
        'operators': operators,
        'answer': answer,
        'explanation': explanation,
        'batchId': batchId,
        'createdAt': createdAt.toIso8601String(),
        'grade': grade,
        'semester': semester,
        'topic': topic,
        'difficulty': difficulty,
        'done': done,
        'attempts': attempts,
        'correctCount': correctCount,
        'lastDoneAt': lastDoneAt?.toIso8601String(),
        'appliedActivityIds': appliedActivityIds,
        'generationMetadataJson': generationMetadataJson,
      };

  factory LlmProblem.fromSnapshot(Map<String, dynamic> json) => LlmProblem(
        id: json['id'] as String,
        profileId: json['profileId'] as String,
        questionText: json['questionText'] as String,
        unit: json['unit'] as String,
        operands: (json['operands'] as List<dynamic>).cast<int>(),
        operators: (json['operators'] as List<dynamic>).cast<String>(),
        answer: json['answer'] as int,
        explanation: json['explanation'] as String,
        batchId: json['batchId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        grade: json['grade'] as int,
        semester: json['semester'] as String,
        topic: json['topic'] as String,
        difficulty: json['difficulty'] as int,
        done: json['done'] as bool? ?? false,
        attempts: json['attempts'] as int? ?? 0,
        correctCount: json['correctCount'] as int? ?? 0,
        lastDoneAt: DateTime.tryParse(json['lastDoneAt'] as String? ?? ''),
        appliedActivityIds:
            (json['appliedActivityIds'] as List<dynamic>? ?? []).cast<String>(),
        generationMetadataJson: json['generationMetadataJson'] as String? ?? '',
      );

  /// 组装算式显示文本（如 "12 + 4 = ?"）。
  String get expressionText {
    final buffer = StringBuffer(operands.first.toString());
    for (var i = 0; i < operators.length; i++) {
      buffer.write(' ${operators[i]} ${operands[i + 1]}');
    }
    return buffer.toString();
  }
}
