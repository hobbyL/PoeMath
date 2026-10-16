import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/today_plan_repository.dart';
import 'package:poemath/domain/poem_curriculum.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

final todayPlanRepositoryProvider = Provider<TodayPlanRepository>((ref) {
  final subscription = HiveBoxes.meta
      .watch(key: 'practice_draft_epoch')
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return TodayPlanRepository();
});

final todayPlanProvider = FutureProvider.autoDispose<TodayPlan>((ref) async {
  ref.watch(dayKeyProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final poems = ref.watch(poemRepositoryProvider);
  final progress = ref.watch(poemProgressRepositoryProvider);
  final reviews = ref.watch(reviewRepositoryProvider);
  final mistakes = ref.watch(mathMistakeRepositoryProvider);
  final repository = ref.watch(todayPlanRepositoryProvider);
  final subscriptions = [
    HiveBoxes.poemProgress.watch().listen((_) => ref.invalidateSelf()),
    HiveBoxes.reviewSchedules.watch().listen((_) => ref.invalidateSelf()),
    HiveBoxes.mathMistakes.watch().listen((_) => ref.invalidateSelf()),
    repository.changes().listen((_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  });
  final due = reviews.getDueToday()
    ..sort((a, b) => a.nextReviewDate.compareTo(b.nextReviewDate));
  final plan = await repository.getOrCreate(
    now: DateTime.now(),
    grade: settings.selectedGrade,
    semester: settings.selectedSemester,
    candidates: {
      TodayTaskKind.review: [
        for (final review in due)
          if (poems.getById(review.poemId) case final poem?)
            TodayTaskCandidate(
                id: poem.id,
                title: poem.title,
                baseline: reviews.completedReviewCount(poem.id),),
      ],
      TodayTaskKind.mistake: [
        for (final mistake in mistakes.getAll())
          if (mistake.isUnmastered || mistake.isConsolidationDue)
            TodayTaskCandidate(
                id: mistake.id,
                title: mistake.problemText,
                baseline: mistake.retryCount,),
      ],
      TodayTaskKind.newPoem: [
        for (final poem in requiredTextbookPoems(
          poems.getAll(),
          settings.selectedGrade,
          settings.selectedSemester,
        ))
          if (progress.get(poem.id)?.status == null ||
              progress.get(poem.id)?.status == LearningStatus.notStarted)
            TodayTaskCandidate(
                id: poem.id,
                title: poem.title,
                baseline: progress.get(poem.id)?.studyCount ?? 0,),
      ],
    },
  );
  final completed = <String>{};
  for (final task in plan.tasks) {
    final isCompleted = switch (task.kind) {
      TodayTaskKind.newPoem =>
        (progress.get(task.targetId)?.studyCount ?? 0) > task.baseline,
      TodayTaskKind.mistake =>
        (mistakes.getById(task.targetId)?.retryCount ?? 0) > task.baseline,
      TodayTaskKind.review =>
        reviews.completedReviewCount(task.targetId) > task.baseline,
    };
    if (isCompleted) completed.add(task.id);
  }
  return repository.refreshCompletion(plan, completed);
});
