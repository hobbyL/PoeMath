// test/core/widgets/colored_card_test.dart
//
// ColoredCard 渐变扩展测试（任务 10-12-feature-batch-8 ⑦）：
// - 默认纸面不透出祖先背景，实色/透明区域不附加装饰；
// - 渐变路径：gradient 优先，忽略 color 着色；
// - 阴影参数：boxShadow 透传到 Decoration；
// - color 与 gradient 至少其一（断言报错）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

void main() {
  const kRed = Color(0xFFF44336);
  const kBlue = Color(0xFF2196F3);

  BoxDecoration decorationOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(ColoredCard),
        matching: find.byType(Container),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('同一张卡片切换主题后改变材质与轮廓并保留点击反馈', (tester) async {
    var taps = 0;
    final card = ColoredCard(
      color: kBlue,
      onTap: () => taps++,
      child: const Text('开始练习'),
    );
    for (final preset in [
      AppSubject.poem,
      AppSubject.candy,
      AppSubject.space,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            subject: preset,
            brightness: Brightness.light,
          ),
          home: Scaffold(body: card),
        ),
      );
      await tester.pumpAndSettle();
      if (preset == AppSubject.space) {
        final surface = tester.widget<Container>(
          find.descendant(
            of: find.byType(ColoredCard),
            matching: find.byType(Container),
          ),
        );
        final decoration = surface.decoration! as ShapeDecoration;
        expect(decoration.color!.a, 1);
        expect(decoration.shape, isA<BeveledRectangleBorder>());
        expect(decoration.shadows, isNull);
        final shape = decoration.shape as BeveledRectangleBorder;
        final path = shape.getOuterPath(const Rect.fromLTWH(0, 0, 100, 80));
        expect(path.contains(const Offset(1, 1)), isFalse);
        expect(path.contains(const Offset(50, 40)), isTrue);
        await tester.tap(find.text('开始练习'));
        await tester.pumpAndSettle();
        continue;
      }
      final decoration = decorationOf(tester);
      expect(decoration.color!.a, 1);
      if (preset == AppSubject.poem) {
        expect(decoration.borderRadius, BorderRadius.circular(8));
      } else if (preset == AppSubject.candy) {
        expect(decoration.borderRadius, BorderRadius.circular(16));
      } else {
        expect(decoration.borderRadius, BorderRadius.circular(4));
      }
      if (preset == AppSubject.candy) {
        expect(decoration.border, isNull);
        expect(decoration.boxShadow, isNotEmpty);
      }
      if (preset == AppSubject.space) {
        expect(decoration.border, isNotNull);
        expect(decoration.boxShadow, isNull);
      }
      await tester.tap(find.text('开始练习'));
      await tester.pumpAndSettle();
    }
    expect(taps, 3);
  });

  testWidgets('默认纸面是独立的不透明表面，带细边线且无厚重底边', (tester) async {
    await tester.pumpWidget(
      wrap(const ColoredCard(color: kRed, child: Text('卡片'))),
    );

    final decoration = decorationOf(tester);
    expect(decoration.color!.a, 1);
    expect(decoration.gradient, isNull);
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNull);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(SpacingTokens.radiusMedium),
    );
  });

  testWidgets('纸卡细描边不改变零内边距内容与贴边操作的位置', (tester) async {
    const contentKey = ValueKey('edge-content');
    await tester.pumpWidget(
      wrap(
        const ColoredCard(
          color: kRed,
          padding: EdgeInsets.zero,
          child: SizedBox(key: contentKey, width: 200, height: 80),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      tester.getRect(find.byType(ColoredCard)),
    );
  });

  testWidgets('准备遮罩保留半透明，遮罩内的进度可以独立显示', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ColoredCard(
          color: kRed,
          backgroundOpacity: .6,
          paperSurface: false,
          child: CircularProgressIndicator(),
        ),
      ),
    );
    final decoration = decorationOf(tester);
    expect(decoration.color, kRed.withValues(alpha: .6));
    expect(decoration.border, isNull);
    expect(decoration.boxShadow, isNull);
  });

  for (final opacity in [0.0, 1.0]) {
    testWidgets('透明度 $opacity 保留全幅背景和无背景容器的语义', (tester) async {
      await tester.pumpWidget(
        wrap(
          ColoredCard(
            color: kRed,
            backgroundOpacity: opacity,
            child: const Text('背景'),
          ),
        ),
      );
      final decoration = decorationOf(tester);
      expect(decoration.color, kRed.withValues(alpha: opacity));
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, isNull);
    });
  }

  testWidgets('渐变路径：gradient 优先于 color 着色', (tester) async {
    const gradient = LinearGradient(
      colors: [kBlue, kRed],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    await tester.pumpWidget(
      wrap(const ColoredCard(gradient: gradient, child: Text('渐变卡'))),
    );

    final decoration = decorationOf(tester);
    expect(decoration.gradient, same(gradient));
    expect(decoration.color, isNull);
    expect(decoration.boxShadow, isNull);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(SpacingTokens.radiusMedium),
    );
  });

  testWidgets('boxShadow 透传（渐变 + softShadow 组合）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ColoredCard(
          gradient: LinearGradient(colors: [kBlue, kRed]),
          boxShadow: SpacingTokens.softShadow,
          child: Text('带阴影渐变卡'),
        ),
      ),
    );

    final decoration = decorationOf(tester);
    expect(decoration.boxShadow, same(SpacingTokens.softShadow));
    expect(decoration.gradient, isNotNull);
  });

  testWidgets('color 与 gradient 至少其一，否则断言报错', (tester) async {
    expect(
      () => ColoredCard(child: const Text('x')),
      throwsA(isA<AssertionError>()),
    );
  });
}
