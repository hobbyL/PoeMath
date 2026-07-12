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

  CheckIn({
    required this.profileId,
    required this.date,
    this.poemCount = 0,
    this.mathCorrectCount = 0,
    this.starsEarned = 0,
    this.durationSeconds = 0,
  });
}
