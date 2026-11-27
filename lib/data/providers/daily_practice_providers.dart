import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/poem_identity.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/daily_practice_spacing.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

/// 今日日期 key（yyyy-MM-dd）。每 30 秒比对，驱动目标及练习列表跨天更新。
class DayKeyNotifier extends Notifier<String> {
  @override
  String build() {
    final timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final today = _todayKey();
      if (state != today) state = today;
    });
    ref.onDispose(timer.cancel);
    return _todayKey();
  }
}

final dayKeyProvider = NotifierProvider<DayKeyNotifier, String>(
  DayKeyNotifier.new,
);

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

final _profileChangesProvider = StreamProvider((ref) => ProfileScope.changes);
final _poemProgressChangesProvider = StreamProvider(
  (ref) => HiveBoxes.poemProgress.watch(),
);
final _learningActivityChangesProvider = StreamProvider(
  (ref) => HiveBoxes.learningActivities.watch(),
);
final _expressionCompletionChangesProvider = StreamProvider(
  (ref) => HiveBoxes.pictureStoryPractice.watch(),
);

/// 当前孩子的完整已知完成历史，包含看图活动漏写时的只读恢复。
final learningActivityHistoryProvider = Provider<List<LearningActivity>>((ref) {
  ref.watch(_profileChangesProvider);
  ref.watch(_learningActivityChangesProvider);
  ref.watch(_expressionCompletionChangesProvider);
  return ref.watch(learningActivityRepositoryProvider).getAll();
});

final poemDailyPracticeSpacingProvider = Provider<DailyPracticeSpacing>((ref) {
  final today = DateTime.parse(ref.watch(dayKeyProvider));
  ref.watch(_poemProgressChangesProvider);
  final activities = ref.watch(learningActivityHistoryProvider);
  final progress = ref.watch(poemProgressRepositoryProvider).getAll();
  return evaluateDailyPracticeSpacing([
    for (final activity in activities)
      if (activity.poemId != null &&
          const {
            LearningActivityType.poemRecitation,
            LearningActivityType.poemQuiz,
            LearningActivityType.poemDictation,
            LearningActivityType.readAlong,
          }.contains(activity.typeOrNull))
        (
          contentId: PoemIdentity.canonical(activity.poemId!),
          completedAt: activity.completedAt,
        ),
    // 旧版本可能只有进度，或结算尚未写完活动；仅补入确实已知的日期。
    for (final poem in progress) ...[
      if (poem.firstStudiedAt case final first?)
        (contentId: PoemIdentity.canonical(poem.poemId), completedAt: first),
      if (poem.lastStudiedAt case final last?)
        (contentId: PoemIdentity.canonical(poem.poemId), completedAt: last),
    ],
  ], day: today);
});

final pictureStoryDailyPracticeSpacingProvider = Provider<DailyPracticeSpacing>(
  (ref) {
    final today = DateTime.parse(ref.watch(dayKeyProvider));
    final activities = ref.watch(learningActivityHistoryProvider);
    final promptIds = {
      for (final record in HiveBoxes.pictureStoryPractice.values)
        if (record.profileId == ProfileScope.currentId &&
            record.status == 'completed' &&
            record.completedAt != null)
          'picture-story:${record.id}': record.promptId,
    };
    return evaluateDailyPracticeSpacing([
      for (final activity in activities)
        if (activity.typeOrNull == LearningActivityType.pictureStoryExpression)
          if (promptIds[activity.id] case final promptId?)
            (contentId: promptId, completedAt: activity.completedAt),
    ], day: today);
  },
);
