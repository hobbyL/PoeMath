// test/core/routing/route_fallback_page_test.dart
//
// 兜底页本体：两种构造的文案正确，且按钮用 go 重置路由栈（深链场景没有上一页）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/route_fallback_page.dart';

void main() {
  /// 两条路由的最小 router：'/' 挂兜底页，'/target' 作为跳转落点。
  Future<GoRouter> pumpFallback(WidgetTester tester, Widget page) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => page),
        GoRoute(
          path: '/target',
          builder: (_, __) => const Scaffold(body: Text('落点页')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('dataMissing：标题沿用目标页，按钮跳到重新进入的入口', (tester) async {
    final router = await pumpFallback(
      tester,
      const RouteFallbackPage.dataMissing(
        title: '错题详情',
        fallbackLocation: '/target',
        fallbackLabel: '前往错题本',
      ),
    );

    expect(find.text('错题详情'), findsOneWidget);
    expect(find.text('页面数据已失效'), findsOneWidget);
    expect(find.textContaining('这个页面需要的数据不会被保留'), findsOneWidget);

    await tester.tap(find.text('前往错题本'));
    await tester.pumpAndSettle();

    expect(find.text('落点页'), findsOneWidget);
    // go 而非 pop：深链/进程恢复时栈里本就没有上一页。
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/target',
    );
  });

  testWidgets('notFound：显示出错路径并提供返回首页', (tester) async {
    await pumpFallback(
      tester,
      const RouteFallbackPage.notFound(path: '/legacy/removed'),
    );

    expect(find.text('页面不存在'), findsOneWidget);
    expect(find.textContaining('/legacy/removed'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
  });
}
