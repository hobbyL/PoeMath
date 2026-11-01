import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/app.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';

import '../../helpers/hive_test_helper.dart';

const _targetKey = ValueKey('transition_target');
const _target = Scaffold(body: Text('目标页面', key: _targetKey));

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final useGoRouter in [true, false]) {
      testWidgets(
          '$platform ${useGoRouter ? 'GoRouter' : 'Navigator'} '
          '即时切换自定义与平台默认转场且可正常返回', (tester) async {
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(body: Text('入口')),
            ),
            GoRoute(
              path: '/target',
              pageBuilder: (context, state) => fadeSlideTransitionPage<void>(
                state: state,
                child: _target,
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        final container = ProviderContainer(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            lightThemeProvider.overrideWithValue(ThemeData(platform: platform)),
            darkThemeProvider.overrideWithValue(
              ThemeData(platform: platform, brightness: Brightness.dark),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const App(),
          ),
        );
        await tester.pumpAndSettle();

        for (final enabled in [true, false, true]) {
          await tester.runAsync(
            () => container
                .read(settingsRepositoryProvider)
                .setPageAnimationsEnabled(enabled),
          );
          // 不等待主题颜色插值结束：转场选择必须在下一帧即时生效。
          await tester.pump();
          if (useGoRouter) {
            router.push<void>('/target');
          } else {
            Navigator.of(tester.element(find.text('入口'))).push<void>(
              fadeSlideRoute<void>(builder: (_) => _target),
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
          final context = tester.element(find.byKey(_targetKey));
          final route = ModalRoute.of(context)! as PageRoute<dynamic>;
          final builder =
              Theme.of(context).pageTransitionsTheme.builders[platform]!;
          expect(route, isA<MaterialRouteTransitionMixin<dynamic>>());
          final slides = tester.widgetList<SlideTransition>(
            find.ancestor(
              of: find.byKey(_targetKey),
              matching: find.byType(SlideTransition),
            ),
          );
          if (enabled) {
            expect(builder, isA<FadeSlidePageTransitionsBuilder>());
            expect(route.transitionDuration, const Duration(milliseconds: 400));
            expect(
              route.reverseTransitionDuration,
              const Duration(milliseconds: 300),
            );
            expect(
              slides.any((slide) => slide.position.value.dy > 0.05),
              isTrue,
            );
          } else {
            final native = const PageTransitionsTheme().builders[platform]!;
            expect(builder.runtimeType, native.runtimeType);
            expect(route.transitionDuration, native.transitionDuration);
            expect(
              route.reverseTransitionDuration,
              native.reverseTransitionDuration,
            );
            expect(
              slides.any((slide) => slide.position.value.dy > 0.05),
              isFalse,
            );
            if (platform == TargetPlatform.iOS) {
              expect(
                find.ancestor(
                  of: find.byKey(_targetKey),
                  matching: find.byType(CupertinoPageTransition),
                ),
                findsOneWidget,
              );
            }
          }
          await tester.pumpAndSettle();
          Navigator.of(context).pop();
          await tester.pumpAndSettle();
          expect(find.text('入口'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
