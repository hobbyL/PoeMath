import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/shell/onboarding_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final scenario in [
    (const Size(320, 640), 1.0),
    (const Size(320, 640), 2.0),
    (const Size(411, 914), 2.0),
    (const Size(914, 411), 1.0),
  ]) {
    testWidgets('引导可滚动且能完成背景保存 ${scenario.$1} @${scenario.$2}', (tester) async {
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(
        () => HiveBoxes.settings.put('has_onboarded', false),
      );
      final router = GoRouter(
        initialLocation: '/onboarding',
        routes: [
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const OnboardingPage(),
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text('首页已打开')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scenario.$2)),
              child: PageAnimationScope(enabled: false, child: child!),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      for (var page = 0; page < 3; page++) {
        expect(tester.takeException(), isNull);
        expect(find.text('跳过').hitTestable(), findsOneWidget);
        expect(find.text('下一步').hitTestable(), findsOneWidget);
        final intro = find.descendant(
          of: find.byType(PageView),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(intro.first, const Offset(0, -900));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('下一步'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('3 年级'));
      await tester.tap(find.text('3 年级'));
      await tester.pump();
      await tester.ensureVisible(find.text('下学期'));
      await tester.tap(find.text('下学期'));
      await tester.pump();
      expect(find.text('开始使用').hitTestable(), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('开始使用'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 30 && find.text('首页已打开').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('首页已打开'), findsOneWidget);
      final settings = SettingsRepository();
      expect(settings.hasOnboarded, isTrue);
      expect(settings.selectedGrade, 3);
      expect(settings.selectedSemester, '下');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await drainHiveWritesForTesting(tester);
    });
  }
}
