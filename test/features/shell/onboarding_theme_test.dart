import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/app_appearance.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/shell/onboarding_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  testWidgets('引导切换四主题和明暗保留当前页，横屏大字仍可继续', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pageKey = GlobalKey();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    State? original;
    for (final subject in AppSubject.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.resolve(
          subject: subject,
          brightness: brightness,
        );
        for (final size in [const Size(320, 640), const Size(740, 320)]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: PageAnimationScope(enabled: false, child: child!),
                ),
                home: OnboardingPage(key: pageKey),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final state = tester.state(find.byType(OnboardingPage));
          if (original == null) {
            original = state;
            await tester.tap(find.text('下一步'));
            await tester.pumpAndSettle();
          }
          expect(state, same(original));
          expect(
            tester.widget<PageView>(find.byType(PageView)).controller!.page,
            1,
          );
          expect(find.byType(AppScaffold), findsOneWidget);
          final background = find.byKey(const ValueKey('theme-page-art'));
          expect(background, findsOneWidget);
          final image = tester.widget<Image>(background);
          expect(
            (image.image as ResizeImage).imageProvider,
            AssetImage(theme.appearance.pageImage),
          );
          expect(find.text('下一步').hitTestable(), findsOneWidget);
          expect(find.text('跳过').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
