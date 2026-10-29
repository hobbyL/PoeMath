// test/features/poem/poem_handwriting_pad_test.dart
//
// 诗词默写手写板契约：
// - 有笔顺数据：写对自动回调通过（每字只回调一次）；
// - 笔数不符给「第 N 笔」教练提示，可重写；
// - 核对不过可「就这样」带错推进；
// - 无笔顺数据：降级「下一个」直通；
// - 空笔迹不可提交。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/poem/widgets/poem_handwriting_pad.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

/// 单笔参考字「一」（横向中线一笔）。
CharacterStrokeData _hengData() => const CharacterStrokeData(
      character: '一',
      strokes: ['M 256 512 L 768 512'],
      medians: [
        [
          math.Point<double>(256, 512),
          math.Point<double>(768, 512),
        ],
      ],
    );

void main() {
  Future<void> pumpPad(
    WidgetTester tester, {
    required CharacterStrokeData? strokeData,
    required ValueChanged<PoemHandwrittenChar> onConfirmed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PoemHandwritingPad(
              character: '一',
              strokeData: strokeData,
              side: 240,
              onConfirmed: onConfirmed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 在画布上写一笔横（从左到右、穿过中线，几何上应判定为正确的「一」）。
  Future<void> dragHeng(WidgetTester tester) async {
    final canvas = find
        .descendant(
          of: find.byType(WritingCanvas),
          matching: find.byType(CustomPaint),
        )
        .first;
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center + const Offset(-60, 0));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('写一笔横核对通过且只回调一次（笔迹随结果上交）', (tester) async {
    var confirmed = 0;
    PoemHandwrittenChar? result;
    await pumpPad(
      tester,
      strokeData: _hengData(),
      onConfirmed: (r) {
        confirmed++;
        result = r;
      },
    );

    await dragHeng(tester);
    expect(confirmed, 0, reason: '核对前不应回调');
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(result?.passed, isTrue);
    expect(result?.character, '一');
    expect(result?.strokes, hasLength(1), reason: '笔迹随结果上交');
  });

  testWidgets('笔数不符显示教练提示，可重写后再核对', (tester) async {
    var calls = 0;
    await pumpPad(
      tester,
      strokeData: _hengData(),
      onConfirmed: (_) => calls++,
    );

    // 写两笔：参考只有一笔 → 笔数不符提示。
    await dragHeng(tester);
    await dragHeng(tester);
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(calls, 0, reason: '笔数不符不通过');
    expect(find.textContaining('有 1 笔'), findsOneWidget);

    // 清空后写一笔正确的 → 核对通过。
    await tester.tap(find.text('重写'));
    await tester.pumpAndSettle();
    await dragHeng(tester);
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('核对不过可「就这样」带错推进（checked=false）', (tester) async {
    PoemHandwrittenChar? result;
    await pumpPad(
      tester,
      strokeData: _hengData(),
      onConfirmed: (r) => result = r,
    );

    // 两笔 → 笔数不符。
    await dragHeng(tester);
    await dragHeng(tester);
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有 1 笔'), findsOneWidget);

    await tester.tap(find.text('就这样'));
    await tester.pumpAndSettle();
    expect(result?.passed, isFalse);
    expect(result?.checked, isFalse);
  });

  testWidgets('无笔顺数据：写一笔后「下一个」直通（checked=false）', (tester) async {
    PoemHandwrittenChar? result;
    await pumpPad(
      tester,
      strokeData: null,
      onConfirmed: (r) => result = r,
    );

    expect(find.text('下一个'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '下一个'),
          )
          .onPressed,
      isNull,
      reason: '空笔迹不可提交',
    );

    await dragHeng(tester);
    await tester.tap(find.text('下一个'));
    await tester.pumpAndSettle();
    expect(result?.passed, isTrue);
    expect(result?.checked, isFalse);
  });
}
