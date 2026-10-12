// test/core/widgets/colored_card_test.dart
//
// ColoredCard 渐变扩展测试（任务 10-12-feature-batch-8 ⑦）：
// - 纯色路径回归：背景 = color × backgroundOpacity、radiusMedium、无阴影；
// - 渐变路径：gradient 优先，忽略 color 着色；
// - 阴影参数：boxShadow 透传到 Decoration；
// - color 与 gradient 至少其一（断言报错）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/design_tokens.dart';
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

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  testWidgets('纯色路径回归：color × backgroundOpacity + radiusMedium 无阴影', (tester) async {
    await tester.pumpWidget(wrap(
      const ColoredCard(color: kRed, child: Text('卡片')),
    ),);

    final decoration = decorationOf(tester);
    expect(decoration.color, kRed.withValues(alpha: 0.08));
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, isNull);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(SpacingTokens.radiusMedium),
    );
  });

  testWidgets('渐变路径：gradient 优先于 color 着色', (tester) async {
    const gradient = LinearGradient(
      colors: [kBlue, kRed],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    await tester.pumpWidget(wrap(
      const ColoredCard(gradient: gradient, child: Text('渐变卡')),
    ),);

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
    await tester.pumpWidget(wrap(
      const ColoredCard(
        gradient: LinearGradient(colors: [kBlue, kRed]),
        boxShadow: SpacingTokens.softShadow,
        child: Text('带阴影渐变卡'),
      ),
    ),);

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
