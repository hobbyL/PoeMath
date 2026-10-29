// test/features/poem/poem_sentence_writing_sheet_test.dart
//
// 诗句手写默写板契约：
// - 整句渲染为一排格位（含标点灰显占位）；
// - 确认一字后对应格位显示笔迹、书写板换新目标字；
// - 全部写完显示「本句完成」且不再出手写板。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/poem/widgets/poem_handwriting_pad.dart';
import 'package:poemath/features/poem/widgets/poem_sentence_writing_sheet.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

void main() {
  const confirmed0 = PoemHandwrittenChar(
    character: '床',
    strokes: [
      [Offset(10, 10), Offset(30, 30)],
    ],
    passed: true,
    checked: false,
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<PoemHandwrittenChar> confirmed,
    required ValueChanged<PoemHandwrittenChar> onCharConfirmed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: PoemSentenceWritingSheet(
                targetChars: const ['床', '前'],
                confirmedChars: confirmed,
                currentStrokeData: null,
                onCharConfirmed: onCharConfirmed,
                maxBoardSide: 200,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('整句格位行：未写格空显、标点位灰显', (tester) async {
    // 「床，」含标点：标点在格位行自动落位（无需手写）。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: PoemSentenceWritingSheet(
                targetChars: const ['床', '，', '前'],
                confirmedChars: const [],
                currentStrokeData: null,
                onCharConfirmed: (_) {},
                maxBoardSide: 200,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 标点「，」直接显示在格位行；书写板目标是「床」（首格）。
    expect(find.text('，'), findsOneWidget);
    expect(find.byType(PoemHandwritingPad), findsOneWidget);
    expect(find.text('下一个'), findsOneWidget, reason: '无笔顺数据走降级直通');
  });

  testWidgets('确认一字后书写板换新目标字，格位显示笔迹', (tester) async {
    await pumpSheet(
      tester,
      confirmed: const [],
      onCharConfirmed: (_) {},
    );
    // 首目标「床」的板上有「下一个」。
    expect(find.text('下一个'), findsOneWidget);

    // 传入已确认「床」的笔迹：板换成「前」。
    await pumpSheet(
      tester,
      confirmed: [confirmed0],
      onCharConfirmed: (_) {},
    );
    expect(find.text('下一个'), findsOneWidget);
    // 已写格位有一个不可交互的 WritingCanvas 预览 + 书写板本体。
    final canvases = find.byType(WritingCanvas);
    expect(canvases.evaluate().length, 2);
  });

  testWidgets('全部写完显示「本句完成」', (tester) async {
    final done = [
      confirmed0,
      const PoemHandwrittenChar(
        character: '前',
        strokes: [
          [Offset(5, 5), Offset(20, 20)],
        ],
        passed: true,
        checked: false,
      ),
    ];
    await pumpSheet(tester, confirmed: done, onCharConfirmed: (_) {});

    expect(find.text('本句完成'), findsOneWidget);
    expect(find.byType(PoemHandwritingPad), findsNothing);
  });
}
