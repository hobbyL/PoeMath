import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/domain/english_course_parser.dart';
import 'package:poemath/domain/english_practice.dart';

import '../../helpers/english_fixture.dart';
import '../../helpers/math_textbook_fixture.dart';

void main() {
  test('编辑只失效本项内容和音色审核，来源区域与页码严格校验', () {
    final course = englishCourse();
    expect(
      EnglishCourse.fromJson(course.toJson()).lessons.single.approvedCount,
      5,
    );
    final word = course.lessons.single.targets.first;
    expect(word.audioApproved('en-US|test'), isTrue);
    expect(word.audioApproved('en-GB|test'), isFalse);
    final edited = word.change({'text': 'green kite'});
    expect(edited.approved, isFalse);
    expect(edited.audioApproved('en-US|test'), isFalse);
    expect(course.lessons.single.targets[1].approved, isTrue);
    expect(
      () => EnglishSource.fromJson({
        ...word.sources.first.toJson(),
        'left': double.nan,
      }),
      throwsFormatException,
    );
    expect(
      () => EnglishCourse.fromJson({...course.toJson(), 'pageCount': 1}),
      throwsFormatException,
    );
    expect(
      () => EnglishCourse.fromJson({
        ...course.toJson(),
        'lessons': [
          ...course.lessons.map((l) => l.toJson()),
          ...course.lessons.map((l) => l.toJson()),
        ],
      }),
      throwsFormatException,
    );
  });
  test('词义、听音、词块、字母、拼写及开放题资格分别判断', () {
    final course = englishCourse();
    expect(
      buildEnglishQuestions(course, EnglishPracticeKind.meaning),
      hasLength(2),
    );
    expect(
      buildEnglishQuestions(course, EnglishPracticeKind.listening),
      isEmpty,
    );
    expect(
      buildEnglishQuestions(
        course,
        EnglishPracticeKind.listening,
        voiceKey: 'en-US|test',
      ),
      hasLength(2),
    );
    final sentence = buildEnglishQuestions(
      course,
      EnglishPracticeKind.sentence,
    ).single;
    expect(sentence.accepts('I see a red kite.'), isTrue);
    expect(sentence.accepts('Iseearedkite.'), isFalse);
    final letter = buildEnglishQuestions(
      course,
      EnglishPracticeKind.letters,
    ).single;
    expect(letter.accepts('b'), isTrue);
    expect(letter.accepts('B'), isFalse);
    final spelling = buildEnglishQuestions(
      course,
      EnglishPracticeKind.spelling,
    ).first;
    expect(spelling.accepts('RED   KITE'), isTrue);
    expect(spelling.accepts('redkite'), isFalse);
    expect(normalizeEnglishAnswer('  can’t '), "can't");
    expect(
      buildEnglishQuestions(
        course,
        EnglishPracticeKind.original,
      ).single.parentCheck,
      isTrue,
    );
    expect(
      buildEnglishQuestions(
        englishCourse(
          lessons: [
            englishLesson(targets: [englishWord()]),
          ],
        ),
        EnglishPracticeKind.meaning,
      ),
      isEmpty,
    );
    expect(
      buildEnglishQuestions(
        englishCourse(
          lessons: [
            englishLesson(
              targets: [
                englishWord(approved: false),
                englishWord(id: 'other'),
              ],
            ),
          ],
        ),
        EnglishPracticeKind.meaning,
      ),
      isEmpty,
    );
  });
  test('提示和跳过不升级；跨日到期成功升级，同日重复不会升级', () {
    final q = buildEnglishQuestions(
      englishCourse(),
      EnglishPracticeKind.meaning,
    ).first;
    EnglishAnswer answer({
      bool hinted = false,
      bool skipped = false,
      bool correct = true,
    }) => EnglishAnswer(
      question: q,
      answer: q.answers.first,
      correct: skipped ? null : correct,
      hinted: hinted,
      skipped: skipped,
    );
    var r = updateEnglishReview(null, answer(), DateTime(2026, 11, 20));
    expect(r.stage, 0);
    expect(r.nextDay, '2026-11-21');
    r = updateEnglishReview(r, answer(), DateTime(2026, 11, 21));
    expect(r.stage, 1);
    expect(r.nextDay, '2026-11-24');
    r = updateEnglishReview(r, answer(), DateTime(2026, 11, 21));
    expect(r.stage, 1);
    final before = r.toJson();
    r = updateEnglishReview(r, answer(skipped: true), DateTime(2026, 11, 24));
    expect(r.toJson(), before);
    r = updateEnglishReview(r, answer(hinted: true), DateTime(2026, 11, 24));
    expect(r.stage, 0);
    expect(r.nextDay, '2026-11-25');
  });
  test('重复 Lesson / Story 标题不串单元，覆盖目录与附录', () {
    final pages = [
      (MathPageFixture(1)..text('目 录', .1, .1)).build().text,
      (MathPageFixture(2)..text('Unit 1 Garden', .1, .1)).build().text,
      (MathPageFixture(3)
            ..text('Lesson 1', .1, .1)
            ..text('I can fly.', .1, .3))
          .build()
          .text,
      (MathPageFixture(4)..text('Story Time', .1, .1)).build().text,
      (MathPageFixture(5)..text('Revision 1', .1, .1)).build().text,
      (MathPageFixture(6)..text('Unit 2 River', .1, .1)).build().text,
      (MathPageFixture(7)..text('Lesson 1', .1, .1)).build().text,
      (MathPageFixture(8)..text('Story Time', .1, .1)).build().text,
      (MathPageFixture(9)..text('附录二 单元词汇表', .1, .1)).build().text,
    ];
    final parser = EnglishCourseParser(),
        course = parser.outline(englishBook(pages: 9), pages);
    expect(course.lessons, hasLength(7));
    expect(course.coverage, hasLength(9));
    expect(
      course.lessons
          .where((l) => l.title == 'Lesson 1')
          .map((l) => l.id)
          .toSet(),
      hasLength(2),
    );
    expect(course.coverage[9], '附录与词汇来源');
    final draft = parser.prepare(course.lessons[1], [pages[2]], []);
    expect(draft.targets.any((t) => t.text == 'I can fly.'), isTrue);
    expect(draft.approvedCount, 0);
  });
  test('词组与抬高的弯撇号按源空白拼合，不把字母拆成单词', () {
    final f = MathPageFixture(1)
      ..text('Family', .1, .1)
      ..text('can’t fly', .1, .3);
    final text = f.build().text;
    expect(englishPageLines(text).map((l) => l.text), ['Family', 'can’t fly']);
  });
  test('四张编号图卡按卡片号排序，卡片句子坐标不决定跨卡顺序', () {
    final markers = [
      const EnglishTextLine(
        '1',
        EnglishSource(21, left: .452, top: .156, right: .460, bottom: .174),
      ),
      const EnglishTextLine(
        '2',
        EnglishSource(21, left: .895, top: .154, right: .912, bottom: .173),
      ),
      const EnglishTextLine(
        '3',
        EnglishSource(21, left: .447, top: .510, right: .464, bottom: .529),
      ),
      const EnglishTextLine(
        '4',
        EnglishSource(21, left: .894, top: .588, right: .913, bottom: .608),
      ),
    ];
    expect(
      englishNumberedCardForSource(
        const EnglishSource(
          21,
          left: .147,
          top: .219,
          right: .285,
          bottom: .235,
        ),
        markers,
      ),
      1,
    );
    expect(
      englishNumberedCardForSource(
        const EnglishSource(
          21,
          left: .582,
          top: .650,
          right: .757,
          bottom: .668,
        ),
        markers,
      ),
      4,
    );
    expect(
      englishNumberedCardForSource(
        const EnglishSource(
          21,
          left: .091,
          top: .803,
          right: .259,
          bottom: .818,
        ),
        markers,
      ),
      3,
    );
    expect(
      englishNumberedCardForSource(
        const EnglishSource(
          21,
          left: .604,
          top: .295,
          right: .762,
          bottom: .313,
        ),
        markers,
      ),
      2,
    );
    expect(
      englishNumberedCardForSource(
        const EnglishSource(
          21,
          left: .604,
          top: .295,
          right: .762,
          bottom: .313,
        ),
        markers.take(3).toList(),
      ),
      isNull,
    );
  });
  test('整理句子时先按图卡编号，再保留卡片内行优先顺序', () {
    final fixture = MathPageFixture(3)
      ..text('1', .452, .156, width: .008, height: .018)
      ..text('2', .895, .154, width: .017, height: .019)
      ..text('3', .447, .510, width: .017, height: .019)
      ..text('4', .894, .588, width: .019, height: .020)
      ..text('Who is he?', .147, .219, width: .012, height: .016)
      ..text('Is he a boy?', .604, .295, width: .012, height: .018)
      ..text('Is he a tiger?', .582, .650, width: .012, height: .018)
      ..text('Is he a man?', .091, .803, width: .012, height: .015);
    final page = fixture.build().text;
    final plan = englishLesson(targets: const [])
        .change({'startPage': 3, 'endPage': 3});
    final prepared = EnglishCourseParser().prepare(plan, [page], []);
    expect(prepared.targets.map((target) => target.text), [
      'Who is he?',
      'Is he a boy?',
      'Is he a man?',
      'Is he a tiger?',
    ]);
  });
}
