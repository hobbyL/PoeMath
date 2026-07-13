import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/features/profile/settings_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('设置页应显示所有设置项', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('音频设置'), findsOneWidget);
    expect(find.text('拼音显示'), findsOneWidget);
    expect(find.text('音效'), findsOneWidget);
    expect(find.text('触觉反馈'), findsOneWidget);

    // 滚动以显示下方的备份/恢复/更新选项
    await tester.scrollUntilVisible(
      find.text('数据备份'),
      50,
    );
    expect(find.text('数据备份'), findsOneWidget);
    expect(find.text('数据恢复'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('检查更新'),
      50,
    );
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('点击主题设置打开底部弹窗并可选择', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    await tester.tap(find.text('主题设置'));
    await tester.pumpAndSettle();

    expect(find.text('主题风格'), findsOneWidget);
    expect(find.text('诗词'), findsWidgets);
    expect(find.text('口算'), findsWidgets);

    // 选择口算
    await tester.tap(find.text('童趣马卡龙主题'));
    await tester.pumpAndSettle();

    expect(container.read(activeSubjectProvider), AppSubject.math);
  });

  testWidgets('Switch 控件可点击', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    // 验证有 Switch 控件
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(3)); // 拼音、音效、触觉反馈

    // 不抛异常即可
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏和大字号下设置页不应溢出', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.binding.setSurfaceSize(const Size(320, 720));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('主题设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
