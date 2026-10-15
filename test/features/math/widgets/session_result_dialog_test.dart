// test/features/math/widgets/session_result_dialog_test.dart
//
// 结算弹窗返回值契约（审计问题 1 / 3）：
// 旧实现只有「查看错题」「再练一组」两个出口且 `barrierDismissible: false`，
// 用户无法关闭弹窗。现补充右上角关闭图标与点击空白两条出口，均返回 null。
//
// 本测试锁定四条返回路径：
//   - 右上角关闭图标 → null
//   - 点击空白（外部）→ null
//   - 「查看错题」   → 'review'（仅在非全对时出现）
//   - 「再练一组」   → 'retry'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/math/widgets/session_result_dialog.dart';

/// 打开弹窗并记录其返回值；`null` 表示尚未返回。
Future<void> _pumpDialog(
  WidgetTester tester, {
  required int totalProblems,
  required int correctCount,
  required void Function(String? result) onResult,
}) async {
  // 默认 800x600 视口下 AlertDialog content 高度上限约 384，
  // 星星行 + 三行统计 + 按钮行会溢出，故设置更高视口。
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
                final result = await showDialog<String>(
                  context: context,
                  barrierDismissible: true,
                  builder: (_) => SessionResultDialog(
                    totalProblems: totalProblems,
                    correctCount: correctCount,
                    durationSeconds: 75,
                    starsEarned: 2,
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

void main() {
  group('SessionResultDialog 返回值契约', () {
    testWidgets('右上角关闭图标返回 null', (tester) async {
      String? result;
      await _pumpDialog(
        tester,
        totalProblems: 5,
        correctCount: 5,
        onResult: (r) => result = r,
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(SessionResultDialog), findsNothing);
      expect(result, isNull);
    });

    testWidgets('点击弹窗外部返回 null', (tester) async {
      String? result;
      await _pumpDialog(
        tester,
        totalProblems: 5,
        correctCount: 5,
        onResult: (r) => result = r,
      );

      // 点击左上角（弹窗外的 barrier 区域）。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(SessionResultDialog), findsNothing);
      expect(result, isNull);
    });

    testWidgets('「再练一组」返回 retry', (tester) async {
      String? result;
      await _pumpDialog(
        tester,
        totalProblems: 5,
        correctCount: 5,
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('再练一组'));
      await tester.pumpAndSettle();

      expect(result, 'retry');
    });

    testWidgets('非全对时「查看错题」返回 review', (tester) async {
      String? result;
      await _pumpDialog(
        tester,
        totalProblems: 5,
        correctCount: 3,
        onResult: (r) => result = r,
      );

      expect(find.text('查看错题'), findsOneWidget);
      await tester.tap(find.text('查看错题'));
      await tester.pumpAndSettle();

      expect(result, 'review');
    });

    testWidgets('全对时不显示「查看错题」，且关闭图标仍可退出', (tester) async {
      String? result;
      await _pumpDialog(
        tester,
        totalProblems: 4,
        correctCount: 4,
        onResult: (r) => result = r,
      );

      expect(find.text('查看错题'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    test('正确率按 correctCount / totalProblems 计算，除数为 0 时不崩', () {
      const normal = SessionResultDialog(
        totalProblems: 4,
        correctCount: 3,
        durationSeconds: 10,
        starsEarned: 1,
      );
      expect(normal.accuracy, 0.75);

      const empty = SessionResultDialog(
        totalProblems: 0,
        correctCount: 0,
        durationSeconds: 0,
        starsEarned: 0,
      );
      expect(empty.accuracy, 0.0);
    });
  });
}
