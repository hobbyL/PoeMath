// test/features/math/widgets/number_keypad_test.dart
//
// NumberKeypad 组件单元测试

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';

void main() {
  group('NumberKeypad', () {
    testWidgets('应该显示 0-9 数字键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
            ),
          ),
        ),
      );

      // 验证 0-9 都存在
      for (var i = 0; i <= 9; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
    });

    testWidgets('应该显示退格和提交按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
            ),
          ),
        ),
      );

      // 退格图标
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
      // 提交图标（默认模式）
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('点击数字键应该触发回调', (tester) async {
      String? tappedNumber;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (n) => tappedNumber = n,
              onBackspace: () {},
              onSubmit: () {},
            ),
          ),
        ),
      );

      // 点击数字 5
      await tester.tap(find.text('5'));
      await tester.pump();

      expect(tappedNumber, '5');
    });

    testWidgets('点击退格应该触发回调', (tester) async {
      var backspacePressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () => backspacePressed = true,
              onSubmit: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(backspacePressed, true);
    });

    testWidgets('点击提交应该触发回调', (tester) async {
      var submitPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () => submitPressed = true,
              submitEnabled: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(submitPressed, true);
    });

    testWidgets('submitEnabled=false 时点击提交不应触发回调', (tester) async {
      var submitPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () => submitPressed = true,
              submitEnabled: false,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(submitPressed, false);
    });

    testWidgets('showDecimal=true 时应该显示小数点', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showDecimal: true,
            ),
          ),
        ),
      );

      expect(find.text('.'), findsOneWidget);
    });

    testWidgets('showDecimal=false 时不应该显示小数点', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showDecimal: false,
            ),
          ),
        ),
      );

      expect(find.text('.'), findsNothing);
    });

    testWidgets('普通、小数和余数模式的按钮高度都应该 ≥56pt', (tester) async {
      for (final mode in const [
        (showDecimal: false, showEllipsis: false),
        (showDecimal: true, showEllipsis: false),
        (showDecimal: false, showEllipsis: true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NumberKeypad(
                onNumberTap: (_) {},
                onBackspace: () {},
                onSubmit: () {},
                showDecimal: mode.showDecimal,
                showEllipsis: mode.showEllipsis,
              ),
            ),
          ),
        );

        // 查找所有 InkWell 的 Container（按钮容器）
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(InkWell),
            matching: find.byType(Container),
          ),
        );

        for (final container in containers) {
          final height = container.constraints?.minHeight ?? 0;
          expect(
            height,
            greaterThanOrEqualTo(56),
            reason: '键盘按钮高度应 ≥56pt',
          );
        }
      }
    });

    testWidgets('showEllipsis=true 时应该同时显示省略号和提交键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showEllipsis: true,
            ),
          ),
        ),
      );

      expect(find.text('…'), findsOneWidget);
      expect(find.text('.'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('showEllipsis=false 时不应该显示省略号键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showEllipsis: false,
            ),
          ),
        ),
      );

      expect(find.text('…'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('小数与余数标记同时开启时省略号优先且保留提交键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showDecimal: true,
              showEllipsis: true,
            ),
          ),
        ),
      );

      expect(find.text('…'), findsOneWidget);
      expect(find.text('.'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('点击省略号键应该触发 onNumberTap', (tester) async {
      String? tappedDigit;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (digit) => tappedDigit = digit,
              onBackspace: () {},
              onSubmit: () {},
              showEllipsis: true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('…'));
      await tester.pump();

      expect(tappedDigit, '…');
    });

    testWidgets('特殊输入模式下点击提交仍然触发 onSubmit', (tester) async {
      var submitPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () => submitPressed = true,
              showDecimal: true,
              submitEnabled: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(submitPressed, isTrue);
    });
  });
}
