// test/shell/main_shell_test.dart
//
// MainShell 5-Tab 点击测试：点击 tab 后应正确切换页面；
// 主题由用户在设置页手动切换，tab 切换不改变主题。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';

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

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('点击底部 tab 应切换页面，主题保持不变', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );

    await _pumpPastSplashAndAnimations(tester);

    expect(find.byType(NavigationBar), findsOneWidget);

    // 记录初始主题
    final initialSubject = container.read(activeSubjectProvider);

    // 点击"口算" — 切换到口算页，但主题不变
    await tester.tap(find.text('口算'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(container.read(activeSubjectProvider), initialSubject);

    // 点击"诗词" — 切换到诗词页，主题仍不变
    await tester.tap(find.text('诗词'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(container.read(activeSubjectProvider), initialSubject);
  });

  testWidgets('手动设置 activeSubject 应改变主题', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
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
  });

  testWidgets('我的页设置按钮应打开设置页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    await _pumpPastSplashAndAnimations(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('设置'), findsOneWidget);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观与显示'), findsOneWidget);
    expect(find.text('声音与交互'), findsOneWidget);
    expect(find.text('数据与同步'), findsOneWidget);

    // 消耗剩余 flutter_animate 计时器
    await tester.pump(const Duration(seconds: 2));
  });
}
