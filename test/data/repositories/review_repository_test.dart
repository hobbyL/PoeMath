// test/data/repositories/review_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/review_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late ReviewRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    repo = ReviewRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('ReviewRepository', () {
    test('get 无记录返回 null', () {
      expect(repo.get('poem_001'), isNull);
    });

    test('save 和 get 正常工作', () async {
      final schedule = ReviewSchedule(
        poemId: 'poem_001',
        profileId: ProfileScope.currentId,
        nextReviewDate: DateTime.now().add(const Duration(days: 1)),
      );
      await repo.save(schedule);

      final loaded = repo.get('poem_001');
      expect(loaded, isNotNull);
      expect(loaded!.poemId, 'poem_001');
      expect(loaded.currentRound, 0);
    });

    test('createSchedule 创建新复习计划', () async {
      final schedule = await repo.createSchedule('poem_002');
      expect(schedule.poemId, 'poem_002');
      expect(schedule.profileId, 'default');
      expect(schedule.currentRound, 0);
      expect(schedule.isCompleted, isFalse);

      // 验证已持久化
      expect(repo.get('poem_002'), isNotNull);
    });

    test('getDueToday 返回今日待复习的诗词', () async {
      // 今天应该复习的
      final dueSchedule = ReviewSchedule(
        poemId: 'due_poem',
        profileId: ProfileScope.currentId,
        nextReviewDate: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await HiveBoxes.reviewSchedules.put(
        ProfileScope.key('due_poem'),
        dueSchedule,
      );

      // 明天才需要复习的
      final futureSchedule = ReviewSchedule(
        poemId: 'future_poem',
        profileId: ProfileScope.currentId,
        nextReviewDate: DateTime.now().add(const Duration(days: 2)),
      );
      await HiveBoxes.reviewSchedules.put(
        ProfileScope.key('future_poem'),
        futureSchedule,
      );

      // 已完成的
      final completedSchedule = ReviewSchedule(
        poemId: 'done_poem',
        profileId: ProfileScope.currentId,
        nextReviewDate: DateTime.now(),
        isCompleted: true,
      );
      await HiveBoxes.reviewSchedules.put(
        ProfileScope.key('done_poem'),
        completedSchedule,
      );

      final due = repo.getDueToday();
      expect(due.length, 1);
      expect(due.first.poemId, 'due_poem');
    });

    test('getActive 返回未完成的复习计划', () async {
      await repo.createSchedule('active_1');
      await repo.createSchedule('active_2');

      // 添加一个已完成的
      final completed = ReviewSchedule(
        poemId: 'completed_1',
        profileId: ProfileScope.currentId,
        nextReviewDate: DateTime.now(),
        isCompleted: true,
      );
      await HiveBoxes.reviewSchedules.put(
        ProfileScope.key('completed_1'),
        completed,
      );

      final active = repo.getActive();
      expect(active.length, 2);
    });

    test('completeReview 推进复习轮次', () async {
      await repo.createSchedule('poem_review');
      await repo.completeReview('poem_review');

      final schedule = repo.get('poem_review')!;
      expect(schedule.currentRound, 1);
      expect(schedule.lastReviewedAt, isNotNull);
    });

    test('completeReview 全部轮次完成后标记 isCompleted', () async {
      await repo.createSchedule('poem_all');

      // 完成所有 5 轮
      for (var i = 0; i < ReviewSchedule.intervals.length; i++) {
        await repo.completeReview('poem_all');
      }

      final schedule = repo.get('poem_all')!;
      expect(schedule.isCompleted, isTrue);
    });

    test('completeReview 对不存在的诗词无操作', () async {
      // 不应抛异常
      await repo.completeReview('nonexistent');
    });

    test('getActive 不包含其他 profile 的数据', () async {
      await repo.createSchedule('poem_p1');

      ProfileScope.switchTo('kid2');
      expect(repo.getActive().length, 0);

      ProfileScope.reset();
    });
  });
}
