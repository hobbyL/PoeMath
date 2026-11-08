import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

// 读取真实绘制的背景（含光晕和光带），避免只检查渐变端点而漏掉叠色。
Future<void> _expectRenderedHeaderContrast(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('home-check-in-background')),
  );
  final pixels = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  }))!;
  var darkest = double.infinity;
  var lightest = 0.0;
  for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
    final color = Color.fromARGB(
      pixels.getUint8(offset + 3),
      pixels.getUint8(offset),
      pixels.getUint8(offset + 1),
      pixels.getUint8(offset + 2),
    );
    expect(color.a, 1, reason: '贴边背景不能透出页面底色');
    final luminance = color.computeLuminance();
    darkest = math.min(darkest, luminance);
    lightest = math.max(lightest, luminance);
  }
  for (final label in ['今日待打卡', '天连续']) {
    final text = tester.widget<Text>(find.text(label));
    final foreground = text.style!.color!.computeLuminance();
    // 前景必须完全高于或低于所有背景亮度，再检查最接近的像素。
    final contrast = foreground > lightest
        ? (foreground + .05) / (lightest + .05)
        : foreground < darkest
        ? (darkest + .05) / (foreground + .05)
        : 1.0;
    expect(contrast, greaterThanOrEqualTo(4.5), reason: '$label/实际光效');
  }
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
          '导航选中文字': (
            theme.navigationBarTheme.labelTextStyle!.resolve({
              WidgetState.selected,
            })!.color!,
            scheme.surfaceContainer,
          ),
          '导航未选中文字': (
            theme.navigationBarTheme.labelTextStyle!.resolve({})!.color!,
            scheme.surfaceContainer,
          ),
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
        await drainHiveWritesForTesting(tester);
        await tester.pump(const Duration(milliseconds: 400));
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
        // 覆盖整个光效周期，避免移动到文字下方时叠色降低可读性。
        for (var frame = 0; frame < 12; frame++) {
          await _expectRenderedHeaderContrast(tester);
          await tester.pump(const Duration(milliseconds: 500));
        }
        final gesture = await tester.startGesture(
          tester.getCenter(
            find.byKey(const ValueKey('home-check-in-background')),
          ),
        );
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 160));
        await tester.pump();
        await _expectRenderedHeaderContrast(tester);
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await drainHiveWritesForTesting(tester);
      });
    }
  }
}
