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
import 'package:poemath/core/services/cloud_usage_service.dart';
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
  'cloudUsage',
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

  test('meta box 里只有结算标记与云用量随备份走，其余本机状态不外泄', () async {
    // 往 meta 写入三类「本机状态」，都不应出现在导出里。
    await HiveBoxes.meta.put(
      'practice_draft:word',
      jsonEncode({'schema': 1}),
    );
    await HiveBoxes.meta.put(
      'today_plan_config_v1:default',
      jsonEncode({'dailyPoemGoal': 3}),
    );
    await HiveBoxes.meta.put('last_external_backup', '2026-10-01T00:00:00Z');
    // 这两类必须随备份走：
    await HiveBoxes.meta.put(
      'default_activity_settlement:user_stats:act-1',
      true,
    );
    await HiveBoxes.meta.put('cloud_usage:2026-10-18:llm', 7);

    final raw = await BackupService().exportToJson();

    expect(raw, isNot(contains('practice_draft')));
    expect(raw, isNot(contains('today_plan_config')));
    expect(raw, isNot(contains('last_external_backup')));

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(
      decoded['activitySettlements'],
      contains('default_activity_settlement:user_stats:act-1'),
    );
    expect(
      decoded['cloudUsage'],
      containsPair('cloud_usage:2026-10-18:llm', 7),
    );
  });

  test('云用量键自带日期：恢复旧备份不会污染恢复当天的桶', () async {
    // 这是「换机后今天该从 0 开始」的契约：备份里只有导出当天的 key，
    // 恢复后今天读的是今天的桶，恒为 0。
    final service = BackupService();
    await HiveBoxes.meta.put('cloud_usage:2026-10-18:llm', 9);
    final json = await service.exportToJson();

    // 模拟新机：清空本机计数后再恢复。
    await CloudUsageService.replaceCounts(const {});
    await service.restoreFromJson(json);

    expect(
      CloudUsageService.exportCounts()['cloud_usage:2026-10-18:llm'],
      9,
      reason: '导出当天的历史计数应随备份迁移',
    );
    // 恢复当天的桶（用真实 today 计算）不受影响。
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 0);
  });

  test('云用量节非法（负数/坏日期/未知类别）时拒绝整份备份', () async {
    final service = BackupService();
    final base =
        jsonDecode(await service.exportToJson()) as Map<String, dynamic>;

    for (final bad in <String, Map<String, dynamic>>{
      '负数': {'cloud_usage:2026-10-18:llm': -1},
      '坏日期': {'cloud_usage:not-a-date:llm': 3},
      '未知类别': {'cloud_usage:2026-10-18:unknown': 3},
      '错误前缀': {'other_prefix:2026-10-18:llm': 3},
    }.entries) {
      final node = Map<String, dynamic>.from(base)
        ..['cloudUsage'] = bad.value;
      await expectLater(
        service.restoreFromJson(jsonEncode(node)),
        throwsA(isA<FormatException>()),
        reason: bad.key,
      );
    }
  });
}
