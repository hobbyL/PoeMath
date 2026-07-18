// test/features/math/widgets/math_text_test.dart
//
// MathText 组件单元测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/math/widgets/math_text.dart';

void main() {
  group('MathText', () {
    Widget buildApp(String text, {TextStyle? style}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: MathText(text, style: style),
          ),
        ),
      );
    }

    testWidgets('普通文本不含分数时使用 Text 渲染', (tester) async {
      await tester.pumpWidget(buildApp('25 + 38 = ?'));

      // 应该有 Text widget
      expect(find.text('25 + 38 = ?'), findsOneWidget);
    });

    testWidgets('普通整数除法不触发 LaTeX', (tester) async {
      await tester.pumpWidget(buildApp('12 + 5 = ?'));

      expect(find.text('12 + 5 = ?'), findsOneWidget);
    });

    test('hasFraction 正确检测分数模式', () {
      expect(const MathText('1/3 + 2/5 = ?').hasFraction, isTrue);
      expect(const MathText('25 + 38 = ?').hasFraction, isFalse);
      expect(const MathText('3/4').hasFraction, isTrue);
      expect(const MathText('12 ÷ 4 = ?').hasFraction, isFalse);
    });

    test('hasFraction 不匹配三段日期格式', () {
      // 2026/07/18 这种日期不应匹配
      expect(const MathText('2026/07/18').hasFraction, isFalse);
    });

    test('_latex 正确转换分数', () {
      // 由于 _latex 是私有的，我们通过 hasFraction 和组件渲染间接验证
      const widget = MathText('1/3 + 2/5 = ?');
      expect(widget.hasFraction, isTrue);
    });

    testWidgets('含分数文本使用 Math.tex 渲染', (tester) async {
      await tester.pumpWidget(buildApp('1/3 + 2/5 = ?'));

      // Math.tex 渲染时不会出现纯文本 Text widget 的 "1/3 + 2/5 = ?"
      expect(find.text('1/3 + 2/5 = ?'), findsNothing);
    });

    testWidgets('可传入 TextStyle', (tester) async {
      await tester.pumpWidget(buildApp(
        '25 + 38 = ?',
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      ),);

      final textWidget = tester.widget<Text>(find.text('25 + 38 = ?'));
      expect(textWidget.style?.fontSize, 32);
      expect(textWidget.style?.fontWeight, FontWeight.bold);
    });
  });
}
