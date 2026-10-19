// test/core/services/backup_coverage_guard_test.dart
//
// 备份覆盖范围守卫：新增一类持久化数据后若忘了接进 `exportToJson`，
// 它会静默不同步 —— 用户换机才发现数据丢了，没有任何报错线索。
// 本文件把「哪些数据随备份走」变成可执行契约。
//
// 对应 spec：`.trellis/spec/backend/backup-service.md` 的
// 「The full travel / don't-travel map」。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

import '../../helpers/hive_test_helper.dart';

/// 随备份迁移的顶层字段。新增 box 时必须同时加到 `exportToJson` 和这里。
const Set<String> _travelingFields = {
  'version',
  'exportedAt',
  'poemProgress',
  'poemFavorites',
  'reviewSchedules',
  'mathMistakes',
  'mathSessions',
  'formulaFavorites',
  'achievements',
  'checkIns',
  'userStats',
  'challengeRecords',
  'learningActivities',
  'llmProblems',
  'conversations',
  'messages',
  'activitySettlements',
  'settings',
  // credentials 仅在提供口令时出现，不在此断言。
};

/// 明确不同步的顶层字段。放进来等于「已决策」，不是遗漏。
const Set<String> _nonTravelingFields = <String>{'credentials'};

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('导出的顶层字段与契约清单逐项一致', () async {
    final data =
        jsonDecode(await BackupService().exportToJson()) as Map<String, dynamic>;
    final actual = data.keys.toSet();

    expect(
      actual.difference(_travelingFields).difference(_nonTravelingFields),
      isEmpty,
      reason: '导出里出现了契约未登记的新字段 —— 请更新本测试的 '
          '_travelingFields 与 backup-service.md 的同步清单',
    );
    expect(
      _travelingFields.difference(actual),
      isEmpty,
      reason: '契约声明的字段没被导出 —— exportToJson 可能被改坏了',
    );
  });

  test('每个动态数据 box 要么随备份走，要么在清单里显式排除', () async {
    // 空数据下导出，只校验「字段名存在与否」这一层契约。
    // 具体内容正确性由各 collection 的专项测试负责。
    final data =
        jsonDecode(await BackupService().exportToJson()) as Map<String, dynamic>;

    expect(data['poemProgress'], isEmpty);
    expect(data['mathMistakes'], isEmpty);
    expect(data['learningActivities'], isEmpty);
    expect(data['conversations'], isEmpty);
    expect(data['messages'], isEmpty);
    expect(
      data['settings'],
      isA<Map<String, dynamic>>(),
      reason: 'settings 节必须存在（导出为空对象也应出现）',
    );
  });

  test('meta box 里只有结算标记随备份走，其余本机状态不外泄', () async {
    // 往 meta 写入三类「本机状态」，都不应出现在导出里。
    await HiveBoxes.meta.put('cloud_usage:2026-10-19:llm', 7);
    await HiveBoxes.meta.put(
      'practice_draft:word',
      jsonEncode({'schema': 1}),
    );
    await HiveBoxes.meta.put(
      'today_plan_config_v1:default',
      jsonEncode({'dailyPoemGoal': 3}),
    );
    // 结算标记则必须随 `activitySettlements` 走。
    await HiveBoxes.meta.put(
      'default_activity_settlement:user_stats:act-1',
      true,
    );

    final raw = await BackupService().exportToJson();

    expect(raw, isNot(contains('cloud_usage')));
    expect(raw, isNot(contains('practice_draft')));
    expect(raw, isNot(contains('today_plan_config')));
    expect(
      jsonDecode(raw)['activitySettlements'],
      contains('default_activity_settlement:user_stats:act-1'),
    );
  });
}
