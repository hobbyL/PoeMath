import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/features/shell/splash_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('静态数据导入失败后可重试并进入首页', (tester) async {
    var dataAttempts = 0;
    final router = _router(
      dataInitializer: (onProgress) async {
        dataAttempts++;
        if (dataAttempts == 1) {
          throw StateError('asset unavailable');
        }
        return false;
      },
      indexBuilder: () async {},
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    expect(find.text('启动失败'), findsOneWidget);
    expect(find.text('学习资料加载失败，请重试。'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('首页已显示'), findsOneWidget);
    expect(dataAttempts, 2);
  });

  testWidgets('索引构建失败后可重新执行完整初始化', (tester) async {
    var dataAttempts = 0;
    var indexAttempts = 0;
    final router = _router(
      dataInitializer: (onProgress) async {
        dataAttempts++;
        return false;
      },
      indexBuilder: () async {
        indexAttempts++;
        if (indexAttempts == 1) {
          throw StateError('index unavailable');
        }
      },
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    expect(find.text('启动失败'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('首页已显示'), findsOneWidget);
    expect(dataAttempts, 2);
    expect(indexAttempts, 2);
  });
}

GoRouter _router({
  required SplashDataInitializer dataInitializer,
  required SplashIndexBuilder indexBuilder,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => SplashPage(
          dataInitializer: dataInitializer,
          indexBuilder: indexBuilder,
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: Text('首页已显示')),
      ),
    ],
  );
}
