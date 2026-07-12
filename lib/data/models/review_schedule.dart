// lib/data/models/review_schedule.dart
//
// 层级：data/models
// 职责：艾宾浩斯复习调度模型。Profile-scoped。

import 'package:hive/hive.dart';

part 'review_schedule.g.dart';

@HiveType(typeId: 7)
class ReviewSchedule extends HiveObject {
  @HiveField(0)
  final String poemId;

  @HiveField(1)
  final String profileId;

  /// 当前处于艾宾浩斯第几轮（0=未开始, 1=1天, 2=3天, 3=7天, 4=14天, 5=30天）
  @HiveField(2)
  int currentRound;

  /// 下次复习日期
  @HiveField(3)
  DateTime nextReviewDate;

  /// 上次复习日期
  @HiveField(4)
  DateTime? lastReviewedAt;

  /// 是否已完成全部 5 轮复习
  @HiveField(5)
  bool isCompleted;

  ReviewSchedule({
    required this.poemId,
    required this.profileId,
    this.currentRound = 0,
    required this.nextReviewDate,
    this.lastReviewedAt,
    this.isCompleted = false,
  });

  /// 艾宾浩斯间隔天数：1, 3, 7, 14, 30
  static const List<int> intervals = [1, 3, 7, 14, 30];

  /// 推进到下一轮复习
  void advanceToNextRound() {
    lastReviewedAt = DateTime.now();
    currentRound++;
    if (currentRound >= intervals.length) {
      isCompleted = true;
    } else {
      nextReviewDate = DateTime.now().add(
        Duration(days: intervals[currentRound]),
      );
    }
  }
}
