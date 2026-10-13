// test/core/routing/app_router_test.dart
//
// 深链 / 进程恢复白屏回归：四条依赖 `GoRouterState.extra` 的路由在 extra
// 缺失或类型不符时必须渲染兜底页而非抛 TypeError；未匹配路径走 errorBuilder。
//
// 直达深层路由用 `createAppRouter(initialLocation:)`，避免启动页触发真实数据导入。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/models/llm_problem.dart';

void main() {
  /// 直达 [location] 并返回 router（兜底页不依赖 Hive / provider，可裸挂载）。
  Future<GoRouter> pumpAt(WidgetTester tester, String location) async {
    final router = createAppRouter(initialLocation: location);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  group('extra 缺失时渲染兜底页而非白屏', () {
    final cases = <String, ({String path, String title, String fallbackLabel})>{
      '练习详情': (
        path: AppRoutes.mathSessionDetail,
        title: '练习详情',
        fallbackLabel: '前往练习历史',
      ),
      '错题详情': (
        path: AppRoutes.mathMistakeDetail,
        title: '错题详情',
        fallbackLabel: '前往错题本',
      ),
      '家长预览': (
        path: AppRoutes.wordProblemPreview,
        title: '家长预览',
        fallbackLabel: '重新生成题目',
      ),
      '应用题练习': (
        path: AppRoutes.wordProblemPractice,
        title: '应用题练习',
        fallbackLabel: '前往题库',
      ),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key}：深链直达不崩溃，给出重新进入入口', (tester) async {
        await pumpAt(tester, entry.value.path);

        expect(tester.takeException(), isNull);
        expect(find.text(entry.value.title), findsOneWidget);
        expect(find.text('页面数据已失效'), findsOneWidget);
        expect(find.text(entry.value.fallbackLabel), findsOneWidget);
      });
    }

    testWidgets('extra 类型不符（如旧版本传了 Map）同样走兜底页', (tester) async {
      // 从另一条兜底路由出发（兜底页不依赖 provider），跳转后标题变化即证明
      // 新的 extra 确实走了类型校验分支。
      final router = await pumpAt(tester, AppRoutes.wordProblemPreview);
      router.go(AppRoutes.mathMistakeDetail, extra: <String, String>{});
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('错题详情'), findsOneWidget);
      expect(find.text('页面数据已失效'), findsOneWidget);
    });

    testWidgets('应用题练习收到空题目列表也走兜底页（避免 RangeError）', (tester) async {
      final router = await pumpAt(tester, AppRoutes.mathSessionDetail);
      router.go(AppRoutes.wordProblemPractice, extra: const <LlmProblem>[]);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('应用题练习'), findsOneWidget);
      expect(find.text('页面数据已失效'), findsOneWidget);
    });
  });

  testWidgets('未匹配路径走 errorBuilder，显示中文兜底页', (tester) async {
    await pumpAt(tester, '/not-a-real-page');

    expect(tester.takeException(), isNull);
    expect(find.text('页面不存在'), findsOneWidget);
    expect(find.textContaining('/not-a-real-page'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
  });
}
