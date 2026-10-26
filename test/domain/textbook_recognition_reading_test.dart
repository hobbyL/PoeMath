import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_recognition_reading.dart';
import '../helpers/textbook_course_fixture.dart';

void main() {
  RecognitionReadingOutcome match(String target, String pinyin, String text) =>
      matchRecognitionReading(target: target, pinyin: pinyin, transcript: text);

  test('单字和同音同调可匹配，不把同音字形差异当作不会读', () {
    expect(match('晴', 'qíng', '晴。'), RecognitionReadingOutcome.matched);
    expect(match('晴', 'qing2', ' 情！ '), RecognitionReadingOutcome.matched);
    expect(match('晴', 'qíng', '清'), RecognitionReadingOutcome.needsPractice);
    expect(match('晴', 'qíng', '青'), RecognitionReadingOutcome.needsPractice);
    expect(match('晴', 'qíng', '月'), RecognitionReadingOutcome.needsPractice);
    expect(match('女', 'nǚ', '女'), RecognitionReadingOutcome.needsContext);
    expect(match('绿', 'lǜ', '绿'), RecognitionReadingOutcome.needsContext);
  });

  test('多音字单读不能从同形识别结果推断读音', () {
    expect(recognitionReadingNeedsContext('长'), isTrue);
    expect(recognitionReadingNeedsContext('星'), isFalse);
    expect(match('长', 'zhǎng', '长'), RecognitionReadingOutcome.needsContext);
    expect(match('长', 'cháng', '长'), RecognitionReadingOutcome.needsContext);
    expect(match('行', 'xíng', '行'), RecognitionReadingOutcome.needsContext);
  });

  test('组词使用明确词典语境，多音字读错词不能按包含目标字通过', () {
    expect(match('长', 'zhǎng', '长大'), RecognitionReadingOutcome.needsContext);
    expect(match('行', 'xíng', '银行'), RecognitionReadingOutcome.needsPractice);
    expect(match('行', 'háng', '银行'), RecognitionReadingOutcome.matched);
    expect(match('长', 'zhǎng', '长星'), RecognitionReadingOutcome.needsContext);
    expect(match('星', 'xīng', '星星'), RecognitionReadingOutcome.matched);
  });

  test('课内明确逐字注音补充词典空缺，冲突语境或无注音不猜读音', () {
    final raw = courseFixture();
    final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
    lesson['paragraphs'] = [
      ...lesson['paragraphs'] as List,
      courseFixtureText(
        'word',
        '小蝌蚪长大了。',
        ['xiǎo', 'kē', 'dǒu', 'zhǎng', 'dà', 'le5', '。'],
      ),
      courseFixtureText('other', '长大', ['cháng', 'dà']),
    ];
    final paragraphs =
        TextbookCoursePack.fromJson(raw).lessons.single.paragraphs;
    final context = paragraphs[paragraphs.length - 2];
    final conflict = paragraphs.last;
    expect(
      matchRecognitionReading(
        target: '长',
        pinyin: 'zhǎng',
        transcript: '长大',
        contexts: [context],
      ),
      RecognitionReadingOutcome.matched,
    );
    expect(
      matchRecognitionReading(
        target: '长',
        pinyin: 'cháng',
        transcript: '长大',
        contexts: [context],
      ),
      RecognitionReadingOutcome.needsPractice,
    );
    expect(
      matchRecognitionReading(
        target: '长',
        pinyin: 'zhǎng',
        transcript: '长大',
        contexts: [context, conflict],
      ),
      RecognitionReadingOutcome.inconclusive,
    );
    expect(
      matchRecognitionReading(
        target: '长',
        pinyin: 'zhǎng',
        transcript: '长',
        contexts: [context],
      ),
      RecognitionReadingOutcome.needsContext,
    );
  });

  test('静音、未知字、跨句拼接、不相关句子和不明确拼音不记对错', () {
    for (final text in [
      '',
      '  ',
      '……',
      '123',
      'xing',
      '月亮',
      '星，大',
      '星 月',
      '我不认识这个星',
    ]) {
      expect(
        match('星', 'xīng', text),
        RecognitionReadingOutcome.inconclusive,
        reason: text,
      );
    }
    expect(match('𠀀', 'hē', '𠀀'), RecognitionReadingOutcome.inconclusive);
    expect(match('星', '', '星'), RecognitionReadingOutcome.inconclusive);
    expect(match('星', 'xing', '星'), RecognitionReadingOutcome.inconclusive);
    expect(match('长', 'zhǎng', '长，大'), RecognitionReadingOutcome.inconclusive);
    expect(match('星', 'xīng', '不认识星'), RecognitionReadingOutcome.needsContext);
  });
}
