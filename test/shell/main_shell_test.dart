// test/shell/main_shell_test.dart
//
// MainShell 4-Tab 点击测试：点击 tab 后应正确切换页面；
// 主题由用户在设置页手动切换，tab 切换不改变主题。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/features/profile/parent_protection_page.dart';
import 'package:poemath/features/profile/settings_page.dart';

import '../helpers/day_key_override.dart';
import '../helpers/hive_test_helper.dart';

/// 等待 splash 结束并消耗所有 flutter_animate 入场动画计时器。
///
/// MainShell 的 IndexedStack 同时构建所有 tab 页面，
/// 各页面的 AnimatedPageBody / per-item .animate() 会创建 delay timers，
/// 需要足够的 pump 时间来清除。
Future<void> _pumpPastSplashAndAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 3));
}

/// 当前高亮的 tab 下标 —— 「页面真的切了」的可观测证据。
///
/// `MainShell` 不自己存选中态，`selectedIndex` 由 `_indexFromRoute(context)`
/// 从真实 GoRouter 路径推导，所以这个值变了就说明路由真的跳了。
int _selectedTab(WidgetTester tester) {
  return tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    FlutterSecureStorage.setMockInitialValues({});
    final access = ParentAccessService.instance;
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await access.initialize();
    access.lock();
  });

  tearDown(() async {
    ParentAccessService.instance.lock();
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('点击底部 tab 应切换页面，主题保持不变', (tester) async {
    // dayKey override 为静态值：跳过 DayKeyNotifier 的 30s 轮询 Timer，
    // 避免外部 container 在 pending timer 检查后 dispose 报错。
    final container = ProviderContainer(overrides: [staticDayKeyOverride()]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );

    await _pumpPastSplashAndAnimations(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    // 伪测试回归：本用例原先只断言主题不变，标题前半句「应切换页面」
    // 毫无验证 —— 把 `MainShell._switch` 改成空函数，主题当然也不变，
    // 用例照样全绿。切换本身必须单独断言。
    expect(_selectedTab(tester), 0, reason: '初始应停在首页 tab');

    // 记录初始主题
    final initialSubject = container.read(activeSubjectProvider);

    // 点击"数学" — 切换到数学页，但主题不变
    await tester.tap(find.text('数学'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(_selectedTab(tester), 2, reason: '应切到数学 tab');
    expect(container.read(activeSubjectProvider), initialSubject);

    // 点击“语文”切换到课本与诗词入口，主题仍不变。
    await tester.tap(find.text('语文'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(_selectedTab(tester), 1, reason: '应切到语文 tab');
    expect(container.read(activeSubjectProvider), initialSubject);

    // 排空 Hive 写链，否则 tearDown 的 Hive.close() 在 fake 时钟下永不返回。
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('手动设置 activeSubject 应改变主题', (tester) async {
    // dayKey override 为静态值：跳过 DayKeyNotifier 的 30s 轮询 Timer，
    // 避免外部 container 在 pending timer 检查后 dispose 报错。
    final container = ProviderContainer(overrides: [staticDayKeyOverride()]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );

    await _pumpPastSplashAndAnimations(tester);

    // 手动切换到 math 主题
    container.read(activeSubjectProvider.notifier).setSubject(AppSubject.math);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(container.read(activeSubjectProvider), AppSubject.math);

    // 切回 poem
    container.read(activeSubjectProvider.notifier).setSubject(AppSubject.poem);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(container.read(activeSubjectProvider), AppSubject.poem);

    // 排空 Hive 写链，否则 tearDown 的 Hive.close() 在 fake 时钟下永不返回。
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('我的页设置按钮在未配置时先打开家长设置', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: [staticDayKeyOverride()], child: const App()),
    );

    await _pumpPastSplashAndAnimations(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('我的'));
      await tester.pump();
    });
    // 星空与徽章会持续重绘，只等待有限的页面切换，不等待所有动画停止。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(_selectedTab(tester), 3);
    expect(find.byTooltip('设置').hitTestable(), findsOneWidget);

    // 家长验证入口会读取本地设置，交替推进真实 I/O 与导航帧。
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
    });
    for (
      var i = 0;
      i < 100 && find.byType(ParentProtectionPage).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ParentProtectionPage), findsOneWidget);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
    expect(find.textContaining('设置与管理需要家长密码，请先设置'), findsOneWidget);

    // 消耗剩余 flutter_animate 计时器
    await tester.pump(const Duration(seconds: 2));

    // 排空 Hive 写链，否则 tearDown 的 Hive.close() 在 fake 时钟下永不返回。
    await drainHiveWritesForTesting(tester);
  });
}
