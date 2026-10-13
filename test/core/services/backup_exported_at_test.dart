// test/core/services/backup_exported_at_test.dart
//
// `BackupService.exportedAt` 的解析契约：跨设备冲突检测完全依赖它，
// 解析口径漂移会让闸门静默失效（要么永不提醒，要么误拦所有恢复）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';

void main() {
  test('解析合法 ISO 时间戳', () {
    final json = jsonEncode(<String, dynamic>{
      'version': 1,
      'exportedAt': '2026-10-13T09:30:00.000',
    });
    expect(BackupService.exportedAt(json), DateTime(2026, 10, 13, 9, 30));
  });

  test('非法 JSON 返回 null（不抛异常，不阻断恢复）', () {
    expect(BackupService.exportedAt('not json at all'), isNull);
  });

  test('顶层不是对象返回 null', () {
    expect(BackupService.exportedAt('[1, 2, 3]'), isNull);
  });

  test('字段缺失返回 null（老版本备份的常见形态）', () {
    // 老备份没有 exportedAt：不能判定时间线，调用方据此跳过冲突检测。
    expect(BackupService.exportedAt(jsonEncode({'version': 1})), isNull);
  });

  test('字段类型不是字符串返回 null', () {
    expect(
      BackupService.exportedAt(jsonEncode({'exportedAt': 12345})),
      isNull,
    );
    expect(
      BackupService.exportedAt(jsonEncode({'exportedAt': null})),
      isNull,
    );
  });

  test('字符串不是合法日期返回 null', () {
    expect(
      BackupService.exportedAt(jsonEncode({'exportedAt': '昨天'})),
      isNull,
    );
  });

  test('自身导出结果可被解析（导出/解析同源）', () {
    // 不依赖 Hive：直接构造导出形态的 JSON，锁定字段名与格式一致。
    final json = jsonEncode(<String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
    });
    expect(BackupService.exportedAt(json), isNotNull);
  });
}
