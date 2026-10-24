import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';

import '../../tools/textbook_importer/course.dart' as tool;
import '../helpers/textbook_course_fixture.dart';

void main() {
  late Directory temporary;
  setUp(
    () async => temporary =
        await Directory.systemTemp.createTemp('textbook-course-test-'),
  );
  tearDown(() async => temporary.delete(recursive: true));
  Future<String> write(String name, Object value) async {
    final file = File('${temporary.path}/$name');
    await file.writeAsString(jsonEncode(value));
    return file.path;
  }

  test('文档合成样例与真实建稿器产物一致', () async {
    final raw = jsonDecode(
      await File('tools/textbook_importer/examples/synthetic-course.json')
          .readAsString(),
    ) as Map<String, dynamic>;
    expect(raw, courseFixture());
    expect(TextbookCoursePack.fromJson(raw).toJson(), raw);
  });

  test('CLI实际建稿、校验、工作表，未知许可不能导出且不会留下半份文件', () async {
    final extraction = await write('draft.json', courseFixtureExtraction());
    final catalog = await write('catalog.json', courseFixtureCatalog());
    final output = '${temporary.path}/course.json';
    final out = StringBuffer();
    final err = StringBuffer();
    expect(
      await tool.runTextbookCourseCommand(
        [
          'init',
          '--draft',
          extraction,
          '--catalog',
          catalog,
          '--output',
          output,
        ],
        output: out,
        errors: err,
      ),
      0,
    );
    final json =
        jsonDecode(await File(output).readAsString()) as Map<String, dynamic>;
    final pack = TextbookCoursePack.fromJson(json);
    expect(pack.edition.pdfSha256, courseFixtureHash);
    expect(pack.units, isEmpty);
    expect(pack.status, 'draft');
    expect(pack.edition.review.status, TextbookReviewStatus.unreviewed);
    final validation = StringBuffer();
    expect(
      await tool.runTextbookCourseCommand(
        ['validate', '--input', output],
        output: validation,
        errors: err,
      ),
      0,
    );
    final report = jsonDecode(validation.toString()) as Map;
    expect(report['schemaValid'], true);
    expect(report['publishable'], false);
    expect(
      await tool.runTextbookCourseCommand(
        ['validate', '--input', output, '--for-publish'],
        output: StringBuffer(),
        errors: err,
      ),
      2,
    );
    final exported = '${temporary.path}/exported.json';
    expect(
      await tool.runTextbookCourseCommand(
        ['export', '--input', output, '--output', exported],
        output: out,
        errors: err,
      ),
      2,
    );
    expect(await File(exported).exists(), false);
    final worksheet = '${temporary.path}/worksheet.md';
    expect(
      await tool.runTextbookCourseCommand(
        [
          'worksheet',
          '--input',
          output,
          '--draft',
          extraction,
          '--output',
          worksheet,
        ],
        output: out,
        errors: err,
      ),
      0,
    );
    expect(await File(worksheet).readAsString(), contains('    自有测试第1页'));
  });

  test('实际已核自有内容可导出，消费者接收全部字段', () async {
    final raw = courseFixture(reviewed: true, permitted: true);
    final input = await write('reviewed.json', raw);
    final exported = '${temporary.path}/published.json';
    expect(
      await tool.runTextbookCourseCommand(
        ['export', '--input', input, '--output', exported],
        output: StringBuffer(),
        errors: StringBuffer(),
      ),
      0,
    );
    final decoded =
        jsonDecode(await File(exported).readAsString()) as Map<String, dynamic>;
    expect(TextbookCoursePack.forPublication(decoded).toJson(), raw);
  });

  test('输出保护涵盖现有文件、输入覆盖、符号链接及硬链接', () async {
    final raw = courseFixture(reviewed: true, permitted: true);
    final input = await write('input.json', raw);
    final existing = await write('existing.json', {'keep': true});
    for (final target in [input, existing]) {
      final before = await File(target).readAsString();
      expect(
        await tool.runTextbookCourseCommand(
          ['export', '--input', input, '--output', target],
          output: StringBuffer(),
          errors: StringBuffer(),
        ),
        2,
      );
      expect(await File(target).readAsString(), before);
    }
    final link = Link('${temporary.path}/input-link.json');
    await link.create(input);
    final hardLink = '${temporary.path}/input-hardlink.json';
    final linked = await Process.run('ln', [input, hardLink]);
    expect(linked.exitCode, 0);
    for (final target in [input, link.path, hardLink]) {
      expect(
        await tool.runTextbookCourseCommand(
          ['export', '--input', input, '--output', target, '--force'],
          output: StringBuffer(),
          errors: StringBuffer(),
        ),
        2,
      );
      expect(jsonDecode(await File(input).readAsString()), raw);
    }
  });

  test('目录只能给出待核骨架，按原序保留课号并校验PDF身份', () {
    final toc = <String, dynamic>{
      'version': 1,
      'sha256': courseFixtureHash,
      'pageCount': 3,
      'pdfSize': 1234,
      'data': {
        'tocVersion': 1,
        'source': 'text',
        'hasText': true,
        'directoryPages': [1],
        'entries': [
          {
            'title': '第一单元',
            'isGroup': true,
            'level': 0,
            'page': null,
            'printedPage': null,
            'lessonNumber': null,
          },
          {
            'title': '测试课',
            'isGroup': false,
            'level': 1,
            'page': 2,
            'printedPage': 1,
            'lessonNumber': 1,
          },
        ],
      },
    };
    final json = tool.buildTextbookCourseDraft(
      extraction: courseFixtureExtraction(),
      catalog: courseFixtureCatalog(),
      toc: toc,
    );
    final pack = TextbookCoursePack.fromJson(json);
    expect(pack.units.single.title, '第一单元');
    expect(pack.units.single.lessonIds, ['lesson-001']);
    expect(pack.lessons.single.lessonNumber, 1);
    expect(pack.lessons.single.paragraphs, isEmpty);
    expect(
      pack.lessons.single.coverage.values.toSet(),
      {TextbookCoverage.pending},
    );
    expect(pack.lessons.single.sources.single.printedPage, '1');
    toc['sha256'] = List.filled(64, 'b').join();
    expect(
      () => tool.buildTextbookCourseDraft(
        extraction: courseFixtureExtraction(),
        catalog: courseFixtureCatalog(),
        toc: toc,
      ),
      throwsFormatException,
    );
  });

  test('抽取草稿不能缺页、错哈希或错体积', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (d) => (d['pages'] as List).removeLast(),
      (d) => ((d['pages'] as List).first as Map)['pdfPageNumber'] = 3,
      (d) => (d['source'] as Map)['fileSizeBytes'] = 2000,
      (d) => (d['source'] as Map)['sha256'] = List.filled(64, 'b').join(),
    ]) {
      final raw = courseFixtureExtraction();
      mutation(raw);
      expect(
        () => tool.buildTextbookCourseDraft(
          extraction: raw,
          catalog: courseFixtureCatalog(),
        ),
        throwsFormatException,
      );
    }
  });

  test('真实12册矩阵不将PDF核验写作课程审核，重复及错版课程包被拒绝', () async {
    final catalog = jsonDecode(
      await File('assets/data/textbook_catalog.json').readAsString(),
    ) as Map<String, dynamic>;
    final matrix = tool.buildTextbookReviewMatrix(catalog: catalog);
    final books = matrix['books'] as List;
    expect(books.length, 12);
    expect(
      books
          .map((b) => '${(b as Map)['grade']}/${b['semester']}')
          .toSet()
          .length,
      12,
    );
    expect(
      books.every((b) => (b as Map)['contentReview'] == 'notStarted'),
      true,
    );
    expect(books.every((b) => (b as Map)['publishable'] == false), true);
    expect(
      books.where((b) => (b as Map)['editionLabel'] == '2022课标修订').length,
      9,
    );
    expect(
      () => tool.buildTextbookReviewMatrix(
        catalog: catalog,
        packs: [TextbookCoursePack.fromJson(courseFixture())],
      ),
      throwsFormatException,
    );
    (catalog['books'] as List).removeLast();
    expect(
      () => tool.buildTextbookReviewMatrix(catalog: catalog),
      throwsFormatException,
    );
  });
}
