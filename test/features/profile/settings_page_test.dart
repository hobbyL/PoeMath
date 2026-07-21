import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/settings_page.dart';

import '../../helpers/hive_test_helper.dart';

class _DelayedSettingsRepository extends SettingsRepository {
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();

  @override
  Future<void> setPinyinVisible(bool visible) {
    writeStarted.complete();
    return allowWrite.future;
  }
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('设置页应只显示五个分类入口', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppTile), findsNWidgets(5));
    expect(find.text('外观与显示'), findsOneWidget);
    expect(find.text('声音与交互'), findsOneWidget);
    expect(find.text('学习与提醒'), findsOneWidget);
    expect(find.text('数据与同步'), findsOneWidget);
    expect(find.text('关于韵算'), findsOneWidget);
    expect(find.text('主题设置'), findsNothing);
    expect(find.text('音效'), findsNothing);
    expect(find.byType(Switch), findsNothing);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('四个分类入口应展示对应设置项', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('外观与显示'));
    await tester.pumpAndSettle();
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('拼音显示'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('声音与交互'));
    await tester.pumpAndSettle();
    expect(find.text('音频设置'), findsOneWidget);
    expect(find.text('语音识别设置'), findsOneWidget);
    expect(find.text('音效'), findsOneWidget);
    expect(find.text('触觉反馈'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('学习与提醒'));
    await tester.pumpAndSettle();
    expect(find.text('练习设置'), findsOneWidget);
    expect(find.text('通知设置'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('数据与同步'));
    await tester.pumpAndSettle();
    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('云端同步'), findsOneWidget);

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

    await tester.tap(find.text('外观与显示'));
    await tester.pumpAndSettle();
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

  testWidgets('即时开关应归入分类并保持可用', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsNothing);

    await tester.tap(find.text('外观与显示'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    final settings = container.read(settingsRepositoryProvider);
    final pinyinTile = find.ancestor(
      of: find.text('拼音显示'),
      matching: find.byType(AppTile),
    );
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: pinyinTile, matching: find.byType(Switch)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(settings.pinyinVisible, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与交互'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(2));
    final soundTile = find.ancestor(
      of: find.text('音效'),
      matching: find.byType(AppTile),
    );
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: soundTile, matching: find.byType(Switch)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(settings.soundEnabled, isFalse);

    final hapticTile = find.ancestor(
      of: find.text('触觉反馈'),
      matching: find.byType(AppTile),
    );
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: hapticTile, matching: find.byType(Switch)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(settings.hapticEnabled, isFalse);

    // 不抛异常即可
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('设置写入期间离开分类页不应访问已销毁的 ref', (tester) async {
    final settings = _DelayedSettingsRepository();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('外观与显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.writeStarted.isCompleted, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    settings.allowWrite.complete();
    await tester.pump();

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

    expect(find.text('外观与显示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
