import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/features/poem/widgets/poem_stroke_numbers.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

void main() {
  Future<void> pumpNumbers(
    WidgetTester tester, {
    required List<List<Offset>> strokes,
    required Map<int, int> numbers,
    double textScale = 1,
    ValueChanged<List<List<Offset>>>? onStrokesChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PoemTheme.light(),
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SizedBox.square(
                key: const ValueKey('numbered-board'),
                dimension: 240,
                child: Stack(
                  children: [
                    WritingCanvas(
                      strokes: strokes,
                      onStrokesChanged: onStrokesChanged,
                    ),
                    Positioned.fill(
                      child: PoemStrokeNumbers(
                        strokes: strokes,
                        numbers: numbers,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final textScale in [1.0, 2.0]) {
    testWidgets('密集笔画的双位数编号可辨且不出田字格，字号 $textScale', (tester) async {
      await pumpNumbers(
        tester,
        textScale: textScale,
        strokes: const [
          [Offset(4, 4), Offset(4, 12)],
          [Offset(6, 4), Offset(6, 12)],
          [Offset(8, 4), Offset(8, 12)],
          [Offset(236, 236), Offset(242, 242)],
        ],
        numbers: const {0: 1, 1: 10, 2: 11, 3: 12},
      );
      final board = tester.getRect(
        find.byKey(const ValueKey('numbered-board')),
      );
      final markers = <Rect>[];
      for (final number in [1, 10, 11, 12]) {
        final marker = find.byKey(ValueKey('poem-stroke-number-$number'));
        final rect = tester.getRect(marker);
        expect(rect.left, greaterThanOrEqualTo(board.left));
        expect(rect.top, greaterThanOrEqualTo(board.top));
        expect(rect.right, lessThanOrEqualTo(board.right));
        expect(rect.bottom, lessThanOrEqualTo(board.bottom));
        final text = tester.getRect(
          find.descendant(of: marker, matching: find.text('$number')),
        );
        expect(text.width, lessThanOrEqualTo(rect.width));
        expect(text.height, lessThanOrEqualTo(rect.height));
        for (final other in markers) {
          expect(
            rect.overlaps(other),
            isFalse,
            reason: '第 $number 笔序号不能遮住其他序号',
          );
        }
        markers.add(rect);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('在编号上落笔仍交给画布，不阻挡继续书写', (tester) async {
    List<List<Offset>>? written;
    await pumpNumbers(
      tester,
      strokes: const [
        [Offset(60, 120), Offset(180, 120)],
      ],
      numbers: const {0: 1},
      onStrokesChanged: (value) => written = value,
    );
    final marker = find.byKey(const ValueKey('poem-stroke-number-1'));
    final gesture = await tester.startGesture(tester.getCenter(marker));
    await gesture.moveBy(const Offset(20, 20));
    await gesture.up();
    await tester.pump();

    expect(written, hasLength(2));
    final boardTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('numbered-board')),
    );
    expect(written!.last.first, tester.getCenter(marker) - boardTopLeft);
    expect(written!.last.last - written!.last.first, const Offset(20, 20));
  });
}
