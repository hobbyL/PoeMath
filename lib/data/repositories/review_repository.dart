// lib/data/repositories/review_repository.dart
//
// 层级：data/repositories
// 职责：艾宾浩斯复习调度仓储。Profile-scoped。

import 'dart:async';

import 'package:poemath/data/poem_identity.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/domain/poem_review_history.dart';

class ReviewRepository {
  static final Map<String, Future<void>> _pending = {};

  List<ReviewSchedule> getAll() => HiveBoxes.reviewSchedules.values
      .where((schedule) => schedule.profileId == ProfileScope.currentId)
      .toList();

  /// 真实通过事件；旧记录没有事件明细时不按轮数补造次数。
  List<CompletedPoemReview> completedReviewsBetween(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    if (!startInclusive.isBefore(endExclusive)) {
      throw ArgumentError('startInclusive 必须早于 endExclusive');
    }
    return {
      for (final schedule in getAll())
        for (final event in _history(schedule).reviews)
          if (!event.reviewedAt.isBefore(startInclusive) &&
              event.reviewedAt.isBefore(endExclusive))
            '${PoemIdentity.canonical(schedule.poemId)}:${event.id}':
                CompletedPoemReview(
              id: event.id,
              cycleId: event.cycleId,
              poemId: PoemIdentity.canonical(event.poemId),
              reviewedAt: event.reviewedAt,
              roundBefore: event.roundBefore,
              roundAfter: event.roundAfter,
              score: event.score,
            ),
    }.values.toList()
      ..sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
  }

  int completedReviewCount(String poemId) {
    final schedule = get(poemId);
    return schedule == null ? 0 : _history(schedule).reviews.length;
  }

  PoemReviewHistory _history(ReviewSchedule schedule) =>
      PoemReviewHistory.decode(schedule.historyJson) ??
      const PoemReviewHistory(cycleId: 'legacy');

  Future<void> _serialized(
    String poemId,
    Future<void> Function() action,
  ) async {
    final key = ProfileScope.key(PoemIdentity.canonical(poemId));
    while (_pending[key] != null) {
      await _pending[key];
    }
    final done = Completer<void>();
    _pending[key] = done.future;
    try {
      await action();
    } finally {
      _pending.remove(key);
      done.complete();
    }
  }

  /// 获取某首诗的复习调度
  ReviewSchedule? get(String poemId) {
    return HiveBoxes.reviewSchedules
        .get(ProfileScope.key(PoemIdentity.canonical(poemId)));
  }

  /// 创建或更新复习调度
  Future<void> save(ReviewSchedule schedule) async {
    if (PoemIdentity.canonical(schedule.poemId) != schedule.poemId) {
      schedule = PoemIdentity.review(PoemIdentity.reviewMap(schedule));
    }
    final key = ProfileScope.key(schedule.poemId);
    await HiveBoxes.reviewSchedules.put(key, schedule);
  }

  /// 创建新的复习计划（首次背诵完成后调用）
  Future<ReviewSchedule> createSchedule(String poemId) async {
    poemId = PoemIdentity.canonical(poemId);
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
        .where(
          (s) =>
              s.profileId == ProfileScope.currentId &&
              !s.isCompleted &&
              !s.nextReviewDate.isAfter(today.add(const Duration(days: 1))),
        )
        .toList();
  }

  /// 获取所有未完成的复习计划
  List<ReviewSchedule> getActive() {
    return HiveBoxes.reviewSchedules.values
        .where(
          (s) => s.profileId == ProfileScope.currentId && !s.isCompleted,
        )
        .toList();
  }

  /// 完成一次复习并按得分自适应推进。
  ///
  /// 三分层（及格线复用 QuizSession.isPassed 的 0.8 口径）：
  /// - [score] 为 null（背诵完成）或 ≥ 0.8（测试通过）：推进下一轮；
  /// - score < 0.8：不推进，`nextReviewDate` 重置明天再来一轮。
  /// 两种情况均记录 `lastScore`（null 不覆盖既有值）。
  Future<void> completeReview(
    String poemId, {
    double? score,
    String? activityId,
    DateTime? reviewedAt,
  }) async {
    if (score != null && (!score.isFinite || score < 0 || score > 1)) {
      throw ArgumentError.value(score, 'score');
    }
    final now = reviewedAt ?? DateTime.now();
    final id = activityId ?? 'review_${now.microsecondsSinceEpoch}';
    await _serialized(poemId, () async {
      final schedule = get(poemId);
      if (schedule == null) return;
      final history = _history(schedule);
      if (history.reviews.any((event) => event.id == id) ||
          schedule.isCompleted) {
        return;
      }
      final passed = score == null || score >= 0.8;
      final round = schedule.currentRound + (passed ? 1 : 0);
      final completed = round >= ReviewSchedule.intervals.length;
      final nextHistory = PoemReviewHistory(
        cycleId: history.cycleId,
        cycleStartedAt: history.cycleStartedAt,
        cycles: history.cycles,
        reviews: [
          ...history.reviews,
          if (passed)
            CompletedPoemReview(
              id: id,
              cycleId: history.cycleId,
              poemId: PoemIdentity.canonical(poemId),
              reviewedAt: now,
              roundBefore: schedule.currentRound,
              roundAfter: round,
              score: score,
            ),
        ],
      );
      await save(
        ReviewSchedule(
          poemId: schedule.poemId,
          profileId: schedule.profileId,
          currentRound: round,
          isCompleted: completed,
          nextReviewDate: completed
              ? schedule.nextReviewDate
              : now.add(
                  Duration(days: passed ? ReviewSchedule.intervals[round] : 1),
                ),
          lastReviewedAt: passed ? now : schedule.lastReviewedAt,
          lastScore: score ?? schedule.lastScore,
          historyJson: nextHistory.encode(),
        ),
      );
    });
  }

  /// 完成五轮后重开；旧周期快照和逐次完成事件随新计划原子保存。
  Future<void> restartSchedule(
    String poemId, {
    String? operationId,
    DateTime? startedAt,
  }) async {
    final now = startedAt ?? DateTime.now();
    final cycleId = operationId ?? 'cycle_${now.microsecondsSinceEpoch}';
    await _serialized(poemId, () async {
      final schedule = get(poemId);
      if (schedule == null || !schedule.isCompleted) return;
      final history = _history(schedule);
      if (history.cycleId == cycleId ||
          history.cycles.any((cycle) => cycle['cycleId'] == cycleId)) {
        return;
      }
      final nextHistory = PoemReviewHistory(
        cycleId: cycleId,
        cycleStartedAt: now,
        reviews: history.reviews,
        cycles: [
          ...history.cycles,
          {
            'cycleId': history.cycleId,
            'cycleStartedAt': history.cycleStartedAt?.toIso8601String(),
            'currentRound': schedule.currentRound,
            'isCompleted': schedule.isCompleted,
            'nextReviewDate': schedule.nextReviewDate.toIso8601String(),
            'lastReviewedAt': schedule.lastReviewedAt?.toIso8601String(),
            'lastScore': schedule.lastScore,
            'archivedAt': now.toIso8601String(),
          }
        ],
      );
      await save(
        ReviewSchedule(
          poemId: schedule.poemId,
          profileId: schedule.profileId,
          nextReviewDate: now,
          historyJson: nextHistory.encode(),
        ),
      );
    });
  }
}
