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

/// 模拟 Hive 落盘失败（磁盘满 / Box 损坏）。
class _FailingSettingsRepository extends SettingsRepository {
  @override
  Future<void> setPinyinVisible(bool visible) async {
    throw StateError('磁盘写入失败');
  }
}

/// 定位某设置项行内的开关。
///
/// 不再用 `find.byType(Switch)`：同组开关数会随分组调整变化（如「外观与
/// 反馈」含音效 + 触觉两个），裸 byType 会 ambiguous 失败。按标题定位对
/// 分组变动免疫。
Finder _switchOf(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(AppTile)),
      matching: find.byType(Switch),
    );

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('设置页应只显示八个分类入口', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppTile), findsNWidgets(8));
    expect(find.text('学习与内容'), findsOneWidget);
    expect(find.text('AI 设置'), findsOneWidget);
    expect(find.text('语音与音频'), findsOneWidget);
    expect(find.text('外观与反馈'), findsOneWidget);
    expect(find.text('通知提醒'), findsOneWidget);
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

    // 学习与内容：学习背景 + 练习参数 + 拼音显示（拼音由外观迁入）。
    await tester.tap(find.text('学习与内容'));
    await tester.pumpAndSettle();
    expect(find.text('学习背景'), findsOneWidget);
    expect(find.text('练习设置'), findsOneWidget);
    expect(find.text('拼音显示'), findsOneWidget);
    // 通知与 AI 已不在此组。
    expect(find.text('通知设置'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // AI 设置：一级入口，点击直接进枢纽页。
    await tester.tap(find.text('AI 设置'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 语音与音频：音频设置 + 语音识别（音效/触觉已移出）。
    await tester.tap(find.text('语音与音频'));
    await tester.pumpAndSettle();
    expect(find.text('音频设置'), findsOneWidget);
    expect(find.text('语音识别设置'), findsOneWidget);
    expect(find.text('音效'), findsNothing);
    expect(find.text('触觉反馈'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 外观与反馈：主题 + 明暗 + 音效 + 触觉（拼音已移出）。
    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('音效'), findsOneWidget);
    expect(find.text('触觉反馈'), findsOneWidget);
    expect(find.text('拼音显示'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 通知提醒：hub 直达通知设置页，无中间分组页（点一次即进目标页，
    // 返回即回 hub）。
    await tester.tap(find.text('通知提醒'));
    await tester.pumpAndSettle();
    expect(find.text('通知设置'), findsOneWidget, reason: '应直达通知设置页');
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

    await tester.tap(find.text('外观与反馈'));
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

    // 拼音显示已由「外观与反馈」迁入「学习与内容」，是该组唯一的开关。
    await tester.tap(find.text('学习与内容'));
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
    // 音效与触觉反馈已由「声音与交互」迁入「外观与反馈」。
    await tester.tap(find.text('外观与反馈'));
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

    await tester.tap(find.text('学习与内容'));
    await tester.pumpAndSettle();
    await tester.tap(_switchOf('拼音显示'));
    await tester.pump();
    expect(settings.writeStarted.isCompleted, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    settings.allowWrite.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('设置写入失败：提示用户、不回滚界面、不冒泡异常', (tester) async {
    // 回归锁定：三个 Switch 原先各自内联 `onChanged: (v) async { await ... }`，
    // Hive.put 抛出的异常直接冒泡到框架 —— 用户只看到开关弹回，没有任何解释。
    // 现在统一由 `_writeSetting` 捕获并提示。
    final settings = _FailingSettingsRepository();
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

    await tester.tap(find.text('学习与内容'));
    await tester.pumpAndSettle();

    await tester.tap(_switchOf('拼音显示'));
    await tester.pumpAndSettle();

    // 异常被吞下（不冒泡），并以 SnackBar 告知用户。
    expect(tester.takeException(), isNull);
    expect(find.text('拼音显示设置保存失败，请重试'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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

    expect(find.text('外观与反馈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
