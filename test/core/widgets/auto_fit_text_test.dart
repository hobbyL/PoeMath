// test/core/widgets/auto_fit_text_test.dart
//
// AutoFitText 组件契约（三段语义 + 防御）：
// 放得下原字号单行 / 放不下先等比缩小（字号 ≥ minFontSize 仍单行）/
// 缩到 minFontSize 仍放不下则按下限字号换行 / 下限不低于原字号退化换行 /
// 环境样式并入方向（显式样式胜出，钉死详情页朗读高亮）。
// 测试字体为 Ahem（每字形宽度 == fontSize），宽度可精确推算。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/auto_fit_text.dart';

Widget _harness({required double maxWidth, required Widget child}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('放得下：原字号单行渲染，不缩不放', (tester) async {
    await tester.pumpWidget(
      _harness(
        maxWidth: 300,
        child: const AutoFitText(
          text: 'abc',
          style: TextStyle(fontSize: 40, height: 1.0),
          minFontSize: 16,
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final textBox = tester.renderObject<RenderBox>(find.byType(Text));

    // 字号保持 40，单行（高度 == 40），固有宽度 3 × 40 = 120 未被拉伸。
    expect(text.style!.fontSize, 40);
    expect(text.maxLines, 1);
    expect(textBox.size.width, closeTo(120, 0.5));
    expect(textBox.size.height, closeTo(40, 0.5));
  });

  testWidgets('中等超宽：等比缩小后字号仍大于下限且保持单行', (tester) async {
    // 固有宽度 = 30 × (40 + 4) = 1320，maxWidth 660 → 缩放比例 0.5。
    await tester.pumpWidget(
      _harness(
        maxWidth: 660,
        child: const AutoFitText(
          text: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
          style: TextStyle(fontSize: 40, height: 1.0, letterSpacing: 4),
          minFontSize: 16,
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final textBox = tester.renderObject<RenderBox>(find.byType(Text));

    // 字号与 letterSpacing 同比例缩小（40→20，4→2），仍单行不换行。
    expect(text.style!.fontSize, closeTo(20, 0.2));
    expect(text.style!.letterSpacing, closeTo(2.0, 0.1));
    expect(text.style!.fontSize, greaterThan(16));
    expect(text.maxLines, 1);
    // 单行：高度 == 缩放后字号；宽度占满可用宽度且不越界。
    expect(textBox.size.height, closeTo(20, 0.5));
    expect(textBox.size.width, lessThanOrEqualTo(660));
    expect(textBox.size.width, greaterThan(640));
  });

  testWidgets('极长句：缩到下限仍放不下，按下限字号换行展示', (tester) async {
    // 固有宽度 = 30 × 40 = 1200，maxWidth 300 → 缩放后字号 10 < 16。
    await tester.pumpWidget(
      _harness(
        maxWidth: 300,
        child: const AutoFitText(
          text: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
          style: TextStyle(fontSize: 40, height: 1.0),
          minFontSize: 16,
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final textBox = tester.renderObject<RenderBox>(find.byType(Text));

    // 字号 == minFontSize == 16（单字宽 16，30 字 → 480 > 300 必然换行）。
    expect(text.style!.fontSize, 16);
    expect(text.maxLines, isNull);
    // 两行：高度 == 2 × 16，宽度占满可用宽度。
    expect(textBox.size.height, closeTo(32, 0.5));
    expect(textBox.size.width, closeTo(300, 0.5));
  });

  testWidgets('防御：下限不低于原字号时退化为原字号换行', (tester) async {
    await tester.pumpWidget(
      _harness(
        maxWidth: 300,
        child: const AutoFitText(
          text: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
          style: TextStyle(fontSize: 20, height: 1.0),
          minFontSize: 30,
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final textBox = tester.renderObject<RenderBox>(find.byType(Text));

    // 原字号 20 不缩放（600 > 300 换行为两行），不抛错。
    expect(text.style!.fontSize, 20);
    expect(text.maxLines, isNull);
    expect(textBox.size.height, closeTo(40, 0.5));
  });

  testWidgets('边界：缩放后字号恰等于下限时仍走缩放段保持单行', (tester) async {
    // 固有宽度 = 8 × 40 = 320，maxWidth 160 → 缩放比例 0.5，字号 40 → 20 == minFontSize。
    await tester.pumpWidget(
      _harness(
        maxWidth: 160,
        child: const AutoFitText(
          text: 'xxxxxxxx',
          style: TextStyle(fontSize: 40, height: 1.0),
          minFontSize: 20,
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final textBox = tester.renderObject<RenderBox>(find.byType(Text));

    // 恰好缩到下限属于「放得下」（缩放段）：单行，不落入换行段。
    expect(text.style!.fontSize, 20);
    expect(text.maxLines, 1);
    expect(textBox.size.height, closeTo(20, 0.5));
    expect(textBox.size.width, lessThanOrEqualTo(160));
  });

  testWidgets('环境样式并入：显式样式不被 DefaultTextStyle 覆盖', (tester) async {
    // 与 Text 的合成规则同源：DefaultTextStyle.merge(style)，显式 style 胜出。
    // 详情页朗读高亮（primary 色 + w600）依赖该方向，反向 merge 会丢高亮。
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTextStyle(
          style: const TextStyle(
            fontSize: 13,
            color: Colors.brown,
            fontWeight: FontWeight.w300,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: const AutoFitText(
                text: 'abc',
                style: TextStyle(
                  fontSize: 40,
                  height: 1.0,
                  color: Colors.pink,
                  fontWeight: FontWeight.w600,
                ),
                minFontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final textBox = tester.renderObject<RenderBox>(find.byType(Text));

    // 显式色/字重/字号全部保留；测宽用合并后的样式（3 × 40 = 120 放得下）。
    expect(text.style!.color, Colors.pink);
    expect(text.style!.fontWeight, FontWeight.w600);
    expect(text.style!.fontSize, 40);
    expect(textBox.size.width, closeTo(120, 0.5));
  });
}
