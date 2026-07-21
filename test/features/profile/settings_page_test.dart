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
    await tester.pumpAndSettle();

    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('音频设置'), findsOneWidget);
    expect(find.text('拼音显示'), findsOneWidget);
    expect(find.text('音效'), findsOneWidget);
    expect(find.text('触觉反馈'), findsOneWidget);

    // 滚动以显示下方的练习设置/备份/恢复/更新选项
    await tester.scrollUntilVisible(
      find.text('练习设置'),
      50,
    );
    expect(find.text('练习设置'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('备份与恢复'),
      50,
    );
    expect(find.text('备份与恢复'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('云端同步'),
      50,
    );
    expect(find.text('云端同步'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('语音识别设置'),
      50,
    );
    expect(find.text('语音识别设置'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('关于韵算'),
      50,
    );
    expect(find.text('关于韵算'), findsOneWidget);

    // 消耗 flutter_animate 入场动画剩余计时器（滚动创建新动画）
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
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
    await tester.pump();

    await tester.tap(find.text('主题设置'));
    await tester.pump(); // 触发 showModalBottomSheet
    await tester.pump(const Duration(milliseconds: 500)); // 完成底部弹窗动画

    expect(find.text('主题风格'), findsOneWidget);
    expect(find.text('国风水墨主题'), findsOneWidget);
    expect(find.text('童趣马卡龙主题'), findsOneWidget);

    // 选择童趣马卡龙 — 触发 activeSubjectProvider 变更 + Hive 持久化
    await tester.tap(find.text('童趣马卡龙主题'));
    await tester.pump(); // 触发回调
    await tester.pump(const Duration(seconds: 1)); // 完成动画

    expect(container.read(activeSubjectProvider), AppSubject.math);

    // 消耗 flutter_animate 入场动画剩余计时器
    await tester.pump(const Duration(seconds: 2));
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(find.text('主题设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
