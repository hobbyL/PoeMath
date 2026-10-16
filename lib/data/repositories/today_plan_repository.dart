import 'dart:async';
import 'dart:convert';

import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/today_plan.dart';

/// 本机的有界每日任务快照，不从动态推荐列表补发任务。
class TodayPlanRepository {
  TodayPlanRepository()
      : _guard = PracticeDraftRepository(),
        _epoch =
            HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int;
  final PracticeDraftRepository _guard;
  final int _epoch;
  static final Map<String, Future<TodayPlan>> _creating = {};
  static final Map<String, Future<void>> _writes = {};
  static const _prefix = 'today_plan_v1:';
  String get _configKey => 'today_plan_config_v1:${ProfileScope.currentId}';

  /// 恢复整库时丢弃绑定旧内容的日队列；设备上的家长配置仍保留。
  static Future<void> clearForRestore() async {
    await HiveBoxes.meta.deleteAll(HiveBoxes.meta.keys
        .whereType<String>()
        .where((key) => key.startsWith(_prefix))
        .toList(),);
  }

  TodayPlanConfig get config {
    final raw = HiveBoxes.meta.get(_configKey);
    if (raw is! String) return const TodayPlanConfig();
    try {
      return TodayPlanConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const TodayPlanConfig();
    }
  }

  Future<void> saveConfig(TodayPlanConfig config) async {
    ParentAccessService.instance.assertAllowed();
    // 同一校验器约束用户配置和落盘数据。
    TodayPlanConfig.fromJson(config.toJson());
    await HiveBoxes.meta.put(_configKey, jsonEncode(config.toJson()));
  }

  Future<TodayPlan> getOrCreate({
    required DateTime now,
    required int grade,
    required String semester,
    required Map<TodayTaskKind, List<TodayTaskCandidate>> candidates,
  }) async {
    _guard.assertCurrent();
    final profileId = ProfileScope.currentId;
    final date = planDateKey(now);
    final key = '$_prefix$profileId:$date';
    final pendingKey = '$key@$_epoch';
    final pending = _creating[pendingKey];
    if (pending != null) return pending;
    final future = _serialize(key,
        () => _loadOrCreate(key, date, profileId, grade, semester, candidates),);
    _creating[pendingKey] = future;
    try {
      return await future;
    } finally {
      _creating.remove(pendingKey);
    }
  }

  Future<TodayPlan> _loadOrCreate(
    String key,
    String date,
    String profileId,
    int grade,
    String semester,
    Map<TodayTaskKind, List<TodayTaskCandidate>> candidates,
  ) async {
    final raw = HiveBoxes.meta.get(key);
    if (raw != null && raw is! String) {
      throw const FormatException('今日计划存储格式无效');
    }
    if (raw is String) {
      // 损坏快照需要显式报错，不能悄悄重发一套当天任务。
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if ((json['epoch'] as int? ?? 0) == _epoch) {
        final plan = TodayPlan.fromJson(json);
        if (plan.profileId != profileId || plan.dateKey != date) {
          throw const FormatException('今日计划归属不匹配');
        }
        return plan;
      }
    }
    final settings = config;
    final tasks = <TodayPlanTask>[];
    for (final kind in settings.order) {
      final seen = <String>{};
      for (final candidate in (candidates[kind] ?? const <TodayTaskCandidate>[])
          .where((candidate) => seen.add(candidate.id))
          .take(settings.countFor(kind))) {
        tasks.add(
          TodayPlanTask(
            kind: kind,
            targetId: candidate.id,
            title: candidate.title,
            baseline: candidate.baseline,
          ),
        );
      }
    }
    final plan = TodayPlan(
      dateKey: date,
      profileId: profileId,
      grade: grade,
      semester: semester,
      tasks: tasks,
      epoch: _epoch,
    );
    _guard.assertCurrent();
    await HiveBoxes.meta.put(key, jsonEncode(plan.toJson()));
    final keys = HiveBoxes.meta.keys
        .whereType<String>()
        .where((value) => value.startsWith('$_prefix$profileId:'))
        .toList()
      ..sort();
    if (keys.length > 14) {
      await HiveBoxes.meta.deleteAll(keys.take(keys.length - 14));
    }
    return plan;
  }

  Future<TodayPlan> refreshCompletion(
          TodayPlan plan, Set<String> completedIds,) =>
      _serialize('$_prefix${plan.profileId}:${plan.dateKey}', () async {
        if (plan.epoch != _epoch) throw StateError('今日清单已失效，请重新读取');
        if (completedIds.isEmpty) return plan;
        final key = '$_prefix${plan.profileId}:${plan.dateKey}';
        final raw = HiveBoxes.meta.get(key);
        if (raw is! String) throw StateError('今日清单已清理，请重新读取');
        final stored =
            TodayPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (stored.epoch != _epoch) throw StateError('今日清单已失效，请重新读取');
        final tasks = stored.tasks
            .map((task) =>
                completedIds.contains(task.id) ? task.complete() : task,)
            .toList();
        if (tasks.where((task) => task.completed).length ==
            stored.completedCount) {
          return stored;
        }
        final updated = TodayPlan(
          dateKey: stored.dateKey,
          profileId: stored.profileId,
          grade: stored.grade,
          semester: stored.semester,
          tasks: tasks,
          epoch: _epoch,
        );
        _guard.assertCurrent();
        await HiveBoxes.meta.put(key, jsonEncode(updated.toJson()));
        return updated;
      });

  Stream<void> changes() => HiveBoxes.meta
      .watch()
      .where((event) =>
          event.key == 'practice_draft_epoch' ||
          event.key.toString().startsWith(_prefix),)
      .map((_) {});

  Future<T> _serialize<T>(String key, Future<T> Function() action) =>
      _guard.guard(() async {
        final previous = _writes[key];
        final done = Completer<void>();
        _writes[key] = done.future;
        try {
          if (previous != null) await previous;
          _guard.assertCurrent();
          return await action();
        } finally {
          if (identical(_writes[key], done.future)) _writes.remove(key);
          done.complete();
        }
      });
}
