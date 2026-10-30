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

    expect(record.answerText, '孩子在放风筝小狗也跑来了。');
    expect(record.totalDurationSeconds, 5);
    expect(record.segments.map((segment) => segment.id), ['first', 'second']);
  });

  test('空编辑文字回退到原始转写', () {
    const segment = PictureStorySegment(
      id: 'one',
      position: 0,
      audioPath: '/tmp/one.wav',
      durationSeconds: 1,
      transcript: '原始文字',
      editedText: '  ',
    );

    expect(segment.answerText, '原始文字');
  });
}
