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
import '../../helpers/parent_access_test_helper.dart';

class _DelayedSettingsRepository extends SettingsRepository {
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();
  final writeCompleted = Completer<void>();
  late Future<void> storageWrite;

  @override
  Future<void> setPageAnimationsEnabled(bool enabled) async {
    writeStarted.complete();
    await allowWrite.future;
    storageWrite = Zone.root.run(() => super.setPageAnimationsEnabled(enabled));
    await storageWrite;
    writeCompleted.complete();
  }
}

/// 模拟 Hive 落盘失败（磁盘满 / Box 损坏）。
class _FailingSettingsRepository extends SettingsRepository {
  @override
  Future<void> setSoundEnabled(bool enabled) async {
    throw StateError('磁盘写入失败');
  }

  @override
  Future<void> setPageAnimationsEnabled(bool enabled) async {
    throw StateError('磁盘写入失败');
  }
}

/// 定位某设置项行内的开关。
///
/// 不再用 `find.byType(Switch)`：同组开关数会随分组调整变化（如「外观与
/// 反馈」含页面动画、音效和触觉反馈），裸 byType 会 ambiguous 失败。按标题定位对
/// 分组变动免疫。
Finder _switchOf(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(AppTile)),
      matching: find.byType(Switch),
    );

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
  });

  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  testWidgets('设置首页只显示五个用途分类', (tester) async {
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
    expect(
      tester
          .widgetList<AppTile>(find.byType(AppTile))
          .map((tile) => tile.title),
      ['外观与反馈', '学习与内容', 'AI 与语音', '家长与数据', '应用与提醒'],
    );
    expect(find.text('AI 设置'), findsNothing);
    expect(find.text('家长保护与云额度'), findsNothing);
    expect(find.text('通知提醒'), findsNothing);
    expect(find.text('关于韵算'), findsNothing);
    expect(find.text('主题设置'), findsNothing);
    expect(find.text('音效'), findsNothing);
    expect(find.byType(Switch), findsNothing);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('五个分类展示对应设置项并能进入AI与提醒子页', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 学习与内容：学习配置、书籍和题库。
    await tester.tap(find.text('学习与内容'));
    await tester.pumpAndSettle();
    expect(find.text('学习背景'), findsOneWidget);
    expect(find.text('看图说话题库'), findsOneWidget);
    expect(find.text('管理题目与启用状态'), findsOneWidget);
    expect(find.text('练习设置'), findsOneWidget);
    expect(find.text('书籍管理'), findsOneWidget);
    expect(find.text('拼音显示'), findsNothing);
    expect(find.text('通知设置'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // AI 与语音：模型服务、朗读与识别配置集中展示。
    await tester.tap(find.text('AI 与语音'));
    await tester.pumpAndSettle();
    expect(find.text('AI 设置'), findsOneWidget);
    expect(find.text('音频设置'), findsOneWidget);
    expect(find.text('语音识别设置'), findsOneWidget);
    expect(find.text('音效'), findsNothing);
    expect(find.text('触觉反馈'), findsNothing);
    await tester.tap(find.text('AI 设置'));
    await tester.pumpAndSettle();
    expect(find.text('供应商设置'), findsOneWidget);
    expect(find.text('使用场景设置'), findsOneWidget);
    expect(find.text('提示词设置'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('音频设置'), findsOneWidget);
    expect(find.text('语音识别设置'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 外观与反馈：主题、明暗、页面动画、音效与触觉。
    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('音效'), findsOneWidget);
    expect(find.text('触觉反馈'), findsOneWidget);
    expect(find.text('拼音显示'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 应用与提醒：通知配置和版本、隐私入口。
    await tester.tap(find.text('应用与提醒'));
    await tester.pumpAndSettle();
    expect(find.text('通知提醒'), findsOneWidget);
    expect(find.text('关于韵算'), findsOneWidget);
    await tester.tap(find.text('通知提醒'));
    await tester.pumpAndSettle();
    expect(find.text('通知设置'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('关于韵算'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 家长与数据：保护、额度与备份集中管理。
    await tester.tap(find.text('家长与数据'));
    await tester.pumpAndSettle();
    expect(find.text('家长保护与云额度'), findsOneWidget);
    expect(find.text('存储管理'), findsOneWidget);
    expect(find.text('书籍管理'), findsNothing);
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

    final settings = container.read(settingsRepositoryProvider);

    // 音效与触觉反馈由「外观与反馈」承载（「学习与内容」已无可即时切换的
    // 项 —— 拼音显示开关随详情页拼音改折叠卡一并移除）。
    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(3));
    expect(find.text('页面动画'), findsOneWidget);
    expect(settings.pageAnimationsEnabled, isTrue);
    await tester.runAsync(() async {
      await tester.tap(_switchOf('页面动画'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(settings.pageAnimationsEnabled, isFalse);
    expect(find.text('已关闭 · 使用系统默认动画'), findsOneWidget);

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

  testWidgets('动画保存期间离开分类页不访问销毁的ref，保存结果仍刷新全局偏好', (tester) async {
    final settings = _DelayedSettingsRepository();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      pageAnimationsEnabledProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(_switchOf('页面动画')));
    await tester.pump();
    expect(settings.writeStarted.isCompleted, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    settings.allowWrite.complete();
    await tester.pump();
    await tester.runAsync(() => settings.storageWrite);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(settings.writeCompleted.isCompleted, isTrue);
    expect(container.read(pageAnimationsEnabledProvider), isFalse);
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

    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();

    await tester.tap(_switchOf('音效'));
    await tester.pumpAndSettle();

    // 异常被吞下（不冒泡），并以 SnackBar 告知用户。
    expect(tester.takeException(), isNull);
    expect(find.text('音效设置保存失败，请重试'), findsOneWidget);

    await tester.tap(_switchOf('页面动画'));
    await tester.pumpAndSettle();
    expect(find.text('页面动画设置保存失败，请重试'), findsOneWidget);
    expect(settings.pageAnimationsEnabled, isTrue);
    expect(tester.widget<Switch>(_switchOf('页面动画')).value, isTrue);

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
    await tester.tap(find.text('外观与反馈'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_switchOf('页面动画'));
    await tester.pumpAndSettle();
    expect(find.text('页面动画'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
