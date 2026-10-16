import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/today_plan_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/today_plan.dart';

import '../../helpers/hive_test_helper.dart';

Map<TodayTaskKind, List<TodayTaskCandidate>> candidates(String suffix) => {
      for (final kind in TodayTaskKind.values)
        kind: [
          for (var i = 0; i < 8; i++)
            TodayTaskCandidate(
                id: '${kind.name}_$suffix$i', title: '$suffix$i', baseline: i,),
        ],
    };

void main() {
  setUp(setUpHiveForTesting);
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  test('当天任务有界且稳定：完成、换候选、改册次和重开均不补发', () async {
    final repository = TodayPlanRepository();
    final date = DateTime(2026, 10, 16, 8);
    final first = await repository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('a'),);
    expect(first.tasks.map((task) => task.targetId).toList(), [
      'review_a0',
      'review_a1',
      'mistake_a0',
      'mistake_a1',
      'mistake_a2',
      'newPoem_a0',
    ]);
    await repository.refreshCompletion(
        first, first.tasks.map((task) => task.id).toSet(),);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final again = await repository.getOrCreate(
        now: date, grade: 6, semester: '上', candidates: candidates('b'),);
    expect(again.completedCount, 6);
    expect(again.grade, 4);
    expect(again.semester, '下');
    expect(
        again.tasks.map((task) => task.id), first.tasks.map((task) => task.id),);
    final unchanged = await repository.refreshCompletion(again, {});
    expect(unchanged.completedCount, 6);
  });

  test('家长数量与顺序持久化，次日生效；没有候选时不强行凑数', () async {
    final repository = TodayPlanRepository();
    final date = DateTime(2026, 10, 16);
    final first = await repository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('a'),);
    await repository.saveConfig(const TodayPlanConfig(
      reviewCount: 0,
      mistakeCount: 1,
      newPoemCount: 2,
      order: [
        TodayTaskKind.newPoem,
        TodayTaskKind.mistake,
        TodayTaskKind.review,
      ],
    ),);
    final today = await repository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('b'),);
    expect(
        today.tasks.map((task) => task.id), first.tasks.map((task) => task.id),);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final tomorrow = await repository.getOrCreate(
        now: date.add(const Duration(days: 1)),
        grade: 4,
        semester: '下',
        candidates: candidates('b'),);
    expect(tomorrow.tasks.map((task) => task.targetId).toList(),
        ['newPoem_b0', 'newPoem_b1', 'mistake_b0'],);
    final empty = await repository.getOrCreate(
        now: date.add(const Duration(days: 2)),
        grade: 4,
        semester: '下',
        candidates: {},);
    expect(empty.tasks, isEmpty);
  });

  test('最多每类五项，跨档案隔离，恢复清队列保留配置，最多保留十四日', () async {
    final repository = TodayPlanRepository();
    await repository.saveConfig(const TodayPlanConfig(
        reviewCount: 5, mistakeCount: 5, newPoemCount: 5,),);
    final date = DateTime(2026, 10, 1);
    for (var i = 0; i < 20; i++) {
      final plan = await repository.getOrCreate(
          now: date.add(Duration(days: i)),
          grade: 4,
          semester: '下',
          candidates: candidates('a'),);
      expect(plan.tasks.length, 15);
    }
    expect(
        HiveBoxes.meta.keys
            .whereType<String>()
            .where((key) => key.startsWith('today_plan_v1:'))
            .length,
        14,);
    ProfileScope.switchTo('other');
    final other = await repository.getOrCreate(
        now: date, grade: 2, semester: '上', candidates: candidates('b'),);
    expect(other.tasks.length, 6);
    expect(other.profileId, 'other');
    ProfileScope.reset();
    await TodayPlanRepository.clearForRestore();
    expect(
        HiveBoxes.meta.keys
            .whereType<String>()
            .where((key) => key.startsWith('today_plan_v1:')),
        isEmpty,);
    expect(repository.config.newPoemCount, 5);
    expect(
        () => TodayPlanConfig.fromJson({
              'review': 6,
              'mistake': 1,
              'newPoem': 1,
              'order': ['review', 'mistake', 'newPoem'],
            }),
        throwsFormatException,);
  });

  test('同一天并发创建只有一份；损坏快照报错而非自动补发', () async {
    final repository = TodayPlanRepository();
    final date = DateTime(2026, 10, 16);
    final plans = await Future.wait([
      for (var i = 0; i < 4; i++)
        repository.getOrCreate(
            now: date, grade: 4, semester: '下', candidates: candidates('$i'),),
    ]);
    expect(plans.map((plan) => jsonEncode(plan.toJson())).toSet().length, 1);
    await HiveBoxes.meta.put('today_plan_v1:default:2026-10-16', 'broken');
    await expectLater(
        repository.getOrCreate(
            now: date, grade: 4, semester: '下', candidates: candidates('new'),),
        throwsFormatException,);
  });

  test('家长保护锁定时不能绕过界面修改计划配置', () async {
    await HiveBoxes.settings.put('parent_protection_enabled', true);
    await expectLater(
        TodayPlanRepository().saveConfig(const TodayPlanConfig(reviewCount: 0)),
        throwsA(isA<ParentAccessDenied>()),);
    expect(TodayPlanRepository().config.reviewCount, 2);
  });

  test('同日并发完成不同任务不会丢状态', () async {
    final repository = TodayPlanRepository();
    final date = DateTime(2026, 10, 16);
    final plan = await repository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('a'),);
    await Future.wait([
      for (final task in plan.tasks)
        repository.refreshCompletion(plan, {task.id}),
    ]);
    final updated = await repository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('b'),);
    expect(updated.completedCount, plan.tasks.length);
  });

  test('恢复epoch使旧仓储和旧快照失效，不回写恢复后的数据', () async {
    final date = DateTime(2026, 10, 16);
    final oldRepository = TodayPlanRepository();
    final old = await oldRepository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('old'),);
    await PracticeDraftRepository.clearAll();
    await expectLater(
        oldRepository.refreshCompletion(old, {old.tasks.first.id}),
        throwsStateError,);
    await expectLater(
        oldRepository.getOrCreate(
            now: date, grade: 4, semester: '下', candidates: candidates('old'),),
        throwsStateError,);
    final current = TodayPlanRepository();
    final fresh = await current.getOrCreate(
        now: date, grade: 6, semester: '上', candidates: candidates('new'),);
    expect(fresh.epoch, 1);
    expect(fresh.grade, 6);
    expect(fresh.tasks.first.targetId, 'review_new0');
    await expectLater(
        current.refreshCompletion(old, {old.tasks.first.id}), throwsStateError,);
    await TodayPlanRepository.clearForRestore();
    await expectLater(current.refreshCompletion(fresh, {fresh.tasks.first.id}),
        throwsStateError,);
    expect(
        HiveBoxes.meta.keys
            .whereType<String>()
            .where((key) => key.startsWith('today_plan_v1:')),
        isEmpty,);
  });

  test('恢复屏障排空正在创建的任务，恢复后旧创建不返回可用快照', () async {
    final repository = TodayPlanRepository();
    final date = DateTime(2026, 10, 16);
    final creating = repository.getOrCreate(
        now: date, grade: 4, semester: '下', candidates: candidates('old'),);
    final rejected = expectLater(creating, throwsStateError);
    await PracticeDraftRepository.whileRestoring(() async {
      await expectLater(
          TodayPlanRepository()
              .getOrCreate(now: date, grade: 1, semester: '上', candidates: {}),
          throwsStateError,);
      await PracticeDraftRepository.clearAll();
      await TodayPlanRepository.clearForRestore();
    });
    await rejected;
    final fresh = await TodayPlanRepository().getOrCreate(
        now: date, grade: 6, semester: '上', candidates: candidates('new'),);
    expect(fresh.epoch, 1);
    expect(fresh.tasks.first.targetId, 'review_new0');
  });
}
