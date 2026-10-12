// test/features/assistant/draggable_assistant_bubble_test.dart
//
// 全局悬浮气泡（DraggableAssistantBubble）组件测试：
//   - 显示：气泡与 smart_toy 图标存在；
//   - 拖拽：松手贴最近水平边，位置发生变化；
//   - 点击：经 appRouterProvider 跳转助手页（AppRoutes.assistant）；
//   - 持久化：拖拽落点写入设置仓储，重建恢复，越界回落默认角。
// 导航用记录型假 GoRouter 覆写 appRouterProvider，断言 push 调用，不触碰
// 真实路由栈 / 助手页依赖；位置读写用内存替身覆写 settingsRepositoryProvider
// （真实 Hive 落盘 roundtrip 见 test/data/repositories/settings_repository_test.dart）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/assistant/widgets/draggable_assistant_bubble.dart';

/// 记录型假 GoRouter：覆写 [push] 记录目标路由，不执行真实导航。
/// 走 [GoRouter.routingConfig] 生成构造（默认 `GoRouter(...)` 为工厂，
/// 子类无法 super 调用）。
class _RecordingRouter extends GoRouter {
  _RecordingRouter()
      : super.routingConfig(
          routingConfig: ValueNotifier<RoutingConfig>(
            RoutingConfig(
              routes: <RouteBase>[
                GoRoute(
                  path: '/',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );

  final List<String> pushed = <String>[];

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    pushed.add(location);
    return Future<T?>.value(null);
  }
}

/// 内存版设置仓储：只覆写悬浮球坐标读写，避开真实 Hive 文件 IO。
///
/// widget 测试跑在 fake-async 区，而落盘由手势回调（`_onPanEnd`）在区内
/// 发起——真实文件写入在该区永不完成，`pumpAndSettle` 会一直等到 10 分钟
/// 超时。故组件测试统一用本替身验证「写了什么 / 读了什么」，键名与 Hive
/// roundtrip 由 settings_repository_test.dart 覆盖。
class _FakeSettingsRepository extends SettingsRepository {
  double? _dx;
  double? _dy;

  /// 预置已持久化的坐标（模拟上次启动的存档）。
  void seed({required double dx, required double dy}) {
    _dx = dx;
    _dy = dy;
  }

  @override
  double? get assistantBubbleDx => _dx;

  @override
  double? get assistantBubbleDy => _dy;

  @override
  Future<void> setAssistantBubbleDx(double dx) async {
    _dx = dx;
  }

  @override
  Future<void> setAssistantBubbleDy(double dy) async {
    _dy = dy;
  }
}

/// 气泡宿主树；[bubbleKey] 变更可强制新建 State（模拟重启后的首帧恢复）。
Widget _bubbleTree({
  required GoRouter router,
  required SettingsRepository settings,
  Key? bubbleKey,
}) {
  return ProviderScope(
    overrides: <Override>[
      appRouterProvider.overrideWithValue(router),
      settingsRepositoryProvider.overrideWithValue(settings),
    ],
    child: MaterialApp(
      home: Scaffold(body: DraggableAssistantBubble(key: bubbleKey)),
    ),
  );
}

Future<({_RecordingRouter router, _FakeSettingsRepository settings})>
    _pumpBubble(
  WidgetTester tester, {
  _FakeSettingsRepository? settings,
  Key? bubbleKey,
}) async {
  final router = _RecordingRouter();
  addTearDown(router.dispose);
  final repo = settings ?? _FakeSettingsRepository();
  await tester.pumpWidget(
    _bubbleTree(router: router, settings: repo, bubbleKey: bubbleKey),
  );
  await tester.pumpAndSettle();
  return (router: router, settings: repo);
}

/// 读取气泡当前 [AnimatedPositioned]（唯一一个）。
AnimatedPositioned _positioned(WidgetTester tester) {
  return tester.widget<AnimatedPositioned>(
    find.descendant(
      of: find.byType(DraggableAssistantBubble),
      matching: find.byType(AnimatedPositioned),
    ),
  );
}

void main() {
  testWidgets('显示：气泡与 smart_toy 图标存在', (tester) async {
    await _pumpBubble(tester);

    expect(find.byType(DraggableAssistantBubble), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    // 圆形面走 Material + CircleBorder（非 BoxDecoration）。
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(DraggableAssistantBubble),
        matching: find.byType(Material),
      ),
    );
    expect(material.shape, isA<CircleBorder>());
  });

  testWidgets('拖拽后位置变化并贴最近水平边', (tester) async {
    await _pumpBubble(tester);

    final initialLeft = _positioned(tester).left!;
    final initialTop = _positioned(tester).top!;

    // 默认在右下角，向左上大幅拖拽越过屏幕中线 → 应吸附到左边。
    await tester.drag(
      find.byIcon(Icons.smart_toy_outlined),
      const Offset(-400, -100),
    );
    await tester.pumpAndSettle();

    final newLeft = _positioned(tester).left!;
    final newTop = _positioned(tester).top!;

    // 水平贴左边：left 明显变小。
    expect(newLeft, lessThan(initialLeft));
    // 向上拖拽：top 变小（纵向不吸附，保留拖拽结果）。
    expect(newTop, lessThan(initialTop));
  });

  testWidgets('点击触发跳转助手页', (tester) async {
    final harness = await _pumpBubble(tester);

    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();

    expect(harness.router.pushed, <String>[AppRoutes.assistant]);
  });

  testWidgets('气泡空白区不拦截底层内容点击（命中透传）', (tester) async {
    var underlyingTaps = 0;
    final router = _RecordingRouter();
    addTearDown(router.dispose);

    // 复刻 MainShell 结构：底层内容在下、全尺寸气泡覆盖层在上。
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appRouterProvider.overrideWithValue(router),
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => underlyingTaps++,
                  child: const SizedBox.expand(),
                ),
                const DraggableAssistantBubble(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 气泡默认停在右下角；点左上角——该点落在覆盖层范围内但在圆形气泡之外，
    // 命中应透传到底层内容。
    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(underlyingTaps, 1); // 底层回调被触发
    expect(router.pushed, isEmpty); // 未误触发气泡导航

    // 反向校验：点击气泡本身触发导航，且不计入底层。
    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();

    expect(router.pushed, <String>[AppRoutes.assistant]);
    expect(underlyingTaps, 1);
  });

  testWidgets('拖拽落点写入仓储，重建后恢复到该位置', (tester) async {
    final harness = await _pumpBubble(
      tester,
      bubbleKey: const ValueKey<String>('run1'),
    );
    final repo = harness.settings;

    // 向左上拖拽（默认右下角 → 贴左边）。
    await tester.drag(
      find.byIcon(Icons.smart_toy_outlined),
      const Offset(-400, -100),
    );
    await tester.pumpAndSettle();

    final settledLeft = _positioned(tester).left!;
    final settledTop = _positioned(tester).top!;

    // 落盘值 = 贴边后的最终位置（拖拽过程不写，仅松手写一次）。
    expect(repo.assistantBubbleDx, closeTo(settledLeft, 0.5));
    expect(repo.assistantBubbleDy, closeTo(settledTop, 0.5));

    // 换 key 强制新建 State（模拟重启）：首帧从仓储恢复到贴边位置。
    await tester.pumpWidget(
      _bubbleTree(
        router: harness.router,
        settings: repo,
        bubbleKey: const ValueKey<String>('run2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_positioned(tester).left, closeTo(settledLeft, 0.5));
    expect(_positioned(tester).top, closeTo(settledTop, 0.5));
  });

  testWidgets('持久化位置越界（屏幕尺寸变化）回落默认右下角', (tester) async {
    // 基线：无存档时的默认角。
    await _pumpBubble(tester, bubbleKey: const ValueKey<String>('baseline'));
    final defaultLeft = _positioned(tester).left;
    final defaultTop = _positioned(tester).top;

    // 远超当前视口的存档：弃用 → 与无存档一致的默认角。
    final repo = _FakeSettingsRepository()..seed(dx: 99999, dy: 88888);
    await _pumpBubble(
      tester,
      settings: repo,
      bubbleKey: const ValueKey<String>('restored'),
    );

    expect(_positioned(tester).left, defaultLeft);
    expect(_positioned(tester).top, defaultTop);
  });

  testWidgets('无存档时保持默认角', (tester) async {
    final harness = await _pumpBubble(tester);

    expect(harness.settings.assistantBubbleDx, isNull);
    expect(harness.settings.assistantBubbleDy, isNull);

    // 未持久化 → 默认右下（left/top 为正的有限值）。
    final positioned = _positioned(tester);
    expect(positioned.left, greaterThan(0));
    expect(positioned.top, greaterThan(0));
  });
}
