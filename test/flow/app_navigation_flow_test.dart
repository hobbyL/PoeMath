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

/// 当前高亮的 tab 下标。
///
/// 这是「路由真的跳了」的可观测证据：`MainShell` 的 `selectedIndex` 由
/// `_indexFromRoute(context)` 从真实 GoRouter 路径推导，而非自己存 state。
/// 所以断言它 == 预期值，等价于断言 `context.go(...)` 生效。
int _selectedTab(WidgetTester tester) {
  return tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForWidgetTesting();
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

    // 伪测试回归：本用例原先只在循环后断言 `takeException(), isNull`，
    // 把 `MainShell._switch` 改成空函数（彻底不跳转）照样全绿 ——
    // 标题承诺的「均可切换」完全没被验证。现在逐个断言高亮下标。
    expect(_selectedTab(tester), 0, reason: '启动应停在首页 tab');

    const expectedIndex = <String, int>{
      '诗词': 1,
      '口算': 2,
      '我的': 3,
      '首页': 0,
    };
    for (final entry in expectedIndex.entries) {
      await tester.tap(_bottomBarItem(entry.key));
      await tester.pumpAndSettle();
      expect(
        _selectedTab(tester),
        entry.value,
        reason: '点击「${entry.key}」后应切到下标 ${entry.value}',
      );
    }

    expect(tester.takeException(), isNull);
    // 消耗剩余 flutter_animate 计时器
    await tester.pump(const Duration(seconds: 2));

    // 排空 Hive 写链，否则 tearDown 的 Hive.close() 在 fake 时钟下永不返回。
    await drainHiveWritesForTesting(tester);
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

    // 排空 Hive 写链，否则 tearDown 的 Hive.close() 在 fake 时钟下永不返回。
    await drainHiveWritesForTesting(tester);
  });
}
