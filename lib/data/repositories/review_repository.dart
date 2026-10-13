// lib/data/repositories/review_repository.dart
//
// 层级：data/repositories
// 职责：艾宾浩斯复习调度仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/review_schedule.dart';

class ReviewRepository {
  /// 获取某首诗的复习调度
  ReviewSchedule? get(String poemId) {
    return HiveBoxes.reviewSchedules.get(ProfileScope.key(poemId));
  }

  /// 创建或更新复习调度
  Future<void> save(ReviewSchedule schedule) async {
    final key = ProfileScope.key(schedule.poemId);
    await HiveBoxes.reviewSchedules.put(key, schedule);
  }

  /// 创建新的复习计划（首次背诵完成后调用）
  Future<ReviewSchedule> createSchedule(String poemId) async {
    final schedule = ReviewSchedule(
      poemId: poemId,
      profileId: ProfileScope.currentId,
      nextReviewDate: DateTime.now().add(
        Duration(days: ReviewSchedule.intervals[0]),
      ),
    );
    await save(schedule);
    return schedule;
  }

  /// 获取今日待复习的诗词
  List<ReviewSchedule> getDueToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return HiveBoxes.reviewSchedules.values
        .where((s) =>
            s.profileId == ProfileScope.currentId &&
            !s.isCompleted &&
            !s.nextReviewDate.isAfter(today.add(const Duration(days: 1))),)
        .toList();
  }

  /// 获取所有未完成的复习计划
  List<ReviewSchedule> getActive() {
    return HiveBoxes.reviewSchedules.values
        .where((s) =>
            s.profileId == ProfileScope.currentId && !s.isCompleted,)
        .toList();
  }

  /// 完成一次复习并按得分自适应推进。
  ///
  /// 三分层（及格线复用 QuizSession.isPassed 的 0.8 口径）：
  /// - [score] 为 null（背诵完成）或 ≥ 0.8（测试通过）：推进下一轮；
  /// - score < 0.8：不推进，`nextReviewDate` 重置明天再来一轮。
  /// 两种情况均记录 `lastScore`（null 不覆盖既有值）。
  Future<void> completeReview(String poemId, {double? score}) async {
    final schedule = get(poemId);
    if (schedule == null || schedule.isCompleted) return;

    if (score != null) {
      schedule.lastScore = score;
    }

    if (score != null && score < 0.8) {
      // 未达及格线：本轮不推进，明天重测。
      schedule.nextReviewDate = DateTime.now().add(const Duration(days: 1));
    } else {
      schedule.advanceToNextRound();
    }
    await save(schedule);
  }
}
