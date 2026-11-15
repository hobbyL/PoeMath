import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/character_puzzle.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_jigsaw.dart';

Future<WritingStrokeAsset> loadJigsawTestAsset() async => WritingStrokeAsset(
  await loadWritingStrokeData(loader: (path) => File(path).readAsBytes()),
);

WritingJigsawBoardPainter jigsawPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const ValueKey('jigsaw-board')))
            .painter!
        as WritingJigsawBoardPainter;

void expectLandscapeJigsawControls(WidgetTester tester) {
  final progress = tester.getRect(
    find.byKey(const ValueKey('jigsaw-progress')),
  );
  final restart = tester.getRect(find.byKey(const ValueKey('jigsaw-restart')));
  final hint = tester.getRect(find.byKey(const ValueKey('jigsaw-hint-toggle')));
  final board = tester.getRect(find.byKey(const ValueKey('jigsaw-board')));
  expect(progress.right, lessThan(restart.left));
  expect(restart.right, lessThan(hint.left));
  expect(progress.center.dy, closeTo(restart.center.dy, 0.01));
  expect(hint.center.dy, closeTo(restart.center.dy, 0.01));
  expect(progress.top, greaterThan(board.bottom));
}

Future<void> dragJigsawPiece(
  WidgetTester tester,
  int id, {
  bool correct = true,
  Offset grip = const Offset(0.5, 0.5),
}) async {
  final pieceFinder = find.byKey(ValueKey('jigsaw-piece-$id'));
  final boardFinder = find.byKey(const ValueKey('jigsaw-board'));
  final boardBefore = tester.getRect(boardFinder);
  await tester.ensureVisible(pieceFinder);
  await tester.pumpAndSettle();
  // 滚动碎片区不能把目标字一起移走。
  expect(tester.getRect(boardFinder), boardBefore);
  final piece = tester
      .widget<Draggable<CharacterPuzzlePiece>>(pieceFinder)
      .data!;
  final rect = tester.getRect(pieceFinder);
  final start =
      rect.topLeft + Offset(rect.width * grip.dx, rect.height * grip.dy);
  expect(
    tester
        .hitTestOnBinding(start)
        .path
        .any(
          (entry) => identical(entry.target, tester.renderObject(pieceFinder)),
        ),
    isTrue,
    reason:
        '碎片按下位置应可见并可命中：piece=$rect, start=$start, board=$boardBefore, '
        'tray=${tester.getRect(find.byKey(const ValueKey("jigsaw-tray")))}, '
        'scroll=${tester.stateList<ScrollableState>(find.byType(Scrollable)).map((s) => (s.position.pixels, s.position.maxScrollExtent, s.position.viewportDimension)).toList()}',
  );
  final board = tester.getRect(boardFinder);
  final target =
      board.topLeft +
      Offset(
        (piece.bounds.left + piece.bounds.width / 2) * board.width,
        (piece.bounds.top + piece.bounds.height / 2) * board.height,
      );
  var destination = target;
  if (!correct) {
    final corners = [
      for (final x in [0.06, 0.94])
        for (final y in [0.06, 0.94])
          board.topLeft + Offset(board.width * x, board.height * y),
    ]..sort((a, b) => (b - target).distance.compareTo((a - target).distance));
    destination = corners.first;
  }
  final gesture = await tester.startGesture(start);
  await gesture.moveTo(
    Offset((start.dx + destination.dx) / 2, (start.dy + destination.dy) / 2),
  );
  await tester.pump();
  await gesture.moveTo(destination);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
