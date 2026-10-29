import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/domain/textbook_course_diff.dart';

Map<String, dynamic> _lesson({
  List<Map<String, dynamic>> paragraphs = const [],
  List<Map<String, dynamic>> recognitionCharacters = const [],
  List<Map<String, dynamic>> exercises = const [],
}) =>
    {
      'paragraphs': paragraphs,
      'recognitionCharacters': recognitionCharacters,
      'writingCharacters': const <Map<String, dynamic>>[],
      'words': const <Map<String, dynamic>>[],
      'recitations': const <Map<String, dynamic>>[],
      'exercises': exercises,
    };

void main() {
  const categories = [
    'paragraphs',
    'recognitionCharacters',
    'writingCharacters',
    'words',
    'recitations',
    'exercises',
  ];

  test('段落里的视觉换行不算差异，注音完整度单独提示', () {
    final difference = textbookCourseDiff(
      current: _lesson(
        paragraphs: [
          {'text': '黑\n灰色', 'pinyin': null},
        ],
      ),
      generated: _lesson(
        paragraphs: [
          {
            'text': '黑灰色',
            'pinyin': ['hēi', 'huī', 'sè'],
          },
        ],
      ),
      categories: categories,
    );
    expect(difference.categories.first.isSame, isTrue);
    expect(difference.hasPinyinDifference, isTrue);
    expect(difference.currentAnnotatedParagraphs, 0);
    expect(difference.generatedAnnotatedParagraphs, 1);
    expect(difference.isSame, isFalse);
  });

  test('列出只在一边出现的习题和生字', () {
    final difference = textbookCourseDiff(
      current: _lesson(
        recognitionCharacters: [
          {'text': '蝌'},
          {'text': '蚓'},
        ],
        exercises: [
          {'prompt': '读一读。'},
          {'prompt': '教迎嘴龟'},
        ],
      ),
      generated: _lesson(
        recognitionCharacters: [
          {'text': '蝌'},
          {'text': '蚓'},
          {'text': '脑'},
        ],
        exercises: [
          {'prompt': '读一读。'},
          {'prompt': '分角色朗读课文。'},
        ],
      ),
      categories: categories,
    );
    final recognition = difference.categories[1];
    expect(recognition.removed, isEmpty);
    expect(recognition.added, ['脑']);
    expect(recognition.currentCount, 2);
    expect(recognition.generatedCount, 3);
    final exercises = difference.categories.last;
    expect(exercises.removed, ['教迎嘴龟']);
    expect(exercises.added, ['分角色朗读课文。']);
  });

  test('差异位置定位到第一个不同的字', () {
    final window = textbookDifferenceWindow(
      '向前一跳，巴已经不见了。',
      '向前一跳，尾巴已经不见了。',
    );
    expect(window, isNotNull);
    expect(window!.current, '向前一跳，巴已经不见了。');
    expect(window.generated, '向前一跳，尾巴已经不见了。');
    expect(
      textbookDifferenceWindow('两个版本一致', '两个版本一致'),
      isNull,
    );
  });

  test('内容排版：段落缩进，生字分离，非段落换行移除', () {
    expect(
      textbookCategoryContent('paragraphs', [
        {'text': '黑\n灰色'},
        {'text': '游来\n游去'},
      ]),
      '　　黑灰色\n　　游来游去',
    );
    expect(
      textbookCategoryContent('recognitionCharacters', [
        {'text': '蝌'},
        {'text': '蚓'},
      ]),
      '蝌 蚓',
    );
    expect(
      textbookCategoryContent('words', [
        {'text': '妈妈'},
        {'text': '身子'},
      ]),
      '妈妈、身子',
    );
    expect(
      textbookCategoryContent('exercises', [
        {'prompt': '读一读。\n披着碧绿的衣裳 鼓着大大的眼睛'},
      ]),
      '读一读。披着碧绿的衣裳 鼓着大大的眼睛',
    );
    expect(
      textbookCategoryContent('exercises', [
        {'prompt': '读单词\napple banana'},
      ]),
      '读单词 apple banana',
    );
    expect(
      textbookCategoryContent('exercises', [
        {'prompt': '读一读，记一记。\n脑袋 口袋 袋子 袋鼠\n快活 生活 活动 活力'},
      ]),
      '读一读，记一记。脑袋 口袋 袋子 袋鼠 快活 生活 活动 活力',
    );
  });
}
