// test/shell/main_shell_test.dart
//
// MainShell 5-Tab 点击测试：点击 tab 后应正确切换页面；
// 主题由用户在设置页手动切换，tab 切换不改变主题。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/features/shell/widgets/notched_bottom_bar.dart';

import '../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('点击底部 tab 应切换页面，主题保持不变', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(NotchedBottomBar), findsOneWidget);

    // 记录初始主题
    final initialSubject = container.read(activeSubjectProvider);

    // 点击"口算" — 切换到口算页，但主题不变
    await tester.tap(find.text('口算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(activeSubjectProvider), initialSubject);

    // 点击"诗词" — 切换到诗词页，主题仍不变
    await tester.tap(find.text('诗词'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(activeSubjectProvider), initialSubject);
  });

  testWidgets('手动设置 activeSubject 应改变主题', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const App(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));

    // 手动切换到 math 主题
    container.read(activeSubjectProvider.notifier).state = AppSubject.math;
    await tester.pump();

    expect(container.read(activeSubjectProvider), AppSubject.math);

    // 切回 poem
    container.read(activeSubjectProvider.notifier).state = AppSubject.poem;
    await tester.pump();

    expect(container.read(activeSubjectProvider), AppSubject.poem);
  });

  testWidgets('我的页设置按钮应打开设置页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('设置'), findsOneWidget);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('外观模式'), findsOneWidget);
  });
}
