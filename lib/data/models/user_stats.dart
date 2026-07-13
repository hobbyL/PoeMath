// lib/data/models/user_stats.dart
//
// 层级：data/models
// 职责：用户统计数据模型。Profile-scoped。
//       单条记录，汇总全局统计。

import 'package:hive/hive.dart';

part 'user_stats.g.dart';

@HiveType(typeId: 13)
class UserStats extends HiveObject {
  @HiveField(0)
  final String profileId;

  /// 总星星数
  @HiveField(1)
  int totalStars;

  /// 连续打卡天数
  @HiveField(2)
  int currentStreak;

  /// 最长连续打卡天数
  @HiveField(3)
  int longestStreak;

  /// 已学诗词数
  @HiveField(4)
  int poemsLearned;

  /// 已掌握诗词数
  @HiveField(5)
  int poemsMastered;

  /// 口算总做题数
  @HiveField(6)
  int mathTotalProblems;

  /// 口算总正确数
  @HiveField(7)
  int mathTotalCorrect;

  /// 等级（0=童生, 1=秀才, 2=举人, 3=进士, 4=探花, 5=榜眼, 6=状元, 7=诗仙/算神）
  @HiveField(8)
  int level;

  /// 注册日期
  @HiveField(9)
  final DateTime createdAt;

  /// 口算单次练习最佳连续答对数
  @HiveField(10)
  int mathBestStreak;

  UserStats({
    required this.profileId,
    this.totalStars = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.poemsLearned = 0,
    this.poemsMastered = 0,
    this.mathTotalProblems = 0,
    this.mathTotalCorrect = 0,
    this.level = 0,
    this.mathBestStreak = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 等级名称映射
  static const List<String> levelNames = [
    '童生',
    '秀才',
    '举人',
    '进士',
    '探花',
    '榜眼',
    '状元',
    '诗仙',
  ];

  String get levelName =>
      level < levelNames.length ? levelNames[level] : '诗仙';

  double get mathAccuracy =>
      mathTotalProblems > 0 ? mathTotalCorrect / mathTotalProblems : 0.0;
}
