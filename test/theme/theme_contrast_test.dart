import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/features/home/home_page.dart';

import '../helpers/day_key_override.dart';
import '../helpers/hive_test_helper.dart';

double _contrast(Color foreground, Color background) {
  final front = Color.alphaBlend(foreground, background).computeLuminance();
  final back = background.computeLuminance();
  return (math.max(front, back) + .05) / (math.min(front, back) + .05);
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.resolve(subject: subject, brightness: brightness);
      final scheme = theme.colorScheme;
      test('$subject/$brightness 操作、容器及信息文字对比度', () {
        final pairs = <String, (Color, Color)>{
          '主按钮': (scheme.onPrimary, scheme.primary),
          '次要按钮': (scheme.onSecondary, scheme.secondary),
          '第三色按钮': (scheme.onTertiary, scheme.tertiary),
          '错误按钮': (scheme.onError, scheme.error),
          '主色容器': (scheme.onPrimaryContainer, scheme.primaryContainer),
          '选中标签': (
            scheme.onSecondaryContainer,
            Color.alphaBlend(scheme.secondaryContainer, scheme.surface),
          ),
          '正文': (scheme.onSurface, scheme.surface),
          '次要正文': (scheme.onSurfaceVariant, scheme.surface),
        };
        final page = theme.scaffoldBackgroundColor;
        final card = Color.alphaBlend(
          scheme.primary.withValues(alpha: .08),
          page,
        );
        for (final (name, color) in [
          ('主色', scheme.primary),
          ('成功', theme.semantic.success),
          ('提醒', theme.semantic.caution),
          ('错误', scheme.error),
        ]) {
          pairs['$name/页面'] = (color, page);
          pairs['$name/卡片'] = (color, card);
          pairs['$name/徽章'] = (
            color,
            Color.alphaBlend(color.withValues(alpha: .12), page),
          );
        }
        for (final entry in pairs.entries) {
          expect(
            _contrast(entry.value.$1, entry.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: entry.key,
          );
        }
      });

      testWidgets('$subject/$brightness 首页渐变上的实际文字可读', (tester) async {
        tester.view.physicalSize = const Size(411, 914);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [staticDayKeyOverride()],
            child: MaterialApp(
              theme: theme,
              home: const PageAnimationScope(enabled: false, child: HomePage()),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final cardFinder = find.byWidgetPredicate(
          (widget) => widget is ColoredCard && widget.gradient != null,
        );
        expect(cardFinder, findsOneWidget);
        final card = tester.widget<ColoredCard>(cardFinder);
        for (final color in card.gradient!.colors) {
          final background = Color.alphaBlend(
            color,
            theme.scaffoldBackgroundColor,
          );
          for (final label in ['今日待打卡', '天连续']) {
            final text = tester.widget<Text>(find.text(label));
            expect(
              _contrast(text.style!.color!, background),
              greaterThanOrEqualTo(4.5),
              reason: label,
            );
          }
        }
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '打卡'),
        );
        expect(
          _contrast(
            button.style!.foregroundColor!.resolve({})!,
            button.style!.backgroundColor!.resolve({})!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await drainHiveWritesForTesting(tester);
      });
    }
  }
}
