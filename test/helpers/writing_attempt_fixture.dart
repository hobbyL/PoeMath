import 'dart:math';

import 'package:poemath/data/models/textbook_writing_attempt.dart';

WritingAttempt writingAttemptFixture({
  String id = 'attempt-1',
  WritingAttemptKind kind = WritingAttemptKind.free,
  DateTime? startedAt,
  DateTime? completedAt,
  List<String>? referenceStrokes,
}) {
  final end = completedAt ?? DateTime.utc(2026, 11, 15, 11, 5, 45);
  return WritingAttempt(
    id: id,
    kind: kind,
    startedAt: startedAt ?? end.subtract(const Duration(seconds: 65)),
    completedAt: end,
    referenceStrokes:
        referenceStrokes ?? const ['M 200 100 L 260 100 L 260 850 L 200 850 Z'],
    strokes: kind == WritingAttemptKind.puzzle
        ? const []
        : const [
            [Point<double>(0.1, 0.2), Point<double>(0.9, 0.8)],
            [Point<double>(0.4, 0.1), Point<double>(0.4, 0.9)],
          ],
    strokeWidth: kind == WritingAttemptKind.puzzle ? 0 : 0.0125,
    puzzle: kind != WritingAttemptKind.puzzle
        ? null
        : WritingPuzzleResult(
            pieces: [
              for (var row = 0; row < 2; row++)
                for (var column = 0; column < 3; column++)
                  [
                    Point<double>(column / 3, row / 2),
                    Point<double>((column + 1) / 3, row / 2),
                    Point<double>((column + 1) / 3, (row + 1) / 2),
                    Point<double>(column / 3, (row + 1) / 2),
                  ],
            ],
            placementOrder: const [4, 1, 2, 5, 0, 3],
            hintEnabled: false,
            wrongPlacements: 2,
          ),
  );
}
