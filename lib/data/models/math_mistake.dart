// lib/data/models/math_mistake.dart
//
// 层级：data/models
// 职责：口算错题模型。Profile-scoped。

import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:poemath/data/models/math_textbook_session_context.dart';

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

  /// 巩固轮次 0-3（0 = 未掌握，1-3 = 已通过第 N 关抽查）
  @HiveField(14)
  int consolidationRound;

  /// 下次抽查到期日
  @HiveField(15)
  DateTime? nextConsolidationDate;

  @HiveField(16)
  String? skillId;

  @HiveField(17)
  String? semester;

  @HiveField(18)
  String? problemJson;

  @HiveField(19)
  String? attemptJson;

  /// 与业务值同次落盘的活动结算事实，避免 meta 写入失败后重复累加。
  @HiveField(20, defaultValue: <String>[])
  List<String> appliedActivityIds;

  /// 本版本起的逐次重练结果；旧记录没有可恢复的历史，默认空列表。
  @HiveField(21, defaultValue: '[]')
  String repracticeHistoryJson;

  @HiveField(22, defaultValue: '[]')
  String textbookSourcesJson;

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
    this.consolidationRound = 0,
    this.nextConsolidationDate,
    this.skillId,
    this.semester,
    this.problemJson,
    this.attemptJson,
    List<String> appliedActivityIds = const [],
    this.repracticeHistoryJson = '[]',
    this.textbookSourcesJson = '[]',
  }) : createdAt = createdAt ?? DateTime.now(),
       appliedActivityIds = List.of(appliedActivityIds);

  static List<MathTextbookSessionContext> decodeTextbookSources(
    String encoded,
  ) {
    if (utf8.encode(encoded).length > 1024 * 1024) {
      throw const FormatException('教材错题来源超过容量');
    }
    final raw = jsonDecode(encoded);
    if (raw is! List || raw.length > 20) {
      throw const FormatException('教材错题来源数量无效');
    }
    return List.unmodifiable(raw.map(MathTextbookSessionContext.fromJson));
  }

  List<MathTextbookSessionContext> get textbookSources =>
      decodeTextbookSources(textbookSourcesJson);

  void addTextbookSource(MathTextbookSessionContext source) {
    final valid = MathTextbookSessionContext.fromJson(source.toJson());
    final sources = textbookSources
        .where(
          (previous) =>
              !(previous.bookId == valid.bookId &&
                  previous.editionId == valid.editionId &&
                  previous.lessonDigest == valid.lessonDigest &&
                  previous.planId == valid.planId &&
                  previous.item.exercise.id == valid.item.exercise.id),
        )
        .toList();
    sources.insert(0, valid);
    final encoded = jsonEncode(
      sources.take(20).map((source) => source.toJson()).toList(),
    );
    decodeTextbookSources(encoded);
    textbookSourcesJson = encoded;
  }

  List<MathRepracticeResult> get repracticeHistory {
    final decoded = jsonDecode(repracticeHistoryJson);
    if (decoded is! List) throw const FormatException('错题重练记录格式无效');
    return List.unmodifiable(decoded.map(MathRepracticeResult.fromJson));
  }

  void appendRepracticeResult({
    required bool isCorrect,
    required DateTime completedAt,
  }) {
    final history = repracticeHistory.toList()
      ..add(
        MathRepracticeResult(isCorrect: isCorrect, completedAt: completedAt),
      );
    repracticeHistoryJson = jsonEncode(
      history.map((result) => result.toJson()).toList(),
    );
  }

  MathMistake copy() => MathMistake(
    id: id,
    profileId: profileId,
    problemText: problemText,
    correctAnswer: correctAnswer,
    userAnswer: userAnswer,
    problemType: problemType,
    grade: grade,
    errorType: errorType,
    solutionStepsJson: solutionStepsJson,
    createdAt: createdAt,
    isResolved: isResolved,
    retryCount: retryCount,
    wrongCount: wrongCount,
    lastWrongAt: lastWrongAt,
    consolidationRound: consolidationRound,
    nextConsolidationDate: nextConsolidationDate,
    skillId: skillId,
    semester: semester,
    problemJson: problemJson,
    attemptJson: attemptJson,
    appliedActivityIds: List.of(appliedActivityIds),
    repracticeHistoryJson: repracticeHistoryJson,
    textbookSourcesJson: textbookSourcesJson,
  );

  // ============ 派生状态（单一真相源：isResolved + consolidationRound）============

  /// 待巩固：已答对过但还没通过全部抽查。
  bool get isConsolidating => !isResolved && consolidationRound > 0;

  /// 未掌握：还没答对过（或抽查答错被打回）。
  bool get isUnmastered => !isResolved && consolidationRound == 0;

  /// 今日可练：待巩固且抽查到期（按天比较，当天到期即算）。
  bool get isConsolidationDue {
    if (!isConsolidating) return false;
    final due = nextConsolidationDate;
    if (due == null) return true;
    final now = DateTime.now();
    return !DateTime(
      due.year,
      due.month,
      due.day,
    ).isAfter(DateTime(now.year, now.month, now.day));
  }
}

class MathRepracticeResult {
  const MathRepracticeResult({
    required this.isCorrect,
    required this.completedAt,
  });

  final bool isCorrect;
  final DateTime completedAt;

  Map<String, Object> toJson() => {
    'isCorrect': isCorrect,
    'completedAt': completedAt.toIso8601String(),
  };

  factory MathRepracticeResult.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['isCorrect'] is! bool ||
        value['completedAt'] is! String) {
      throw const FormatException('错题重练记录内容无效');
    }
    final completedAt = DateTime.tryParse(value['completedAt'] as String);
    if (completedAt == null) throw const FormatException('错题重练时间无效');
    return MathRepracticeResult(
      isCorrect: value['isCorrect'] as bool,
      completedAt: completedAt,
    );
  }
}
