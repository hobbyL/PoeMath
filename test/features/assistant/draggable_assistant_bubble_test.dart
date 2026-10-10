// test/features/assistant/draggable_assistant_bubble_test.dart
//
// 全局悬浮气泡（DraggableAssistantBubble）组件测试：
//   - 显示：气泡与 smart_toy 图标存在；
//   - 拖拽：松手贴最近水平边，位置发生变化；
//   - 点击：经 appRouterProvider 跳转助手页（AppRoutes.assistant）。
// 导航用记录型假 GoRouter 覆写 appRouterProvider，断言 push 调用，不触碰
// 真实路由栈 / 助手页依赖。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
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

Future<_RecordingRouter> _pumpBubble(WidgetTester tester) async {
  final router = _RecordingRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[appRouterProvider.overrideWithValue(router)],
      child: const MaterialApp(
        home: Scaffold(body: DraggableAssistantBubble()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
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
    final router = await _pumpBubble(tester);

    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();

    expect(router.pushed, <String>[AppRoutes.assistant]);
  });

  testWidgets('气泡空白区不拦截底层内容点击（命中透传）', (tester) async {
    var underlyingTaps = 0;
    final router = _RecordingRouter();
    addTearDown(router.dispose);

    // 复刻 MainShell 结构：底层内容在下、全尺寸气泡覆盖层在上。
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[appRouterProvider.overrideWithValue(router)],
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
}
