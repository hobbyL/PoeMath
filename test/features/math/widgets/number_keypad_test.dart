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

    testWidgets('showNegative=true 时应该显示负号键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showNegative: true,
            ),
          ),
        ),
      );

      expect(find.text('-'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('showSlash=true 时应该显示分数线键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showSlash: true,
            ),
          ),
        ),
      );

      expect(find.text('/'), findsOneWidget);
      expect(find.text('.'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('负分数模式（showSlash + showNegative）两键同现且保留提交键', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showSlash: true,
              showNegative: true,
            ),
          ),
        ),
      );

      expect(find.text('/'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.text('.'), findsNothing);
      expect(find.text('…'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('默认（整数题）不显示负号与分数线，保持 4 键布局', (tester) async {
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

      expect(find.text('-'), findsNothing);
      expect(find.text('/'), findsNothing);
      expect(find.text('.'), findsNothing);
      expect(find.text('…'), findsNothing);
    });

    testWidgets('点击负号/分数线键应该触发 onNumberTap', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: tapped.add,
              onBackspace: () {},
              onSubmit: () {},
              showSlash: true,
              showNegative: true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('-'));
      await tester.pump();
      await tester.tap(find.text('/'));
      await tester.pump();

      expect(tapped, ['-', '/']);
    });

    testWidgets('负分数模式的按钮高度也应该 ≥56pt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberKeypad(
              onNumberTap: (_) {},
              onBackspace: () {},
              onSubmit: () {},
              showSlash: true,
              showNegative: true,
            ),
          ),
        ),
      );

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
    });
  });

  group('NumberKeypad.canAppend 特殊键合法性校验', () {
    test('负号仅允许出现在空串开头', () {
      expect(NumberKeypad.canAppend('', '-'), isTrue);
      expect(NumberKeypad.canAppend('1', '-'), isFalse);
      expect(NumberKeypad.canAppend('15', '-'), isFalse);
    });

    test('分数线至多出现一次', () {
      expect(NumberKeypad.canAppend('5', '/'), isTrue);
      expect(NumberKeypad.canAppend('5/', '/'), isFalse);
      expect(NumberKeypad.canAppend('5/6', '/'), isFalse);
    });

    test('小数点至多一次且不出现在分数线之后', () {
      expect(NumberKeypad.canAppend('0', '.'), isTrue);
      expect(NumberKeypad.canAppend('0.', '.'), isFalse);
      expect(NumberKeypad.canAppend('5/', '.'), isFalse);
      expect(NumberKeypad.canAppend('5/6', '.'), isFalse);
    });

    test('省略号至多出现一次', () {
      expect(NumberKeypad.canAppend('3', '…'), isTrue);
      expect(NumberKeypad.canAppend('3…', '…'), isFalse);
      expect(NumberKeypad.canAppend('3…2', '…'), isFalse);
    });

    test('数字键始终可追加', () {
      expect(NumberKeypad.canAppend('', '5'), isTrue);
      expect(NumberKeypad.canAppend('12', '3'), isTrue);
      expect(NumberKeypad.canAppend('3…', '2'), isTrue);
      expect(NumberKeypad.canAppend('-', '1'), isTrue);
    });
  });
}
