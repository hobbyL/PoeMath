import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/picture_story_practice_record.dart';

void main() {
  test('多段记录按位置拼接修改后的答案并汇总时长', () {
    final record = PictureStoryPracticeRecord(
      id: 'record-1',
      profileId: 'default',
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026, 10, 29),
      status: 'draft',
      segmentsJson: '[]',
    );
    record.setSegments([
      const PictureStorySegment(
        id: 'second',
        position: 1,
        audioPath: '/tmp/second.wav',
        durationSeconds: 3,
        transcript: '小狗也跑来了',
        editedText: '小狗也跑来了。',
      ),
      const PictureStorySegment(
        id: 'first',
        position: 0,
        audioPath: '/tmp/first.wav',
        durationSeconds: 2,
        transcript: '孩子在放风筝',
      ),
    ]);

    expect(record.answerText, '孩子在放风筝\n小狗也跑来了。');
    expect(record.totalDurationSeconds, 5);
    expect(record.segments.map((segment) => segment.id), ['first', 'second']);
  });

  test('主动清空答案保存后仍为空，原始转写保留供回看', () {
    const segment = PictureStorySegment(
      id: 'one',
      position: 0,
      audioPath: '/tmp/one.wav',
      durationSeconds: 1,
      transcript: '原始文字',
      editedText: '  ',
    );

    expect(segment.answerText.trim(), isEmpty);
    final restored = PictureStorySegment.fromJson(segment.toJson());
    expect(restored.answerText.trim(), isEmpty);
    expect(restored.transcript, '原始文字');
  });

  test('旧版空编辑记录保持原有答案，随后清空采用新语义', () {
    final legacy = PictureStorySegment.fromJson({
      'id': 'old',
      'position': 0,
      'audioPath': '/tmp/old.wav',
      'durationSeconds': 1,
      'transcript': '旧回答',
      'editedText': '',
    });
    expect(legacy.answerText, '旧回答');
    expect(PictureStorySegment.fromJson(legacy.toJson()).answerText, '旧回答');
    expect(
      PictureStorySegment.fromJson(legacy.copyWith(editedText: '').toJson())
          .answerText,
      isEmpty,
    );
  });
  test('旧片段位置有缺口和重复时稳定排序，保存后连续且保留内容', () {
    final record = PictureStoryPracticeRecord(
      id: 'legacy',
      profileId: 'default',
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026, 11, 9),
      status: 'draft',
      segmentsJson: '[]',
    );
    final input = [
      for (var i = 0; i < 40; i++)
        PictureStorySegment(
          id: '$i',
          position: 5,
          audioPath: '/$i.wav',
          durationSeconds: 1,
          transcript: '文字$i',
        ),
    ];
    record.segmentsJson = jsonEncode(input.map((s) => s.toJson()).toList());
    final decoded = record.segments;
    expect(decoded.map((s) => s.id), input.map((s) => s.id));
    record.setSegments(decoded);
    expect(record.segments.map((s) => s.position), List.generate(40, (i) => i));
    expect(
      record.segments.map((s) => s.audioPath),
      input.map((s) => s.audioPath),
    );
    expect(record.answerText, input.map((s) => s.answerText).join('\n'));
    expect(record.totalDurationSeconds, 40);
  });
}
