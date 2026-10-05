// test/features/math/widgets/mistake_repractice_dialog_test.dart
//
// R6（错题重练可作答）专项测试：
// 余数（17…2）、分数（5/6）、负数（-15）、小数（0.5）四种答案形态
// 均可通过 NumberKeypad 输入并判对；取消返回 null；答错返回 false。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';

/// 定位键盘上的按键（避免与答案显示区同文本冲突）。
Finder key(String text) => find.descendant(
      of: find.byType(NumberKeypad),
      matching: find.text(text),
    );

Future<void> pumpDialog(
  WidgetTester tester, {
  required String problemText,
  required String correctAnswer,
  required void Function(bool? result) onResult,
}) async {
  // 默认 800x600 逻辑视口下 AlertDialog content 高度上限约 384，
  // 容纳不下四行键盘（约 256 + 题目 + 答案框），故设置更高视口。
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (_) => MistakeRepracticeDialog(
                    problemText: problemText,
                    correctAnswer: correctAnswer,
                  ),
                );
                onResult(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
  for (final k in keys) {
    await tester.tap(key(k));
    await tester.pump();
  }
}

void main() {
  group('MistakeRepracticeDialog 四种答案形态', () {
    testWidgets('余数答案 17…2 可输入并判对', (tester) async {
      bool? result;
      await pumpDialog(
        tester,
        problemText: '87 ÷ 5 = ?',
        correctAnswer: '17…2',
        onResult: (r) => result = r,
      );

      // 余数模式：应出现省略号键，不出现分数线/小数点/负号
      expect(key('…'), findsOneWidget);
      expect(key('/'), findsNothing);
      expect(key('.'), findsNothing);
      expect(key('-'), findsNothing);

      await tapKeys(tester, ['1', '7', '…', '2']);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(find.text('回答正确！'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('分数答案 5/6 可输入并判对', (tester) async {
      bool? result;
      await pumpDialog(
        tester,
        problemText: '1/2 + 1/3 = ?',
        correctAnswer: '5/6',
        onResult: (r) => result = r,
      );

      expect(key('/'), findsOneWidget);
      expect(key('…'), findsNothing);
      expect(key('-'), findsNothing);

      await tapKeys(tester, ['5', '/', '6']);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(find.text('回答正确！'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('负数答案 -15 可输入并判对', (tester) async {
      bool? result;
      await pumpDialog(
        tester,
        problemText: '-8 - 7 = ?',
        correctAnswer: '-15',
        onResult: (r) => result = r,
      );

      expect(key('-'), findsOneWidget);
      expect(key('/'), findsNothing);
      expect(key('.'), findsNothing);

      await tapKeys(tester, ['-', '1', '5']);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(find.text('回答正确！'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('小数答案 0.5 可输入并判对', (tester) async {
      bool? result;
      await pumpDialog(
        tester,
        problemText: '1 - 0.5 = ?',
        correctAnswer: '0.5',
        onResult: (r) => result = r,
      );

      expect(key('.'), findsOneWidget);
      expect(key('/'), findsNothing);
      expect(key('…'), findsNothing);
      expect(key('-'), findsNothing);

      await tapKeys(tester, ['0', '.', '5']);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(find.text('回答正确！'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('负分数答案 -5/6 时负号与分数线同现', (tester) async {
      await pumpDialog(
        tester,
        problemText: '-1/2 - 1/3 = ?',
        correctAnswer: '-5/6',
        onResult: (_) {},
      );

      expect(key('-'), findsOneWidget);
      expect(key('/'), findsOneWidget);
      expect(key('.'), findsNothing);
    });
  });

  group('MistakeRepracticeDialog 判定与取消契约', () {
    testWidgets('答错显示正确答案并返回 false', (tester) async {
      bool? result;
      await pumpDialog(
        tester,
        problemText: '1/2 + 1/3 = ?',
        correctAnswer: '5/6',
        onResult: (r) => result = r,
      );

      await tapKeys(tester, ['5', '/', '7']);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      expect(find.text('还是答错了'), findsOneWidget);
      expect(find.text('正确答案：5/6'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('取消返回 null', (tester) async {
      bool? result = false; // 哨兵值：区分「未返回」与「返回 null」
      await pumpDialog(
        tester,
        problemText: '87 ÷ 5 = ?',
        correctAnswer: '17…2',
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('答案为空时提交键不可用', (tester) async {
      await pumpDialog(
        tester,
        problemText: '87 ÷ 5 = ?',
        correctAnswer: '17…2',
        onResult: (_) {},
      );

      // 输入后删除，回到空串
      await tapKeys(tester, ['1']);
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      // 空答案提交不产生判定
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(find.text('回答正确！'), findsNothing);
      expect(find.text('还是答错了'), findsNothing);
    });
  });
}
