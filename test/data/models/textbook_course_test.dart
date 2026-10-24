import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';

import '../../helpers/textbook_course_fixture.dart';
import '../../../tools/textbook_importer/course.dart' as tool;

Map<String, dynamic> lesson(Map<String, dynamic> pack) =>
    (pack['lessons'] as List).single as Map<String, dynamic>;

void main() {
  test('实际建稿和审核产物完整往返，Unicode注音与范围不按UTF16误计', () {
    final produced = courseFixture(reviewed: true, permitted: true);
    final pack = TextbookCoursePack.forPublication(produced);
    expect(pack.toJson(), produced);
    expect(pack.isPublishable, isTrue);
    final first = pack.lessons.single;
    expect(first.paragraphs.single.text.runes.length, 5);
    expect(first.paragraphs.single.pinyin, ['xīng', 'hē', '，', 'yuè', '。']);
    expect(first.recognitionCharacters.single.text, '𠀀');
    expect(first.recitations.single.ranges.single.end, 2);
    expect(first.exercises.single.answerType, TextbookAnswerType.parentCheck);
    expect(
      pack.targetKey(first.recitations.single.id),
      '${pack.edition.id}/recitation-001',
    );
    expect(pack.nodes.map((n) => n.id).toList(), [
      pack.edition.id,
      'unit-001',
      'lesson-001',
      'paragraph-001',
      'recognition-001',
      'writing-001',
      'word-001',
      'recitation-001',
      'exercise-001',
    ]);
  });

  test('已核内容仍因未知许可阻断发布，草稿与正式加载入口分开', () {
    final produced = courseFixture(reviewed: true);
    final pack = TextbookCoursePack.fromJson(produced);
    expect(
      pack.publicationIssues.map((e) => e.path).toList(),
      [r'$.permissions.content', r'$.permissions.applicationUse'],
    );
    expect(
      () => TextbookCoursePack.forPublication(produced),
      throwsFormatException,
    );
  });

  test('仅填审核状态或核对项不齐不能通过', () {
    final raw = courseFixture();
    (raw['edition'] as Map)['review'] = {
      ...tool.newTextbookReview(),
      'status': 'approved',
    };
    expect(() => TextbookCoursePack.fromJson(raw), throwsFormatException);
    expect(
      () => tool.reviewTextbookCourse(
        input: courseFixture(),
        nodeId: 'paragraph-001',
        reviewer: '审核人',
        decision: 'approved',
        checks: ['content'],
        notes: '缺页码和注音检查',
      ),
      throwsFormatException,
    );
  });

  test('正文/注音/来源/答案变化使原审核失效；键顺序不影响摘要', () {
    final raw = courseFixture(reviewed: true, permitted: true);
    final rawLesson = lesson(raw);
    final word = (rawLesson['words'] as List).single as Map<String, dynamic>;
    final original = textbookContentDigest(word);
    expect(
      textbookContentDigest(
        {for (final key in word.keys.toList().reversed) key: word[key]},
      ),
      original,
    );
    word['text'] = '星光';
    word['pinyin'] = ['xīng', 'guāng'];
    final pack = TextbookCoursePack.fromJson(raw);
    expect(pack.lessons.single.words.single.isApproved, isFalse);
    expect(pack.lessons.single.isApproved, isFalse);
    expect(
      pack.publicationIssues.map((e) => e.path),
      containsAll([
        r'$.review',
        r'$.lessons[0].review',
        r'$.lessons[0].words[0].review',
      ]),
    );
    final copy = pack.toJson();
    lesson(copy)['title'] = '外部修改';
    expect(pack.lessons.single.title, '星月测试');
    expect(pack.toJson(), raw);
  });

  final invalidCases = <String, void Function(Map<String, dynamic>)>{
    '重复目标ID': (p) =>
        ((lesson(p)['words'] as List).single as Map)['id'] = 'paragraph-001',
    '跨课段落引用': (p) =>
        ((((lesson(p)['recitations'] as List).single as Map)['ranges'] as List)
            .single as Map)['paragraphId'] = 'other-lesson-paragraph',
    '物理页码越界': (p) =>
        (((lesson(p)['sources'] as List).single) as Map)['pdfPage'] = 4,
    '非整数页码': (p) =>
        (((lesson(p)['sources'] as List).single) as Map)['pdfPage'] = 2.0,
    '漏掉字段': (p) => lesson(p).remove('kind'),
    '未知字段': (p) => lesson(p)['isRequired'] = true,
    '拼音错位': (p) =>
        ((lesson(p)['paragraphs'] as List).single as Map)['pinyin'] = ['xīng'],
    '标点未占位': (p) => ((lesson(p)['paragraphs'] as List).single
        as Map)['pinyin'] = ['xīng', 'hē', 'comma', 'yuè', '。'],
    '拼音字形编码损坏': (p) => ((lesson(p)['paragraphs'] as List).single
        as Map)['pinyin'] = ['chOn', 'hē', '，', 'yuè', '。'],
    '字词要求混用': (p) =>
        ((lesson(p)['words'] as List).single as Map)['requirement'] = 'writing',
    '认字混入词语': (p) => ((lesson(p)['recognitionCharacters'] as List).single
        as Map)['text'] = '星月',
    '背诵空区间': (p) =>
        ((((lesson(p)['recitations'] as List).single as Map)['ranges'] as List)
            .single as Map)['end'] = 0,
    '背诵区间越界': (p) =>
        ((((lesson(p)['recitations'] as List).single as Map)['ranges'] as List)
            .single as Map)['end'] = 6,
    '正文改后背诵范围未复核': (p) =>
        ((lesson(p)['paragraphs'] as List).single as Map)['text'] = '月𠀀，月。',
    '重复背诵区间': (p) {
      final ranges =
          ((lesson(p)['recitations'] as List).single as Map)['ranges'] as List;
      ranges.add(jsonDecode(jsonEncode(ranges.single)));
    },
    '单元引用缺失': (p) =>
        ((p['units'] as List).single as Map)['lessonIds'] = ['missing'],
    '单元课目重复': (p) => ((p['units'] as List).single as Map)['lessonIds'] = [
          'lesson-001',
          'lesson-001',
        ],
    '无此要求却有目标': (p) =>
        (lesson(p)['coverage'] as Map)['words'] = 'notApplicable',
    '完整要求却是空表': (p) => lesson(p)['words'] = <Object?>[],
    '伪造答案类型': (p) => ((lesson(p)['exercises'] as List).single
        as Map)['answerType'] = 'aiGuess',
    '参考答案冒充唯一标准': (p) {
      final exercise = (lesson(p)['exercises'] as List).single as Map;
      exercise['answerType'] = 'exact';
      exercise['answers'] = ['星'];
      exercise['answerOrigin'] = 'reviewerReference';
    },
  };
  for (final entry in invalidCases.entries) {
    test('拒绝${entry.key}', () {
      final raw = courseFixture();
      entry.value(raw);
      expect(() => TextbookCoursePack.fromJson(raw), throwsFormatException);
    });
  }

  test('无此学习要求须显式核对，未整理与没有要求不能混为一谈', () {
    final raw = courseFixture();
    final first = lesson(raw);
    first['words'] = <Object?>[];
    (first['coverage'] as Map)['words'] = 'notApplicable';
    (first['coverage'] as Map)['writingCharacters'] = 'pending';
    final pack = TextbookCoursePack.fromJson(raw);
    expect(
      pack.lessons.single.coverage['words'],
      TextbookCoverage.notApplicable,
    );
    expect(
      pack.publicationIssues
          .where((e) => e.code == 'coverage')
          .map((e) => e.path),
      [r'$.lessons[0].coverage.writingCharacters'],
    );
  });

  test('整包不能提前批准，批准后逐项否决清除整包声明', () {
    expect(
      () => tool.reviewTextbookCourse(
        input: courseFixture(),
        nodeId: '@pack',
        reviewer: '审核人',
        decision: 'approved',
        checks: ['coverage', 'content'],
        notes: '未核对的包',
      ),
      throwsFormatException,
    );
    final raw = tool.reviewTextbookCourse(
      input: courseFixture(reviewed: true, permitted: true),
      nodeId: 'word-001',
      reviewer: '审核人',
      decision: 'rejected',
      checks: [],
      notes: '发现词语错误',
    );
    final pack = TextbookCoursePack.fromJson(raw);
    expect(pack.status, 'draft');
    expect(pack.review.status, TextbookReviewStatus.unreviewed);
    expect(
      pack.lessons.single.words.single.review.status,
      TextbookReviewStatus.rejected,
    );
    expect(pack.isPublishable, isFalse);
  });

  test('更换PDF或版次后，旧书的所有目标审核失效', () {
    for (final field in ['id', 'pdfSha256', 'fileSize']) {
      final raw = courseFixture(reviewed: true, permitted: true);
      final edition = raw['edition'] as Map;
      edition[field] = switch (field) {
        'id' => 'another-edition',
        'pdfSha256' => List.filled(64, 'b').join(),
        _ => 1235,
      };
      final pack = TextbookCoursePack.fromJson(raw);
      expect(pack.nodes.every((n) => !n.isApproved), true, reason: field);
      expect(pack.isPublishable, false);
    }
  });

  test('原书标准答案、人工参考与无答案分别保留来源语义', () {
    for (final type in TextbookAnswerType.values) {
      final raw = courseFixture();
      final exercise = (lesson(raw)['exercises'] as List).single as Map;
      exercise['answerType'] = type.name;
      if (type == TextbookAnswerType.exact) {
        exercise['answers'] = ['月'];
        exercise['answerOrigin'] = 'textbook';
        exercise['answerSources'] = [courseFixtureSource(3)];
      } else if (type == TextbookAnswerType.reference) {
        exercise['answers'] = ['可以从星或月展开描述'];
        exercise['answerOrigin'] = 'reviewerReference';
      }
      final decoded =
          TextbookCoursePack.fromJson(raw).lessons.single.exercises.single;
      expect(decoded.answerType, type);
      expect(decoded.answers, exercise['answers']);
      expect(
        decoded.answerSources.map((s) => s.pdfPage),
        type == TextbookAnswerType.exact ? [3] : <int>[],
      );
      expect(decoded.answerOrigin, exercise['answerOrigin']);
    }
  });

  test('完整覆盖须核对总课目数，字词缺注音不能发布', () {
    final raw = courseFixture();
    raw['coverage'] = 'complete';
    raw['expectedLessonCount'] = 2;
    ((lesson(raw)['words'] as List).single as Map)['pinyin'] = null;
    final issues = TextbookCoursePack.fromJson(raw).publicationIssues;
    expect(
      issues.where((i) => i.code == 'coverage').map((i) => i.path),
      [r'$.expectedLessonCount'],
    );
    expect(
      issues.where((i) => i.code == 'pinyin').map((i) => i.path),
      [r'$.lessons[0].words[0]'],
    );
  });
}
