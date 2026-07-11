// test/shell/main_shell_test.dart
//
// MainShell 5-Tab 点击测试：点击"口算" tab 后 activeSubjectProvider 应变为
// AppSubject.math。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/features/shell/widgets/notched_bottom_bar.dart';

void main() {
  testWidgets('点击底部 tab 应切换页面并同步 activeSubject', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );

    // splash → shell
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(NotchedBottomBar), findsOneWidget);

    // 点击"口算"
    await tester.tap(find.text('口算'));
    await tester.pumpAndSettle();

    expect(container.read(activeSubjectProvider), AppSubject.math);

    // 点击"诗词"
    await tester.tap(find.text('诗词'));
    await tester.pumpAndSettle();

    expect(container.read(activeSubjectProvider), AppSubject.poem);
  });
}
