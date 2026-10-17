// test/features/profile/cloud_usage_history_page_test.dart
//
// 云用量历史页：
// - 三类各一张图 + 「今日 / 近 N 天」数字
// - x 轴为连续日期（缺数据补 0，不跳日）
// - 完全无记录时显示空态、不画空图
// - 存量脏数据不导致崩溃

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/features/profile/cloud_usage_history_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  final today = DateTime(2026, 10, 17, 10);
  CloudUsageService svc() => CloudUsageService(clock: () => today);

  String key(DateTime d, CloudUsageKind k) =>
      'cloud_usage:${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}:${k.key}';

  Future<void> pump(WidgetTester tester, CloudUsageService usage) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CloudUsageHistoryPage(usage: usage)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('有数据时三类各一张图，并显示今日与近 7 天合计', (tester) async {
    final usage = svc();
    await tester.runAsync(() async {
      await HiveBoxes.meta.put(key(today, CloudUsageKind.llm), 4);
      await HiveBoxes.meta.put(
        key(today.subtract(const Duration(days: 2)), CloudUsageKind.llm),
        6,
      );
      await HiveBoxes.meta.put(key(today, CloudUsageKind.asr), 1);
    });
    await pump(tester, usage);

    // 三张图（三个 kind 各一张）。
    expect(find.byType(BarChart), findsNWidgets(3));
    // 三类标题。
    for (final label in ['AI', '语音识别', '云朗读']) {
      expect(find.text(label), findsOneWidget);
    }
    // AI：今日 4、近 7 天合计 10（4 + 6）。
    expect(find.text('今日 4 · 近 7 天 10'), findsOneWidget);
    // 语音识别：今日 1、合计 1。
    expect(find.text('今日 1 · 近 7 天 1'), findsOneWidget);
  });

  testWidgets('x 轴为连续 7 天（含今天），缺数据不跳日', (tester) async {
    final usage = svc();
    await tester.runAsync(() async {
      // 只在 4 天前写一条，验证轴标签仍覆盖完整 7 天。
      await HiveBoxes.meta.put(
        key(today.subtract(const Duration(days: 4)), CloudUsageKind.tts),
        2,
      );
    });
    await pump(tester, usage);

    // 7 个轴标签：10/11 ... 10/17。
    for (var i = 0; i < 7; i++) {
      final d = today.subtract(Duration(days: 6 - i));
      expect(
        find.text('${d.month}/${d.day}'),
        findsWidgets,
        reason: '缺少 ${d.month}/${d.day} 的轴标签',
      );
    }
  });

  testWidgets('完全无记录时显示空态，不画空图', (tester) async {
    await pump(tester, svc());

    expect(find.text('暂无用量记录'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets('存量脏数据（非数字/负数）不导致崩溃', (tester) async {
    final usage = svc();
    await tester.runAsync(() async {
      await HiveBoxes.meta.put(key(today, CloudUsageKind.llm), 'oops');
      await HiveBoxes.meta.put(key(today, CloudUsageKind.asr), -5);
      // 让页面至少有数据可渲染（否则走空态分支）。
      await HiveBoxes.meta.put(key(today, CloudUsageKind.tts), 3);
    });
    await pump(tester, usage);

    expect(tester.takeException(), isNull);
    // 脏数据读作 0，云朗读为 3。
    expect(find.text('今日 0 · 近 7 天 0'), findsNWidgets(2));
    expect(find.text('今日 3 · 近 7 天 3'), findsOneWidget);
  });
}
