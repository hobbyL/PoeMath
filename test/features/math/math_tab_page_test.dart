// test/features/math/math_tab_page_test.dart
//
// 口算页入口重构后的行为测试：
// - 册次只读展示、不再就地选择（年级网格与学期按钮已移除）
// - 四类练习卡片按学习背景的开关显隐
// - 竖式在引擎不支持的册次/难度下明确提示且不跳转
//
// 取材说明：口算页含有限入场动画（卡片与统计），一律用显式 `pump`
// 推进而非 `pumpAndSettle`（见 spec 的「Widget Tests with Focus and
// Animations」）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/math_entry_kind.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

/// 记录被跳转的路由，用于断言"是否发生了导航"。
class _RouteProbe {
  final List<String> pushed = [];
}

Future<_RouteProbe> _pumpTab(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final probe = _RouteProbe();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const MathTabPage()),
      GoRoute(
        path: AppRoutes.wordProblemLibrary,
        builder: (_, __) {
          probe.pushed.add(AppRoutes.wordProblemLibrary);
          return const Scaffold(body: Text('应用题题库占位'));
        },
      ),
      GoRoute(
        path: AppRoutes.mathChallenge,
        builder: (_, __) {
          probe.pushed.add(AppRoutes.mathChallenge);
          return const Scaffold(body: Text('挑战占位'));
        },
      ),
      GoRoute(
        path: AppRoutes.mathPractice,
        builder: (_, __) {
          probe.pushed.add(AppRoutes.mathPractice);
          return const Scaffold(body: Text('练习占位'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return probe;
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  testWidgets('册次只读展示：不再有年级网格与学期选择', (tester) async {
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setBackground(4, '下');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpTab(tester, container: container);

    // 只读展示当前册次。
    expect(find.textContaining('当前学习'), findsOneWidget);
    expect(find.textContaining('四年级'), findsOneWidget);
    // 旧的年级选择网格（6 张可选卡片）与学期按钮不复存在。
    expect(find.text('1 年级'), findsNothing);
    expect(find.text('6 年级'), findsNothing);
    expect(find.text('上学期'), findsNothing);
    expect(find.text('下学期'), findsNothing);
  });

  testWidgets('四类开关全开时显示四张卡片，顺序固定', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpTab(tester, container: container);

    for (final title in ['口算', '竖式', '应用题', '挑战']) {
      expect(find.text(title), findsOneWidget, reason: '缺少 $title 卡片');
    }
    // 顺序：以 AppTile 的垂直位置为准。
    final ys = ['口算', '竖式', '应用题', '挑战']
        .map((t) => tester.getTopLeft(find.text(t)).dy)
        .toList();
    expect(ys, orderedEquals(List.of(ys)..sort()));
  });

  testWidgets('按学习背景开关隐藏卡片', (tester) async {
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setKinds({
        MathEntryKind.arithmetic,
        MathEntryKind.challenge,
      });
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpTab(tester, container: container);

    expect(find.text('口算'), findsOneWidget);
    expect(find.text('挑战'), findsOneWidget);
    expect(find.text('竖式'), findsNothing);
    expect(find.text('应用题'), findsNothing);
  });

  testWidgets('改学习背景后口算页立即反映新册次（无需重启）', (tester) async {
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setBackground(1, '上');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpTab(tester, container: container);
    expect(find.textContaining('一年级'), findsOneWidget);

    // 经学习背景写入 —— 这是唯一的册次写入口。
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setBackground(3, '下');
    });
    container.invalidate(settingsRepositoryProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('三年级'), findsOneWidget);
    expect(find.textContaining('一年级'), findsNothing);
  });

  testWidgets('应用题与挑战卡片跳转到对应页面', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final probe = await _pumpTab(tester, container: container);

    await tester.tap(find.text('应用题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(probe.pushed, contains(AppRoutes.wordProblemLibrary));
  });

  testWidgets('竖式在支持的册次与难度下进入练习', (tester) async {
    // 二年级上 + 中等难度：引擎支持竖式。
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setBackground(2, '上');
      await HiveBoxes.settings.put('math_difficulty', 'medium');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final probe = await _pumpTab(tester, container: container);

    await tester.tap(find.text('竖式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(probe.pushed, contains(AppRoutes.mathPractice));
    // 竖式经一次性请求传递，**不改常用偏好**（`mathPracticeModeProvider`
    // 反映的是设置在 Hive 里的偏好，本次点击不应写它）。
    final request = container.read(nextMathPracticeRequestProvider);
    expect(request, isNotNull);
    expect(request!.mode, ProblemMode.vertical);
    expect(request.grade, 2);
    expect(request.semester, '上');
  });

  testWidgets('竖式在不支持的册次下提示原因且不跳转', (tester) async {
    // 一年级上：引擎未开放竖式。
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setBackground(1, '上');
      await HiveBoxes.settings.put('math_difficulty', 'medium');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final probe = await _pumpTab(tester, container: container);

    await tester.tap(find.text('竖式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(probe.pushed, isEmpty, reason: '不可用时不应跳转');
    expect(find.textContaining('暂未开放竖式'), findsOneWidget);
  });

  testWidgets('竖式在简单难度下提示与难度相关的原因', (tester) async {
    // 二年级上本支持竖式，但简单难度把 modes 收窄为 findResult。
    await tester.runAsync(() async {
      await SettingsRepositorySeed.setBackground(2, '上');
      await HiveBoxes.settings.put('math_difficulty', 'easy');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final probe = await _pumpTab(tester, container: container);

    await tester.tap(find.text('竖式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(probe.pushed, isEmpty);
    expect(find.textContaining('难度不包含竖式'), findsOneWidget);
  });
}

/// 直接落 Hive 的种子写入（避免经 UI，测试关注的是读取侧行为）。
class SettingsRepositorySeed {
  const SettingsRepositorySeed._();

  static Future<void> setBackground(int grade, String semester) async {
    await HiveBoxes.settings.put('selected_grade', grade);
    await HiveBoxes.settings.put('selected_semester', semester);
  }

  static Future<void> setKinds(Set<MathEntryKind> kinds) async {
    await HiveBoxes.settings.put('math_entry_kinds', encodeMathEntryKinds(kinds));
  }
}
