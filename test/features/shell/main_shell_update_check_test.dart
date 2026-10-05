import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_check_controller.dart';
import 'package:poemath/core/services/update/update_client.dart';
import 'package:poemath/features/shell/main_shell.dart';

/// 记录 maybeCheck 调用次数的 spy 控制器（基类依赖从不执行）。
class _SpyUpdateController extends UpdateCheckController {
  _SpyUpdateController()
      : super(
          updateCheckConfigured: true,
          client: _NoopUpdateClient(),
          installer: AndroidUpdateInstaller(isAndroid: false),
          onAvailable: (update, current) {},
        );

  int checkCount = 0;

  @override
  Future<void> maybeCheck() async {
    checkCount++;
  }
}

class _NoopUpdateClient extends UpdateClient {
  _NoopUpdateClient() : super(updateUrl: 'https://example.com/latest.json');
}

GoRouter _router(_SpyUpdateController controller) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => MainShell(
          updateCheckController: controller,
          child: const Scaffold(body: Center(child: Text('tab-child'))),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('冷启动首帧后恰触发一次自动检测', (tester) async {
    final spy = _SpyUpdateController();
    final router = _router(spy);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    // postFrameCallback 在 pumpWidget 的帧末已执行。
    expect(spy.checkCount, 1);

    // 后续帧不重复触发。
    await tester.pump();
    expect(spy.checkCount, 1);

    expect(find.text('tab-child'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('前台恢复再次触发检测', (tester) async {
    final spy = _SpyUpdateController();
    final router = _router(spy);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(spy.checkCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spy.checkCount, 2);
  });

  testWidgets('销毁后不再接收生命周期回调且重新挂载无异常', (tester) async {
    final spy = _SpyUpdateController();
    final router = _router(spy);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(spy.checkCount, 1);

    // 移除 MainShell（触发 dispose → removeObserver）。
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spy.checkCount, 1);

    // 重新挂载新的 MainShell + 新控制器，正常工作。
    final spy2 = _SpyUpdateController();
    final router2 = _router(spy2);
    addTearDown(router2.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router2));
    await tester.pump();
    expect(spy2.checkCount, 1);
    expect(find.text('tab-child'), findsOneWidget);
  });
}
