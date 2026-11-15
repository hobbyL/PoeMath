import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/character_puzzle.dart';

void main() {
  final squareInk = [
    for (var y = 2; y < 18; y++)
      for (var x = 2; x < 18; x++) Point(x / 20, y / 20),
  ];
  final horizontalInk = [for (var x = 1; x < 40; x++) Point(x / 40, 0.5)];
  final verticalInk = [for (var y = 1; y < 40; y++) Point(0.5, y / 40)];

  test('同种子得到同一分片和打乱顺序，面积并非等分', () {
    final first = createCharacterPuzzle(inkPoints: squareInk, seed: 719);
    final second = createCharacterPuzzle(inkPoints: squareInk, seed: 719);
    expect(first.trayOrder, second.trayOrder);
    expect(first.trayOrder.toSet(), {0, 1, 2, 3, 4, 5});
    expect(
      first.pieces.map((p) => p.outline),
      second.pieces.map((p) => p.outline),
    );
    final areas = first.pieces.map((p) => p.area).toList()..sort();
    expect(areas.last / areas.first, greaterThan(1.3));
    expect(first.pieces.any((p) => p.outline.length > 8), isTrue);
    final different = createCharacterPuzzle(inkPoints: squareInk, seed: 720);
    expect(
      different.pieces.map((p) => p.outline),
      isNot(first.pieces.map((p) => p.outline)),
    );
  });

  test('不同字形分布与种子均完整覆盖纸面，内部不重叠，每片包含墨迹点', () {
    for (final ink in [squareInk, horizontalInk, verticalInk]) {
      for (var seed = 0; seed < 12; seed++) {
        final puzzle = createCharacterPuzzle(inkPoints: ink, seed: seed);
        expect(
          puzzle.pieces.fold<double>(0, (sum, p) => sum + p.area),
          closeTo(1, 1e-6),
        );
        for (final piece in puzzle.pieces) {
          expect(piece.area, greaterThan(0));
          expect(piece.contains(piece.inkPoint), isTrue);
          expect(ink, contains(piece.inkPoint));
          for (final p in piece.outline) {
            expect(p.x, inInclusiveRange(-1e-7, 1 + 1e-7));
            expect(p.y, inInclusiveRange(-1e-7, 1 + 1e-7));
          }
        }
        for (var y = 0; y < 40; y++) {
          for (var x = 0; x < 40; x++) {
            final point = Point((x + 0.371) / 40, (y + 0.613) / 40);
            expect(
              puzzle.pieces.where((p) => p.contains(point)),
              hasLength(1),
              reason: 'seed=$seed, point=$point',
            );
          }
        }
      }
    }
  });

  test('每条内部撕裂边由相邻两片反向共用', () {
    final puzzle = createCharacterPuzzle(inkPoints: squareInk, seed: 42);
    final edges = <String, List<(Point<double>, Point<double>)>>{};
    for (final piece in puzzle.pieces) {
      for (var i = 0; i < piece.outline.length; i++) {
        final a = piece.outline[i];
        final b = piece.outline[(i + 1) % piece.outline.length];
        String key(Point<double> p) =>
            '${p.x.toStringAsFixed(7)},${p.y.toStringAsFixed(7)}';
        final keys = [key(a), key(b)]..sort();
        edges.putIfAbsent(keys.join('/'), () => []).add((a, b));
      }
    }
    for (final pair in edges.values) {
      if (pair.length == 1) {
        final (a, b) = pair.single;
        expect(
          (a.x == b.x && (a.x == 0 || a.x == 1)) ||
              (a.y == b.y && (a.y == 0 || a.y == 1)),
          isTrue,
        );
      } else {
        expect(pair, hasLength(2));
        expect(pair.first.$1.distanceTo(pair.last.$2), lessThan(1e-7));
        expect(pair.first.$2.distanceTo(pair.last.$1), lessThan(1e-7));
      }
    }
  });

  test('无效或不足的笔画内部采样点不会生成空白伪拼块', () {
    expect(
      () => createCharacterPuzzle(inkPoints: [], seed: 1),
      throwsArgumentError,
    );
    expect(
      () => createCharacterPuzzle(inkPoints: squareInk, seed: 1, pieceCount: 1),
      throwsArgumentError,
    );
    expect(
      () => createCharacterPuzzle(
        inkPoints: [
          const Point(double.nan, 0.5),
          ...List.filled(6, const Point(0.5, 0.5)),
        ],
        seed: 1,
      ),
      throwsArgumentError,
    );
  });
}
