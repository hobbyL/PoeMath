import 'dart:convert';

import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/domain/english_phrase_generation.dart';

import 'english_fixture.dart';

EnglishCourse phraseCourse() => englishCourse(
  lessons: [
    englishLesson(
      targets: [
        englishWord(
          id: 'father',
          text: 'father',
          meaning: '爸爸',
          approved: false,
        ),
        englishWord(
          id: 'mother',
          text: 'mother',
          meaning: '妈妈',
          approved: false,
        ),
      ],
    ),
  ],
);

String phraseResponse({String word = 'father'}) => jsonEncode({
  'items': [
    {
      'sourceId': word,
      'phrases': [
        {'text': 'my $word', 'meaning': word == 'father' ? '我的爸爸' : '我的妈妈'},
        {
          'text': 'a kind $word',
          'meaning': word == 'father' ? '一位和蔼的爸爸' : '一位和蔼的妈妈',
        },
      ],
    },
  ],
});

List<EnglishTarget> phraseTargets(
  EnglishCourse course, {
  String word = 'father',
}) {
  final lesson = course.lessons.single;
  return EnglishPhraseBatch(
    bookId: course.bookId,
    lessonId: lesson.id,
    seeds: englishPhraseSeeds(lesson),
    existingTexts: lesson.targets.map((t) => t.text),
  ).parse(phraseResponse(word: word), now: DateTime.utc(2026, 11, 25));
}

EnglishCourse withPhrases(EnglishCourse course) => course.change({
  'schemaVersion': 2,
  'lessons': [
    course.lessons.single.change({
      'targets': [
        ...course.lessons.single.targets,
        ...phraseTargets(course),
      ].map((t) => t.toJson()).toList(),
    }).toJson(),
  ],
});

String phraseChatResponse(String content) => jsonEncode({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': 'stop',
    },
  ],
});
