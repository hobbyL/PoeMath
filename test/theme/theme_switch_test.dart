// test/theme/theme_switch_test.dart
//
// 主题切换 widget 测试：当 activeSubjectProvider 从 poem 切到 math 时，
// lightThemeProvider 派生的 ThemeData 的主色应从墨绿变为薰衣草紫。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/theme_providers.dart';

import '../helpers/hive_test_helper.dart';

void main() {
  test('AppTheme.resolve 返回不同 subject 的正确主色', () {
    final poemLight =
        AppTheme.resolve(subject: AppSubject.poem, brightness: Brightness.light);
    expect(poemLight.colorScheme.primary, ColorTokens.poemGreen);

    final mathLight =
        AppTheme.resolve(subject: AppSubject.math, brightness: Brightness.light);
    expect(mathLight.colorScheme.primary, ColorTokens.mathPurple);
  });

  group('widget 主题切换', () {
    setUp(() async {
      await setUpHiveForTesting();
    });

    tearDown(() async {
      await tearDownHiveForTesting();
    });

    testWidgets('切换 activeSubject 时派生的 lightTheme 应随之变化', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const App(),
        ),
      );
      // 让 splash + 路由跳转完成（用 pump 代替 pumpAndSettle 避免动画超时）
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // 初始 poem 主题
      final ThemeData light1 = container.read(lightThemeProvider);
      expect(light1.colorScheme.primary, ColorTokens.poemGreen);

      // 切到 math
      container.read(activeSubjectProvider.notifier).state = AppSubject.math;
      await tester.pump();

      final ThemeData light2 = container.read(lightThemeProvider);
      expect(light2.colorScheme.primary, ColorTokens.mathPurple);
    });
  });
}
