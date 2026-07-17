// test/flow/app_navigation_flow_test.dart
//
// 流程测试：App 启动 → Tab 导航 → 首页内容验证。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/features/shell/main_shell.dart';

import '../helpers/hive_test_helper.dart';

Finder _bottomBarItem(String label) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('App 启动后 4 个 Tab 均可切换', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    // 消耗 MainShell IndexedStack 中所有 tab 的 flutter_animate 入场动画
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    for (final label in ['诗词', '口算', '我的', '首页']) {
      await tester.tap(_bottomBarItem(label));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
    // 消耗剩余 flutter_animate 计时器
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('首页显示快捷入口和今日目标', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    // 消耗 MainShell IndexedStack 中所有 tab 的 flutter_animate 入场动画
    await tester.pump(const Duration(seconds: 3));

    // 快捷入口
    expect(find.text('背诗词'), findsOneWidget);
    expect(find.text('做口算'), findsOneWidget);
    expect(find.text('查公式'), findsOneWidget);
    expect(find.text('错题本'), findsOneWidget);

    // 今日目标
    expect(find.text('今日目标'), findsOneWidget);

    // 打卡区域
    expect(find.text('打卡'), findsOneWidget);
  });
}
