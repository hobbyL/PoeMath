// lib/data/repositories/learning_activity_repository.dart
//
// 层级：data/repositories
// 职责：学习活动事件写入和历史查询。Profile-scoped。

import 'dart:async';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

class LearningActivityRepository {
  static final Map<String, Future<void>> _inFlight = {};

  LearningActivity? getById(String id) {
    return HiveBoxes.learningActivities.get(ProfileScope.key(id));
  }

  List<LearningActivity> getAll() {
    return HiveBoxes.learningActivities.values
        .where((activity) => activity.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  List<LearningActivity> completedBetween(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    if (!startInclusive.isBefore(endExclusive)) {
      throw ArgumentError('startInclusive 必须早于 endExclusive');
    }
    return getAll()
        .where(
          (activity) =>
              !activity.completedAt.isBefore(startInclusive) &&
              activity.completedAt.isBefore(endExclusive),
        )
        .toList();
  }

  /// 写入一次活动。相同 ID 和内容重放返回 false，不同内容复用 ID 时抛错。
  Future<bool> record({
    required String id,
    required LearningActivityType activityType,
    required int totalItems,
    required int successfulItems,
    required int starsEarned,
    required int durationSeconds,
    required DateTime completedAt,
    String? poemId,
  }) async {
    final activity = LearningActivity(
      id: id,
      profileId: ProfileScope.currentId,
      activityType: activityType.name,
      totalItems: totalItems,
      successfulItems: successfulItems,
      poemId: poemId,
      starsEarned: starsEarned,
      durationSeconds: durationSeconds,
      completedAt: completedAt,
    );
    _validate(activity);

    final key = ProfileScope.key(activity.id);
    while (true) {
      final pending = _inFlight[key];
      if (pending != null) {
        await pending;
        continue;
      }

      final completer = Completer<void>();
      _inFlight[key] = completer.future;
      try {
        final existing = HiveBoxes.learningActivities.get(key);
        if (existing != null) {
          if (_hasSamePayload(existing, activity)) return false;
          throw StateError('活动 ID ${activity.id} 已被不同内容使用');
        }
        await HiveBoxes.learningActivities.put(key, activity);
        return true;
      } finally {
        _inFlight.remove(key);
        completer.complete();
      }
    }
  }

  void _validate(LearningActivity activity) {
    if (activity.id.trim().isEmpty) {
      throw ArgumentError.value(activity.id, 'id', '不能为空');
    }
    if (activity.totalItems < 0) {
      throw RangeError.range(activity.totalItems, 0, null, 'totalItems');
    }
    if (activity.successfulItems < 0 ||
        activity.successfulItems > activity.totalItems) {
      throw RangeError.range(
        activity.successfulItems,
        0,
        activity.totalItems,
        'successfulItems',
      );
    }
    if (activity.starsEarned < 0 || activity.starsEarned > 3) {
      throw RangeError.range(activity.starsEarned, 0, 3, 'starsEarned');
    }
    if (activity.durationSeconds < 0) {
      throw RangeError.range(
        activity.durationSeconds,
        0,
        null,
        'durationSeconds',
      );
    }

    final requiresPoem = switch (activity.type) {
      LearningActivityType.poemRecitation ||
      LearningActivityType.poemQuiz ||
      LearningActivityType.readAlong =>
        true,
      _ => false,
    };
    if (requiresPoem &&
        (activity.poemId == null || activity.poemId!.trim().isEmpty)) {
      throw ArgumentError.value(activity.poemId, 'poemId', '诗词活动不能为空');
    }
    if (activity.poemId != null && activity.poemId!.trim().isEmpty) {
      throw ArgumentError.value(activity.poemId, 'poemId', '不能为空字符串');
    }
  }

  bool _hasSamePayload(
    LearningActivity left,
    LearningActivity right,
  ) {
    return left.id == right.id &&
        left.profileId == right.profileId &&
        left.activityType == right.activityType &&
        left.totalItems == right.totalItems &&
        left.successfulItems == right.successfulItems &&
        left.poemId == right.poemId &&
        left.starsEarned == right.starsEarned &&
        left.durationSeconds == right.durationSeconds &&
        left.completedAt == right.completedAt;
  }
}
