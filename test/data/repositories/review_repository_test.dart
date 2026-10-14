// test/data/repositories/review_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/review_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late ReviewRepository repo;

  /// 采集「当前时刻」的基准，供断言计算时间差。
  ///
  /// 仓储内部用 `DateTime.now()` 算出 nextReviewDate，断言端点若**再次**
  /// 调用 `DateTime.now()`，两次取值之间会跨过真实时间 —— 恰在午夜边界
  /// 时 `inDays` 就少 1，用例随机变红。这里在动作结束后立刻取一次基准，
  /// 与产出时间几乎同刻，误差只剩毫秒级（不会跨天）。
  var base = DateTime.now();

  /// 把基准重置到「现在」（在每个产生 nextReviewDate 的动作后调用）。
  void captureBase() => base = DateTime.now();

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

    test('completeReview 满分推进并记录 lastScore', () async {
      await repo.createSchedule('poem_full');
      await repo.completeReview('poem_full', score: 1.0);
      captureBase();

      final schedule = repo.get('poem_full')!;
      expect(schedule.currentRound, 1);
      expect(schedule.lastScore, 1.0);
      // 第 1 轮后下次间隔 3 天
      expect(
        schedule.nextReviewDate.difference(base).inDays,
        inInclusiveRange(2, 3),
      );
    });

    test('completeReview 得分 0.8–0.99 推进且记录 lastScore', () async {
      await repo.createSchedule('poem_mid');
      await repo.completeReview('poem_mid', score: 0.85);

      final schedule = repo.get('poem_mid')!;
      expect(schedule.currentRound, 1);
      expect(schedule.lastScore, 0.85);
    });

    test('completeReview 得分低于 0.8 不推进、明天重测', () async {
      await repo.createSchedule('poem_low');
      await repo.completeReview('poem_low', score: 0.5);
      captureBase();

      final schedule = repo.get('poem_low')!;
      expect(schedule.currentRound, 0);
      expect(schedule.lastScore, 0.5);
      // 未达及格线：nextReviewDate 重置为明天
      expect(
        schedule.nextReviewDate.difference(base).inDays,
        inInclusiveRange(0, 1),
      );
      expect(schedule.lastReviewedAt, isNull);
    });

    test('completeReview 无得分不覆盖既有 lastScore', () async {
      await repo.createSchedule('poem_keep');
      await repo.completeReview('poem_keep', score: 0.9);
      // 背诵完成路径：无得分，lastScore 应保持 0.9
      await repo.completeReview('poem_keep');

      final schedule = repo.get('poem_keep')!;
      expect(schedule.lastScore, 0.9);
      expect(schedule.currentRound, 2);
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
      // 零断言回归：原先只有 `await repo.completeReview('nonexistent');`
      // 配一句「不应抛异常」注释。删掉 completeReview 的
      // 「取不到记录就早退」守卫后，原用例照样绿。
      await repo.createSchedule('poem_exists');
      final before = repo.get('poem_exists')!.currentRound;

      await repo.completeReview('nonexistent');

      expect(repo.get('nonexistent'), isNull, reason: '不得凭空创建计划');
      expect(repo.getActive(), hasLength(1), reason: '不得新增记录');
      expect(
        repo.get('poem_exists')!.currentRound,
        before,
        reason: '不得误推进其他诗词的轮次',
      );
    });

    test('getActive 不包含其他 profile 的数据', () async {
      await repo.createSchedule('poem_p1');

      ProfileScope.switchTo('kid2');
      expect(repo.getActive().length, 0);

      ProfileScope.reset();
    });
  });
}
