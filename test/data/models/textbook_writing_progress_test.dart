import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/domain/textbook_writing_review.dart';

void main() {
  Map<String, dynamic> legacyRecord() => {
    'fingerprint': 'original-character',
    'traceCount': 2,
    'freeCount': 3,
    'geometryPasses': 1,
    'parentConfirms': 4,
    'stage': 2,
    'lastParentDay': '2026-11-14',
    'nextDay': '2026-11-21',
    'lastDay': '2026-11-14',
    'advancedDay': '2026-11-14',
  };

  test('旧 v1 记录缺拼装字段读作零，书写和复习历史全部保留', () {
    final key = WritingProgress.targetKey('lesson', 'character');
    final old = {
      'v': 1,
      'profileId': 'profile',
      'bookId': 'book',
      'editionId': 'edition',
      'revision': 7,
      'operations': ['trace-done'],
      'records': {key: legacyRecord()},
    };
    final progress = WritingProgress.fromJson(old);
    expect(progress.records[key]!.puzzleCount, 0);
    expect(progress.records[key]!.toJson(), {
      ...legacyRecord(),
      'puzzleCount': 0,
    });
    expect(progress.revision, 7);
    expect(progress.operations, ['trace-done']);
    expect(
      WritingProgress.fromJson(progress.toJson()).toJson(),
      progress.toJson(),
    );
  });

  test('拼装只累加独立事实，不改变书写、家长确认或任何复习日期', () {
    final original = WritingRecord.fromJson({
      ...legacyRecord(),
      'puzzleCount': 5,
    });
    final assembled = writingRecordStage(original, WritingStageDone.puzzle);
    expect(assembled.toJson(), {...original.toJson(), 'puzzleCount': 6});
    expect(assembled.badge, WritingBadge.written);
    expect(
      writingRecordStage(assembled, WritingStageDone.trace).puzzleCount,
      6,
    );
    expect(writingRecordStage(assembled, WritingStageDone.free).puzzleCount, 6);
    expect(
      writingRecordParentConfirm(
        assembled,
        passed: false,
        day: '2026-11-15',
      ).puzzleCount,
      6,
    );
    expect(
      const WritingRecord(fingerprint: 'glyph', puzzleCount: 1).badge,
      WritingBadge.assembled,
    );
    expect(
      const WritingRecord(
        fingerprint: 'glyph',
        puzzleCount: 1,
        traceCount: 1,
      ).badge,
      WritingBadge.traced,
    );
  });

  test('存在但损坏的拼装次数必须报错，不静默当作零', () {
    for (final value in <Object?>[null, -1, 1.5, '1', true]) {
      expect(
        () => WritingRecord.fromJson({...legacyRecord(), 'puzzleCount': value}),
        throwsFormatException,
      );
    }
  });
}
