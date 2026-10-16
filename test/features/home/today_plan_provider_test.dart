import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/providers/today_plan_providers.dart';

import '../../helpers/hive_test_helper.dart';

Poem poem(String id,
        {String semester = '下', bool required = true, String unit = '课文1',}) =>
    Poem(
      id: id,
      title: id,
      author: '作者',
      dynasty: '唐',
      content: '诗句',
      pinyin: '',
      layer: 'core',
      grade: 4,
      semester: semester,
      textbookUnit: unit,
      isRequired: required,
    );

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('今日任务采用当前册必背；实际完成首学、错题与跨周期复习后更新且不补发', () async {
    await SettingsRepository().setLearningBackground(4, '下');
    for (final entry in [
      poem('new'),
      poem('review'),
      poem('upper', semester: '上'),
      poem('extended', required: false),
    ]) {
      await HiveBoxes.poems.put(entry.id, entry);
    }
    final progress = PoemProgressRepository();
    await progress.recordStudy('review');
    final reviews = ReviewRepository();
    await reviews.save(ReviewSchedule(
      poemId: 'review',
      profileId: 'default',
      nextReviewDate: DateTime.now().subtract(const Duration(days: 1)),
    ),);
    final mistakes = MathMistakeRepository();
    await mistakes.recordWrong(
        problemText: '38+45=?',
        correctAnswer: '83',
        userAnswer: '73',
        problemType: 'addition',
        grade: 4,);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(todayPlanProvider, (_, __) {});
    addTearDown(subscription.close);
    final plan = await container.read(todayPlanProvider.future);
    expect(plan.tasks.map((task) => task.kind).toList(),
        [TodayTaskKind.review, TodayTaskKind.mistake, TodayTaskKind.newPoem],);
    expect(plan.tasks.last.targetId, 'new');
    await progress.recordStudy('new');
    await reviews.completeReview('review',
        score: 1, activityId: 'today_review',);
    await mistakes.recordRepracticeResult(mistakes.getAll().single.id,
        isCorrect: false,);
    container.invalidate(todayPlanProvider);
    final done = await container.read(todayPlanProvider.future);
    expect(done.completedCount, 3);
    await HiveBoxes.poems.put('another', poem('another'));
    container.invalidate(todayPlanProvider);
    final fixed = await container.read(todayPlanProvider.future);
    expect(
        fixed.tasks.map((task) => task.id), plan.tasks.map((task) => task.id),);
    expect(fixed.completedCount, 3);
  });
}
