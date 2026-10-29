import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_dictation.dart';

import '../helpers/textbook_course_fixture.dart';
import '../helpers/writing_fixture.dart';

TextbookCourseLesson _lesson({
  String character = '行',
  List<String>? pinyin = const ['xíng'],
  required List<Map<String, dynamic>> words,
}) {
  final raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
  lesson['writingCharacters'] = [
    {
      ...courseFixtureText('writing-001', character, pinyin),
      'requirement': 'writing',
    },
  ];
  lesson['words'] = [
    for (var i = 0; i < words.length; i++)
      {
        ...courseFixtureText(
          'word-$i',
          words[i]['text'] as String,
          words[i]['pinyin'] as List<String>?,
        ),
        'requirement': 'reading',
      },
  ];
  // 保留原文与背诵指纹，但不让它替自定义词语提供语境。
  ((lesson['paragraphs'] as List).single as Map)['pinyin'] = null;
  return TextbookCoursePack.fromJson(raw).lessons.single;
}

void main() {
  test('目标只取本课会写字，课内词语用于报出各字位置', () {
    final targets = textbookDictationTargets(writingFixture().lessons.single);
    expect(targets.map((t) => t.id), ['writing-001', 'writing-002']);
    expect(targets.map((t) => t.text), ['星', '月']);
    expect(targets.map((t) => t.pinyin), ['xīng', 'yuè']);
    expect(targets.map((t) => t.prompt), [
      '星月，请写第1个字。',
      '星月，请写第2个字。',
    ]);
    expect(targets.every((t) => t.hasContext), isTrue);
  });

  test('多音字跳过错误读音的词，采用匹配本课读音的位置', () {
    final lesson = _lesson(
      words: [
        {
          'text': '银行',
          'pinyin': <String>['yín', 'háng'],
        },
        {
          'text': '行走',
          'pinyin': <String>['xing2', 'zǒu'],
        },
      ],
    );
    final target = textbookDictationTargets(lesson).single;
    expect(target.prompt, '行走，请写第1个字。');
    expect(target.hasContext, isTrue);
  });

  test('相同字在同一词里读音不同时，播报正确的位置', () {
    final lesson = _lesson(
      pinyin: ['háng'],
      words: [
        {
          'text': '行行',
          'pinyin': <String>['xíng', 'háng'],
        },
      ],
    );
    final target = textbookDictationTargets(lesson).single;
    expect(target.prompt, '行行，请写第2个字。');
  });

  test('不借用同音字的组词，也不将缺注音视为相同读音', () {
    final lesson = _lesson(
      words: [
        {
          'text': '形状',
          'pinyin': <String>['xíng', 'zhuàng'],
        },
        {'text': '行走', 'pinyin': null},
      ],
    );
    final target = textbookDictationTargets(lesson).single;
    expect(target.prompt, '请写：行。');
    expect(target.hasContext, isFalse);
  });

  test('空白不占注音，补充平面汉字与标点不会错位', () {
    final lesson = _lesson(
      character: '𠀀',
      pinyin: ['hē'],
      words: [
        {
          'text': '月， 星\n𠀀',
          'pinyin': <String>['yuè', '，', 'xīng', 'hē'],
        },
      ],
    );
    final target = textbookDictationTargets(lesson).single;
    expect(target.prompt, '星𠀀，请写第2个字。');
  });

  test('没有词语时使用含正确注音的课文短句', () {
    final raw = writingFixture().toJson();
    final lesson = (raw['lessons'] as List).single as Map;
    lesson['words'] = <Object?>[];
    (lesson['coverage'] as Map)['words'] = 'notApplicable';
    final targets = textbookDictationTargets(
      TextbookCoursePack.fromJson(raw).lessons.single,
    );
    expect(targets.first.prompt, '星𠀀，请写第1个字。');
    // 「月」在原文中是单字短句，没有足以消歧的词组。
    expect(targets.last.prompt, '请写：月。');
    expect(targets.last.hasContext, isFalse);
  });

  test('打乱保留所有目标且每轮不重复，不修改原始清单', () {
    final targets = textbookDictationTargets(writingFixture().lessons.single);
    final orders = <String>{};
    for (var seed = 0; seed < 20; seed++) {
      final round = shuffledDictationTargets(targets, random: Random(seed));
      expect(round.map((t) => t.id).toSet(), {'writing-001', 'writing-002'});
      expect(round.length, 2);
      orders.add(round.map((t) => t.id).join(','));
    }
    expect(orders.length, 2);
    expect(targets.map((t) => t.id), ['writing-001', 'writing-002']);
    expect(shuffledDictationTargets([targets.last]).single.id, 'writing-002');
    expect(shuffledDictationTargets([]), isEmpty);
  });
}
