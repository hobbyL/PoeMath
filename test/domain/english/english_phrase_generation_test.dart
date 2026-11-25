import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/domain/english_phrase_generation.dart';
import 'package:poemath/domain/english_practice.dart';

import '../../helpers/english_fixture.dart';
import '../../helpers/english_phrase_fixture.dart';

void main() {
  late EnglishCourse course;
  late EnglishPhraseBatch batch;
  setUp(() {
    course = phraseCourse();
    batch = EnglishPhraseBatch(
      bookId: course.bookId,
      lessonId: course.lessons.single.id,
      seeds: englishPhraseSeeds(course.lessons.single),
      existingTexts: ['father', 'mother'],
    );
  });

  test('拓展来源独立、无需审核可练习，旧目标指纹及课程保持兼容', () {
    final legacy = englishCourse();
    final restored = EnglishCourse.fromJson(legacy.toJson());
    expect(restored.schemaVersion, 1);
    expect(restored.toJson(), legacy.toJson());
    expect(
      restored.lessons.single.targets.first.toJson(),
      isNot(contains('phraseSource')),
    );
    final expanded = withPhrases(course);
    expect(
      EnglishCourse.fromJson(expanded.toJson()).toJson(),
      expanded.toJson(),
    );
    expect(
      expanded.lessons.single.targets.take(2).map((t) => t.fingerprint),
      course.lessons.single.targets.map((t) => t.fingerprint),
    );
    final phrase = expanded.lessons.single.phrases.first;
    expect(phrase.sources, isEmpty);
    expect(phrase.picture, isNull);
    expect(phrase.approved, isFalse);
    expect(phrase.audioApproved('voice'), isFalse);
    expect(phrase.isLearnableVocabulary, isTrue);
    final spelling = buildEnglishQuestions(
      expanded,
      EnglishPracticeKind.spelling,
    ).singleWhere((q) => q.target.id == phrase.id);
    expect(spelling.accepts('MY   FATHER'), isTrue);
    expect(spelling.accepts('myfather'), isFalse);
    expect(spelling.options.where((v) => v == ' '), hasLength(1));
    validateEnglishQuestion(
      expanded,
      EnglishQuestion.fromJson(spelling.toJson()),
    );
    expect(
      buildEnglishQuestions(
        expanded,
        EnglishPracticeKind.listening,
        voiceKey: 'voice',
      ),
      isEmpty,
    );
    expect(() => expanded.change({'schemaVersion': 1}), throwsFormatException);
    expect(() => phrase.change({'origin': 'textbook'}), throwsFormatException);
    expect(() => phrase.change({'phraseSource': null}), throwsFormatException);
    expect(
      () => phrase.change({'reviewDigest': phrase.fingerprint}),
      throwsFormatException,
    );
    expect(
      () => phrase.change({
        'sources': [const EnglishSource(2).toJson()],
      }),
      throwsFormatException,
    );
  });

  test('纯词界、词数、中文义、去重及部分有效输出', () {
    final result = batch.parse(
      jsonEncode({
        'items': [
          {
            'sourceId': 'father',
            'phrases': [
              {'text': 'my grandfather', 'meaning': '我的爷爷'},
              {'text': 'my father', 'meaning': ''},
              {'text': 'my father is a very kind man', 'meaning': '爸爸很和蔼'},
              {'text': 'my father', 'meaning': '我的爸爸'},
              {'text': 'MY  FATHER', 'meaning': '爸爸'},
              {'text': 'a kind father', 'meaning': '一位和蔼的爸爸'},
            ],
          },
        ],
      }),
      now: DateTime.utc(2026),
    );
    expect(result.map((t) => t.text), ['my father', 'a kind father']);
    final repeated = batch.parse(phraseResponse(), now: DateTime.utc(2027));
    expect(repeated.map((t) => t.id), result.map((t) => t.id));
    final partial = batch.parse(
      jsonEncode({
        'items': [
          {
            'sourceId': 'father',
            'phrases': [
              {'text': 'my father', 'meaning': '我的爸爸'},
              {'text': 'kind father', 'meaning': 'kind father'},
            ],
          },
        ],
      }),
      now: DateTime.utc(2026),
    );
    expect(partial.map((t) => t.text), ['my father']);
  });

  test('未知目标、重复目标、额外字段及全无效输出失败，不提取任意解释中的 JSON', () {
    final valid = jsonDecode(phraseResponse()) as Map<String, dynamic>;
    final item = (valid['items'] as List).single as Map<String, dynamic>;
    for (final invalid in [
      {
        'items': [
          {...item, 'sourceId': 'unrequested'},
        ],
      },
      {
        'items': [item, item],
      },
      {...valid, 'extra': true},
      {
        'items': [
          {
            ...item,
            'phrases': [
              {'text': 'father', 'meaning': '爸爸'},
            ],
          },
        ],
      },
      {
        'items': [
          {
            ...item,
            'phrases': [
              {'text': 'my\nfather', 'meaning': '我的爸爸'},
            ],
          },
        ],
      },
      {'items': <Object?>[]},
    ]) {
      expect(
        () => batch.parse(jsonEncode(invalid), now: DateTime.utc(2026)),
        throwsFormatException,
      );
    }
    expect(
      () => batch.parse('说明：${phraseResponse()}', now: DateTime.utc(2026)),
      throwsFormatException,
    );
    expect(
      batch.parse('```json\n${phraseResponse()}\n```', now: DateTime.utc(2026)),
      hasLength(2),
    );
  });

  test('补齐仅针对原书单词；已有短语与改过 ID 的同义原词不重复生成', () {
    final expanded = withPhrases(course);
    final lesson = expanded.lessons.single;
    final changed = lesson.change({
      'targets': [
        lesson.targets.first.change({'id': 'reparsed-father'}).toJson(),
        ...lesson.targets.skip(1).map((t) => t.toJson()),
        englishWord(id: 'phrase', text: 'look at', meaning: '看').toJson(),
        englishWord(
          id: 'parent',
          text: 'uncle',
          meaning: '叔叔',
          origin: 'parent',
        ).toJson(),
      ],
    });
    expect(englishPhraseSeeds(changed).map((s) => (s.target.id, s.missing)), [
      ('mother', 2),
    ]);
    expect(isEnglishPhraseSeed(lesson.phrases.first), isFalse);
    final missingOne = lesson.change({
      'targets': lesson.targets
          .where((t) => t.text != 'a kind father')
          .map((t) => t.toJson())
          .toList(),
    });
    expect(
      englishPhraseSeeds(missingOne).map((s) => (s.target.id, s.missing)),
      [('father', 1), ('mother', 2)],
    );
  });
}
