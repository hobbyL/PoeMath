// lib/data/models/check_in.dart
//
// 层级：data/models
// 职责：每日打卡模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'check_in.g.dart';

@HiveType(typeId: 12)
class CheckIn extends HiveObject {
  @HiveField(0)
  final String profileId;

  /// 打卡日期（yyyy-MM-dd 格式的字符串，作为 key 的一部分）
  @HiveField(1)
  final String date;

  /// 当天学习诗词数
  @HiveField(2)
  int poemCount;

  /// 当天口算正确数
  @HiveField(3)
  int mathCorrectCount;

  /// 当天获得的星星
  @HiveField(4)
  int starsEarned;

  /// 当天学习时长（秒）
  @HiveField(5)
  int durationSeconds;

  /// 是否已完成手动打卡。旧版记录均由手动打卡创建，缺失时默认为 true。
  @HiveField(6, defaultValue: true)
  bool isCheckedIn;

  /// 当天口算总题数。
  @HiveField(7, defaultValue: 0)
  int mathTotalCount;

  /// 每日活动已聚合来源的位掩码。0 表示旧记录，需要从历史明细回退计算。
  @HiveField(8, defaultValue: 0)
  int activitySources;

  static const int poemActivitySource = 1;
  static const int mathActivitySource = 2;

  CheckIn({
    required this.profileId,
    required this.date,
    this.poemCount = 0,
    this.mathCorrectCount = 0,
    this.starsEarned = 0,
    this.durationSeconds = 0,
    this.isCheckedIn = true,
    this.mathTotalCount = 0,
    this.activitySources = 0,
  });

  bool get hasPoemActivitySummary =>
      activitySources & poemActivitySource != 0;

  bool get hasMathActivitySummary =>
      activitySources & mathActivitySource != 0;

  bool get hasActivitySummary => activitySources != 0;

  /// 旧版曾把总题数写入 mathCorrectCount，日历展示时保留兼容。
  int get legacyCompatibleMathTotalCount =>
      hasActivitySummary ? mathTotalCount : mathCorrectCount;
}
