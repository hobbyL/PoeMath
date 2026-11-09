import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/profile/widgets/profile_badge_styles.dart';

void main() {
  late ScrollController scroll;
  setUp(() => scroll = ScrollController());
  tearDown(() => scroll.dispose());

  Future<void> pumpTag(
    WidgetTester tester,
    HeroTagStyle style, {
    AppSubject subject = AppSubject.poem,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(subject: subject, brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: AnimatedHeroHeader(
              scrollController: scroll,
              style: AnimatedHeroStyle.starlight,
              child: Center(
                child: HeroStatusTag(
                  key: const ValueKey('badge'),
                  // 固定文字与图标，确保像素差异来自装饰而非等级名称或数字。
                  label: '成长徽章',
                  icon: Icons.star_rounded,
                  style: style,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('badge')),
    );
    return (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
  }

  testWidgets('八级徽章实际配色均不同，升级不改变相同内容的布局尺寸', (tester) async {
    final rendered = <Uint8List>[];
    Size? size;
    for (var level = 0; level < 8; level++) {
      await pumpTag(tester, ProfileBadgeStyles.level(level));
      final bounds = tester.getSize(find.byKey(const ValueKey('badge')));
      size ??= bounds;
      expect(bounds, size);
      final current = await pixels(tester);
      for (final earlier in rendered) {
        expect(listEquals(current, earlier), isFalse);
      }
      rendered.add(current);
    }
    await pumpTag(tester, ProfileBadgeStyles.level(-1));
    expect(listEquals(await pixels(tester), rendered.first), isTrue);
    await pumpTag(tester, ProfileBadgeStyles.level(100));
    expect(listEquals(await pixels(tester), rendered.last), isTrue);
  });

  testWidgets('星芒仅在里程碑变更，未达门槛及满级后保持同一装饰', (tester) async {
    for (final (before, after, shouldChange) in [
      (-1, 0, false),
      (0, 49, false),
      (49, 50, true),
      (50, 299, false),
      (299, 300, true),
      (300, 799, false),
      (799, 800, true),
      (800, 1999, false),
      (1999, 2000, true),
      (2000, 999999, false),
    ]) {
      await pumpTag(tester, ProfileBadgeStyles.stars(before));
      final initial = await pixels(tester);
      await pumpTag(tester, ProfileBadgeStyles.stars(after));
      expect(
        listEquals(initial, await pixels(tester)),
        !shouldChange,
        reason: '$before → $after 星的装饰变化应与里程碑对应',
      );
    }
  });

  testWidgets('全部成长配色在两主题与明暗模式下保持文字可读', (tester) async {
    for (final subject in AppSubject.values) {
      for (final brightness in Brightness.values) {
        for (final style in [
          for (var level = 0; level < 8; level++)
            ProfileBadgeStyles.level(level),
          for (final stars in [0, 50, 300, 800, 2000])
            ProfileBadgeStyles.stars(stars),
        ]) {
          await pumpTag(
            tester,
            style,
            subject: subject,
            brightness: brightness,
          );
          final text = tester.widget<Text>(find.text('成长徽章'));
          final foreground = text.style!.color!.computeLuminance();
          final card = tester.widget<ColoredCard>(
            find.descendant(
              of: find.byKey(const ValueKey('badge')),
              matching: find.byType(ColoredCard),
            ),
          );
          for (final color in card.gradient!.colors) {
            expect(
              (foreground + .05) / (color.computeLuminance() + .05),
              greaterThanOrEqualTo(4.5),
              reason: '$subject / $brightness 的徽章背景应满足文字对比度',
            );
          }
        }
      }
    }
  });
}
