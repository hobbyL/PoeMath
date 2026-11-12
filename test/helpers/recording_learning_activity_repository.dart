import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

class RecordingLearningActivityRepository extends LearningActivityRepository {
  final records = <String, LearningActivity>{};

  @override
  Future<bool> record({
    required String id,
    required LearningActivityType activityType,
    required int totalItems,
    required int successfulItems,
    required int starsEarned,
    required int durationSeconds,
    required DateTime completedAt,
    String? poemId,
    String? detailsJson,
  }) async {
    final activity = LearningActivity(
      id: id,
      profileId: ProfileScope.currentId,
      activityType: activityType.name,
      totalItems: totalItems,
      successfulItems: successfulItems,
      starsEarned: starsEarned,
      durationSeconds: durationSeconds,
      completedAt: completedAt,
      poemId: poemId,
      detailsJson: detailsJson,
    );
    final existing = records[id];
    if (existing != null) {
      if (!_samePayload(existing, activity)) {
        throw StateError('活动 ID $id 已被不同内容使用');
      }
      return false;
    }
    records[id] = activity;
    return true;
  }

  bool _samePayload(LearningActivity left, LearningActivity right) =>
      left.profileId == right.profileId &&
      left.activityType == right.activityType &&
      left.totalItems == right.totalItems &&
      left.successfulItems == right.successfulItems &&
      left.starsEarned == right.starsEarned &&
      left.durationSeconds == right.durationSeconds &&
      left.completedAt == right.completedAt &&
      left.poemId == right.poemId &&
      left.detailsJson == right.detailsJson;
}
