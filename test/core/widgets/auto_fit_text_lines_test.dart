// test/core/widgets/auto_fit_text_lines_test.dart
//
// 职责：验证 AutoFitTextLines 的统一字号缩放语义。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/auto_fit_text_lines.dart';

TextStyle _style(double fontSize) => TextStyle(
      fontSize: fontSize,
      letterSpacing: 1.5,
      color: const Color(0xFF000000),
      inherit: false,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<String> lines,
  required double maxWidth,
  TextStyle Function(int)? styleFor,
  double minFontSize = 14,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: maxWidth,
            child: AutoFitTextLines(
              lines: lines,
              minFontSize: minFontSize,
              styleFor: (i) => styleFor?.call(i) ?? _style(20),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<double?> _fontSizes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.style?.fontSize)
    .toList();

void main() {
  testWidgets('短行全部放得下时使用原字号', (tester) async {
    await _pump(tester, lines: ['床前明月光', '疑是地上霜'], maxWidth: 400);
    expect(_fontSizes(tester), everyElement(20));
  });

  testWidgets('长短行混合时按最长行统一缩放，各行字号一致', (tester) async {
    await _pump(
      tester,
      lines: ['春眠不觉晓', '处处闻啼鸟，夜来风雨声，花落知多少。'],
      maxWidth: 200,
    );
    final sizes = _fontSizes(tester);
    expect(sizes.first, isNot(20), reason: '最长行超宽时应统一缩小');
    expect(sizes.every((s) => s == sizes.first), isTrue,
        reason: '全部行字号必须一致');
  });

  testWidgets('缩到字号下限后统一用下限字号，放不下的行允许换行', (tester) async {
    await _pump(
      tester,
      lines: ['短短', '这一行特别长特别长特别长特别长特别长特别长特别长特别长'],
      maxWidth: 100,
      minFontSize: 18,
    );
    expect(_fontSizes(tester), everyElement(18));
    // 下限字号下长行必然折行：检查该行 Text 是否超出单行高度。
    final renderers = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .toList();
    final longLineHeight = renderers.last.size.height;
    final shortLineHeight = renderers.first.size.height;
    expect(longLineHeight, greaterThan(shortLineHeight), reason: '长行应换行');
  });

  testWidgets('行样式差异（如朗读高亮）不影响统一字号决策', (tester) async {
    await _pump(
      tester,
      lines: ['短行', '较长的一行内容'],
      maxWidth: 90,
      styleFor: (i) => i == 0
          ? _style(20).copyWith(fontWeight: FontWeight.w600)
          : _style(20),
    );
    final sizes = _fontSizes(tester);
    expect(sizes.every((s) => s == sizes.first), isTrue);
  });
}
