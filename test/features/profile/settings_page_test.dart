import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/features/profile/settings_page.dart';

void main() {
  testWidgets('主题风格和外观控件应更新对应设置', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    expect(find.text('主题风格'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.byType(SegmentedButton<AppSubject>), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.text('口算'));
    await tester.pump();
    expect(container.read(activeSubjectProvider), AppSubject.math);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('窄屏和大字号下设置页不应溢出', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.binding.setSurfaceSize(const Size(320, 720));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('主题风格'), findsOneWidget);
    expect(find.byType(SegmentedButton<AppSubject>), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('口算'));
    await tester.pump();

    expect(container.read(activeSubjectProvider), AppSubject.math);
    expect(tester.takeException(), isNull);
  });
}
