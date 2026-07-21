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
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';

import '../helpers/hive_test_helper.dart';

void main() {
  test('AppTheme.resolve 返回不同 subject 的正确主色', () {
    final poemLight = AppTheme.resolve(
      subject: AppSubject.poem,
      brightness: Brightness.light,
    );
    expect(poemLight.colorScheme.primary, ColorTokens.poemGreen);

    final mathLight = AppTheme.resolve(
      subject: AppSubject.math,
      brightness: Brightness.light,
    );
    expect(mathLight.colorScheme.primary, ColorTokens.mathPurple);
  });

  group('widget 主题切换', () {
    setUp(() async {
      await setUpHiveForTesting();
    });

    tearDown(() async {
      await tearDownHiveForTesting();
    });

    test('外观模式从 Hive 恢复并在修改后持久化', () async {
      await HiveBoxes.settings.put('theme_mode', 'dark');
      final firstContainer = ProviderContainer();

      expect(firstContainer.read(themeModeProvider), ThemeMode.dark);
      firstContainer.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      await Future<void>.delayed(Duration.zero);
      await HiveBoxes.settings.flush();
      expect(HiveBoxes.settings.get('theme_mode'), 'light');
      firstContainer.dispose();

      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      expect(secondContainer.read(themeModeProvider), ThemeMode.light);
    });

    test('无效外观模式回退为跟随系统', () async {
      await HiveBoxes.settings.put('theme_mode', 'invalid');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('恢复后统一刷新立即重建主题风格和外观模式', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeSubjectProvider), AppSubject.poem);
      expect(container.read(themeModeProvider), ThemeMode.system);

      await HiveBoxes.settings.put('active_subject', 'math');
      await HiveBoxes.settings.put('theme_mode', 'dark');
      invalidateAllHiveProviders(container.invalidate);

      expect(container.read(activeSubjectProvider), AppSubject.math);
      expect(container.read(themeModeProvider), ThemeMode.dark);
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
      // 消耗 MainShell IndexedStack 中所有 tab 的 flutter_animate 入场动画
      await tester.pump(const Duration(seconds: 3));

      // 初始 poem 主题
      final ThemeData light1 = container.read(lightThemeProvider);
      expect(light1.colorScheme.primary, ColorTokens.poemGreen);

      // 切到 math
      container
          .read(activeSubjectProvider.notifier)
          .setSubject(AppSubject.math);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final ThemeData light2 = container.read(lightThemeProvider);
      expect(light2.colorScheme.primary, ColorTokens.mathPurple);
    });
  });
}
