import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';

import '../../tools/textbook_importer/course.dart' as tool;

String get courseFixtureHash => List.filled(64, 'a').join();

Textbook courseFixtureBook() => Textbook(
      pdfSha256: courseFixtureHash,
      title: '自有合成教材',
      grade: 1,
      semester: '下',
      publisher: '合成出版社',
      editionNote: '自有测试版',
      originalFileName: 'sample.pdf',
      pageCount: 3,
      fileSize: 1234,
      importedAt: DateTime.utc(2026, 10, 23),
    );

Map<String, dynamic> courseFixtureCatalog() => {
      'schemaVersion': 1,
      'books': [
        {
          'sha256': courseFixtureHash,
          'bytes': 1234,
          'pageCount': 3,
          'title': '自有合成教材',
          'grade': 1,
          'semester': '下',
          'publisher': '合成出版社',
          'editionNotes': '自有测试内容，没有真实教材正文',
          'editionLabel': '自有测试版',
          'sourceRepository': 'example/textbook',
          'sourceCommit': List.filled(40, 'b').join(),
          'sourcePath': 'sample.pdf',
          'downloadUrl':
              'https://raw.githubusercontent.com/example/textbook/${List.filled(40, 'b').join()}/sample.pdf',
          'evidencePdfPages': [1],
          'checkedAt': '2026-10-23T00:00:00Z',
        },
      ],
    };

Map<String, dynamic> courseFixtureExtraction() => {
      'schemaVersion': 1,
      'status': 'draft',
      'contentReviewStatus': 'unreviewed',
      'source': {'sha256': courseFixtureHash, 'fileSizeBytes': 1234},
      'qualitySummary': {'pageCount': 3, 'pagesNeedingReview': <int>[]},
      'pages': [
        for (var i = 1; i <= 3; i++)
          {
            'pdfPageNumber': i,
            'text': '自有测试第$i页',
            'extractionStatus': 'text_extracted',
          },
      ],
    };

Map<String, dynamic> courseFixtureSource(int page) => {
      'pdfPage': page,
      'printedPage': '${page - 1}',
      'extractionStatus': 'manual',
    };

Map<String, dynamic> courseFixtureText(
  String id,
  String text,
  List<String>? pinyin,
) =>
    {
      'id': id,
      'text': text,
      'pinyin': pinyin,
      'sources': [courseFixtureSource(2)],
      'review': tool.newTextbookReview(),
    };

/// 所有文字均为自有合成材料；同时覆盖补充平面汉字、标点和明确子段范围。
Map<String, dynamic> courseFixture({
  bool reviewed = false,
  bool permitted = false,
}) {
  var pack = tool.buildTextbookCourseDraft(
    extraction: courseFixtureExtraction(),
    catalog: courseFixtureCatalog(),
  );
  pack['units'] = [
    {
      'id': 'unit-001',
      'title': '合成单元',
      'sources': [courseFixtureSource(1)],
      'review': tool.newTextbookReview(),
      'lessonIds': ['lesson-001'],
    },
  ];
  pack['lessons'] = [
    {
      'id': 'lesson-001',
      'unitId': 'unit-001',
      'title': '星月测试',
      'kind': 'text',
      'lessonNumber': 1,
      'sources': [courseFixtureSource(2)],
      'review': tool.newTextbookReview(),
      'coverage': {
        for (final category in TextbookCoursePack.categories)
          category: 'complete',
      },
      'paragraphs': [
        courseFixtureText(
          'paragraph-001',
          '星𠀀，月。',
          ['xīng', 'hē', '，', 'yuè', '。'],
        ),
      ],
      'recognitionCharacters': [
        {
          ...courseFixtureText('recognition-001', '𠀀', ['hē']),
          'requirement': 'recognition',
        }
      ],
      'writingCharacters': [
        {
          ...courseFixtureText('writing-001', '星', ['xīng']),
          'requirement': 'writing',
        }
      ],
      'words': [
        {
          ...courseFixtureText('word-001', '星月', ['xīng', 'yuè']),
          'requirement': 'reading',
        }
      ],
      'recitations': [
        {
          'id': 'recitation-001',
          'instruction': '只背测试句的前两个字。',
          'ranges': [
            {
              'paragraphId': 'paragraph-001',
              'start': 0,
              'end': 2,
              'textSha256': textbookTextDigest('星𠀀'),
            }
          ],
          'sources': [courseFixtureSource(3)],
          'review': tool.newTextbookReview(),
        },
      ],
      'exercises': [
        {
          'id': 'exercise-001',
          'prompt': '请说出测试句中的天体。',
          'origin': 'textbook',
          'answerType': 'parentCheck',
          'answers': <String>[],
          'answerOrigin': 'none',
          'answerSources': <Object?>[],
          'sources': [courseFixtureSource(3)],
          'review': tool.newTextbookReview(),
        },
      ],
    },
  ];
  if (permitted) {
    pack['permissions'] = {
      'content': {'status': 'permitted', 'evidence': '自有合成测试内容'},
      'applicationUse': {'status': 'permitted', 'evidence': '自有合成测试用途'},
    };
  }
  if (reviewed) {
    final nodes = TextbookCoursePack.fromJson(pack).nodes.toList();
    for (final node in nodes) {
      pack = tool.reviewTextbookCourse(
        input: pack,
        nodeId: node.id,
        reviewer: '合成测试审核者',
        decision: 'approved',
        checks: node.requiredChecks,
        notes: '对照自有测试样本核对',
        at: DateTime.utc(2026, 10, 23),
      );
    }
    pack = tool.reviewTextbookCourse(
      input: pack,
      nodeId: '@pack',
      reviewer: '合成测试审核者',
      decision: 'approved',
      checks: ['coverage', 'content'],
      notes: '已核对本样例的全部目标',
      at: DateTime.utc(2026, 10, 23),
    );
  }
  return TextbookCoursePack.fromJson(pack).toJson();
}
