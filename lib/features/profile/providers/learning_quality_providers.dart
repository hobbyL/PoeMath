import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/learning_quality.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

final learningQualityProvider =
    Provider.autoDispose.family<LearningQualityReport, int>((ref, days) {
  ref.watch(dayKeyProvider);
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day + 1);
  final start = DateTime(now.year, now.month, now.day - days + 1);
  final subscriptions = [
    HiveBoxes.mathSessions.watch().listen((_) => ref.invalidateSelf()),
    HiveBoxes.challengeRecords.watch().listen((_) => ref.invalidateSelf()),
    HiveBoxes.poemProgress.watch().listen((_) => ref.invalidateSelf()),
    HiveBoxes.learningActivities.watch().listen((_) => ref.invalidateSelf()),
    HiveBoxes.reviewSchedules.watch().listen((_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  });
  final reviews =
      ref.watch(reviewRepositoryProvider).completedReviewsBetween(start, end);
  return buildLearningQualityReport(
    startInclusive: start,
    endExclusive: end,
    sessions: ref.watch(mathSessionRepositoryProvider).getAll(),
    challenges: ref.watch(challengeRecordRepositoryProvider).getAll(),
    activities: ref.watch(learningActivityRepositoryProvider).getAll(),
    poemProgress: ref.watch(poemProgressRepositoryProvider).getAll(),
    reviews: reviews.map((review) => QualityReviewCompletion(
        poemId: review.poemId, completedAt: review.reviewedAt,),),
  );
});
