import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';

import '../../helpers/textbook_course_fixture.dart';

void main() {
  test('编辑习题答案保留排版；改写题目清除旧排版及加点位置', () {
    final raw = courseFixture();
    final exercise =
        ((raw['lessons'] as List).single['exercises'] as List).single as Map;
    exercise['prompt'] = '读一读。\n星光\t月光';
    exercise['promptLayout'] = [
      [
        {'text': '读一读。', 'emphasis': <int>[]},
      ],
      [
        {
          'text': '星光',
          'emphasis': [0],
        },
        {'text': '月光', 'emphasis': <int>[]},
      ],
    ];
    final pack = TextbookCoursePack.fromJson(raw);
    final changedAnswer = editTextbookCourseNode(pack, 'exercise-001', {
      'answers': ['星光'],
      'answerOrigin': 'reviewerReference',
    });
    expect(
      changedAnswer.lessons.single.exercises.single.toJson()['promptLayout'],
      exercise['promptLayout'],
    );
    final changedPrompt =
        editTextbookCourseNode(pack, 'exercise-001', {'prompt': '新的题目。'});
    expect(changedPrompt.lessons.single.exercises.single.prompt, '新的题目。');
    expect(changedPrompt.lessons.single.exercises.single.promptLayout, isEmpty);
    expect(
      changedPrompt.lessons.single.exercises.single
          .toJson()
          .containsKey('promptLayout'),
      isFalse,
    );
    expect(changedPrompt.contentRevision, pack.contentRevision + 1);
  });

  test('编辑正文使段落、课目、整包及关联背诵待审，重新绑定同一字符范围', () {
    final pack = TextbookCoursePack.fromJson(
      courseFixture(reviewed: true, permitted: true),
    );
    final edited = editTextbookCourseNode(pack, 'paragraph-001', {
      'text': '月𠀀，星。',
      'pinyin': ['yuè', 'hē', '，', 'xīng', '。'],
    });
    expect(edited.contentRevision, pack.contentRevision + 1);
    expect(edited.status, 'draft');
    expect(edited.review.status, TextbookReviewStatus.unreviewed);
    final lesson = edited.lessons.single;
    expect(
      lesson.paragraphs.single.review.status,
      TextbookReviewStatus.unreviewed,
    );
    expect(lesson.isApproved, isFalse);
    expect(
      lesson.recitations.single.review.status,
      TextbookReviewStatus.unreviewed,
    );
    expect(lesson.recitations.single.ranges.single.start, 0);
    expect(lesson.recitations.single.ranges.single.end, 2);
    expect(
      lesson.recitations.single.ranges.single.textSha256,
      textbookTextDigest('月𠀀'),
    );
    expect(lesson.words.single.isApproved, isTrue);
    expect(pack.lessons.single.paragraphs.single.text, '星𠀀，月。');
    expect(edited.isPublishable, isFalse);
  });

  test('禁止编辑身份、ID、错位注音或把会认字改为听写目标', () {
    final pack = TextbookCoursePack.fromJson(courseFixture());
    for (final changes in [
      <String, dynamic>{'id': 'changed'},
      {'unitId': 'other'},
      {
        'pinyin': ['chOn'],
      },
      {'text': '新内容'},
    ]) {
      expect(
        () => editTextbookCourseNode(pack, 'paragraph-001', changes),
        throwsFormatException,
      );
    }
    expect(
      () => editTextbookCourseNode(
        pack,
        'recognition-001',
        {'requirement': 'dictation'},
      ),
      throwsFormatException,
    );
    expect(
      () => editTextbookCourseNode(
        pack,
        pack.edition.id,
        {'pdfSha256': List.filled(64, 'b').join()},
      ),
      throwsFormatException,
    );
  });

  test('正文缩短使背诵范围越界时拒绝，不截断或悄悄移动范围', () {
    final pack = TextbookCoursePack.fromJson(courseFixture());
    expect(
      () => editTextbookCourseNode(pack, 'paragraph-001', {
        'text': '星',
        'pinyin': ['xīng'],
      }),
      throwsFormatException,
    );
    expect(pack.lessons.single.recitations.single.ranges.single.end, 2);
  });

  test('词语要求、习题参考答案、来源页及背诵范围可修改并严格校验', () {
    var pack = TextbookCoursePack.fromJson(courseFixture(reviewed: true));
    pack =
        editTextbookCourseNode(pack, 'word-001', {'requirement': 'dictation'});
    expect(pack.lessons.single.words.single.requirement, 'dictation');
    pack = editTextbookCourseNode(pack, 'exercise-001', {
      'prompt': '说说你看到的星月。',
      'answerType': 'reference',
      'answers': ['合理描述即可'],
      'answerOrigin': 'reviewerReference',
      'answerSources': <Map<String, dynamic>>[],
    });
    expect(pack.lessons.single.exercises.single.answers, ['合理描述即可']);
    expect(
      () => editTextbookCourseNode(
        pack,
        'exercise-001',
        {'answerType': 'exact'},
      ),
      throwsFormatException,
    );
    pack = editTextbookCourseNode(pack, 'recitation-001', {
      'ranges': [
        {
          'paragraphId': 'paragraph-001',
          'start': 1,
          'end': 2,
          'textSha256': textbookTextDigest('𠀀'),
        },
      ],
      'sources': [courseFixtureSource(3)],
    });
    expect(pack.lessons.single.recitations.single.ranges.single.start, 1);
    expect(pack.lessons.single.recitations.single.sources.single.pdfPage, 3);
  });

  test('范围核对不自动推断空内容；不变内容不撤销审核或增加修订', () {
    final pack = TextbookCoursePack.fromJson(courseFixture(reviewed: true));
    expect(
      identical(
        editTextbookCourseNode(pack, 'paragraph-001', {'text': '星𠀀，月。'}),
        pack,
      ),
      isTrue,
    );
    expect(
      identical(
        updateTextbookCourseCoverage(
          pack,
          'lesson-001',
          pack.lessons.single.coverage,
        ),
        pack,
      ),
      isTrue,
    );
    final changed = updateTextbookCourseCoverage(
      pack,
      'lesson-001',
      {...pack.lessons.single.coverage, 'words': TextbookCoverage.pending},
    );
    expect(changed.contentRevision, pack.contentRevision + 1);
    expect(changed.lessons.single.isApproved, isFalse);
    expect(changed.lessons.single.coverage['words'], TextbookCoverage.pending);
    expect(
      () => updateTextbookCourseCoverage(pack, 'lesson-001', {
        ...pack.lessons.single.coverage,
        'words': TextbookCoverage.notApplicable,
      }),
      throwsFormatException,
    );
  });
}
