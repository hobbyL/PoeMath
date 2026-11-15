import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_writing_attempt.dart';

import '../../helpers/writing_attempt_fixture.dart';

void main() {
  for (final kind in WritingAttemptKind.values) {
    test('$kind 作品及 UTC 时间可独立 JSON 往返', () {
      final original = writingAttemptFixture(kind: kind);
      final reopened = WritingAttempt.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(reopened.toJson(), original.toJson());
      expect(reopened.durationSeconds, 65);
      expect(reopened.startedAt.isUtc, isTrue);
      expect(() => reopened.referenceStrokes.clear(), throwsUnsupportedError);
      if (kind == WritingAttemptKind.puzzle) {
        expect(reopened.puzzle!.placementOrder, [4, 1, 2, 5, 0, 3]);
        expect(
          () => reopened.puzzle!.pieces.first.clear(),
          throwsUnsupportedError,
        );
      } else {
        expect(reopened.strokes.first.first, const Point<double>(0.1, 0.2));
        expect(() => reopened.strokes.first.clear(), throwsUnsupportedError);
      }
    });
  }

  test('捕获按画布缩放，保留位置、笔宽及格外笔迹，不受后续编辑影响', () {
    final references = ['M 0 0 L 10 10'];
    final strokes = [
      <Point<double>>[
        const Point<double>(24, 48),
        const Point<double>(216, 192),
        const Point<double>(264, -24),
      ],
    ];
    final snapshot = WritingAttempt.captureWriting(
      id: 'trace-1',
      kind: WritingAttemptKind.trace,
      startedAt: DateTime.utc(2026, 11, 15, 10),
      completedAt: DateTime.utc(2026, 11, 15, 10, 0, 3),
      referenceStrokes: references,
      strokes: strokes,
      canvasSide: 240,
    );
    strokes.first.clear();
    references.clear();
    expect(snapshot.strokes.single, const [
      Point<double>(0.1, 0.2),
      Point<double>(0.9, 0.8),
      Point<double>(1.1, -0.1),
    ]);
    expect(snapshot.strokeWidth, 3 / 240);
    expect(snapshot.referenceStrokes, ['M 0 0 L 10 10']);
    expect(snapshot.durationSeconds, 3);
  });

  test('长单笔采样保留起止与折线路径，不能减少笔数', () {
    final points = <Point<double>>[
      for (var i = 0; i <= 1024; i++)
        Point<double>(
          i <= 512 ? i / 512 * 240 : 240,
          i <= 512 ? 0 : (i - 512) / 512 * 240,
        ),
    ];
    final snapshot = WritingAttempt.captureWriting(
      id: 'long-1',
      kind: WritingAttemptKind.free,
      startedAt: DateTime.utc(2026),
      completedAt: DateTime.utc(2026),
      strokes: [
        points,
        const [Point<double>(120, 120)],
      ],
      canvasSide: 240,
    );
    expect(snapshot.strokes, hasLength(2));
    expect(
      snapshot.strokes.first,
      hasLength(WritingAttempt.maxPointsPerStroke),
    );
    expect(snapshot.strokes.first.first, const Point<double>(0, 0));
    expect(snapshot.strokes.first.last, const Point<double>(1, 1));
    expect(snapshot.strokes.first[255].x, closeTo(1, 0.003));
    expect(snapshot.strokes.first[256].y, closeTo(0, 0.003));
    expect(snapshot.strokes.last.single, const Point<double>(0.5, 0.5));
  });

  test('无笔迹的完成记录保留为空，不能用参考字形填充用户笔迹', () {
    final snapshot = WritingAttempt.captureWriting(
      id: 'empty',
      kind: WritingAttemptKind.free,
      startedAt: DateTime.utc(2026),
      completedAt: DateTime.utc(2026),
      strokes: const [],
      canvasSide: 240,
    );
    expect(WritingAttempt.fromJson(snapshot.toJson()).strokes, isEmpty);
  });

  test('损坏时间、种类、笔迹、笔宽和不匹配作品必须拒绝', () {
    final original = writingAttemptFixture().toJson();
    for (final patch in <Map<String, dynamic>>[
      {'v': 2},
      {'id': ''},
      {'kind': 'check'},
      {'startedAt': '2026-11-32T11:05:45.000Z'},
      {'completedAt': '2026-01-01T00:00:00.000Z'},
      {'strokeWidth': -1},
      {'strokeWidth': double.nan},
      {'strokes': null},
      {
        'strokes': [
          [<double>[]],
        ],
      },
      {
        'strokes': [
          [
            [double.infinity, 0],
          ],
        ],
      },
      {
        'strokes': [
          [
            ['0.5', 0.5],
          ],
        ],
      },
      {
        'referenceStrokes': [null],
      },
      {
        'puzzle': writingAttemptFixture(kind: WritingAttemptKind.puzzle).puzzle!
            .toJson(),
      },
    ]) {
      expect(
        () => WritingAttempt.fromJson({...original, ...patch}),
        throwsFormatException,
        reason: patch.toString(),
      );
    }
  });

  test('未完成、重复顺序、格外碎片和非法提示状态不能作为拼装完成保存', () {
    final original = writingAttemptFixture(kind: WritingAttemptKind.puzzle)
        .toJson();
    final puzzle = original['puzzle'] as Map<String, dynamic>;
    for (final patch in <Map<String, dynamic>>[
      {
        'placementOrder': [0, 1],
      },
      {
        'placementOrder': [0, 1, 2, 3, 4, 4],
      },
      {
        'placementOrder': [0, 1, 2, 3, 4, 6],
      },
      {'hintEnabled': 'false'},
      {'wrongPlacements': -1},
      {
        'pieces': [
          [
            [0, 0],
            [2, 0],
            [0, 1],
          ],
        ],
      },
    ]) {
      expect(
        () => WritingAttempt.fromJson({
          ...original,
          'puzzle': {...puzzle, ...patch},
        }),
        throwsFormatException,
      );
    }
  });
}
