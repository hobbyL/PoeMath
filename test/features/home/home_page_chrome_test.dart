// test/features/home/home_page_chrome_test.dart
//
// 首页顶部结构：无 AppBar、不显示应用名，等级徽章在打卡卡片首行。
//
// 背景：原先 `AppBar(title: Text('韵算'), actions: [等级徽章])`。顶部这条
// 导航栏只承载一个应用名和一个等级展示，却占掉整条高度。改为去掉 AppBar，
// 应用名不再重复（底部导航已标明「首页」），等级徽章移入打卡卡片 ——
// 连续天数、打卡状态、等级同属「个人进度」，语义一致且不新增高度。
//
// 写法约束同 `profile_page_chrome_test`：必须 override `dayKeyProvider`
// （否则 `DayKeyNotifier` 的 30 秒周期 Timer 会让 tearDown 关库挂到超时），
// 且必须用 `pump(Duration)` 推进 `AnimatedPageBody` 的入场动画。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/features/home/home_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [staticDayKeyOverride()],
      child: const MaterialApp(home: HomePage()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('顶部无 AppBar，应用名不再显示', (tester) async {
    await _pump(tester);

    expect(find.byType(AppBar), findsNothing);
    // 应用名只在 AppBar 里出现过，去掉后全树不应再有。
    expect(find.text('韵算'), findsNothing);

    await drainHiveWritesForTesting(tester);
  });

  testWidgets('等级徽章显示在打卡卡片内，与打卡状态同一行', (tester) async {
    await _pump(tester);

    // 默认等级名（未学习时 level == 0）。
    final defaultLevel = UserStats(profileId: 'default').levelName;
    expect(defaultLevel, UserStats.levelNames.first);
    expect(find.text(defaultLevel), findsOneWidget);

    // 徽章与「今日待打卡」在同一张卡片内 —— 断言两者的纵向中心接近，
    // 而不是只断言「都存在于树上」。
    final badge = tester.getCenter(find.text(defaultLevel));
    final status = tester.getCenter(find.text('今日待打卡'));
    expect((badge.dy - status.dy).abs(), lessThan(20));

    // 徽章必须真的在打卡卡片里。`ColoredCard` 渲染为 `Container`（不是
    // Material `Card`），按文本祖先定位那张卡片。
    expect(
      find.ancestor(
        of: find.text(defaultLevel),
        matching: find.byType(ColoredCard),
      ),
      findsOneWidget,
    );

    await drainHiveWritesForTesting(tester);
  });
}
