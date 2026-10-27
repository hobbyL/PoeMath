import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';

import '../../helpers/textbook_course_fixture.dart';

void main() {
  late Directory directory;
  late TextbookCourseRepository repository;
  final book = courseFixtureBook();
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('poemath-course-repo-');
    repository =
        TextbookCourseRepository(directoryProvider: () async => directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('真实草稿导入、审核、关闭重建完整恢复，移除PDF保留人工成果', () async {
    final raw = courseFixture();
    final source = File('${directory.path}/input.json');
    await source.writeAsString(jsonEncode(raw));
    final imported = await repository.readDraft(book, source.path);
    await repository.importDraft(book, imported);
    final reviewed = TextbookCoursePack.fromJson(
      reviewTextbookCourse(
        input: imported.toJson(),
        nodeId: 'paragraph-001',
        reviewer: '测试家长',
        decision: 'approved',
        checks: ['sourcePages', 'content', 'pinyin'],
        notes: '逐字与原书核对',
        at: DateTime.utc(2026, 10, 23),
      ),
    );
    await repository.save(book, reviewed, previous: imported);
    final reopened =
        TextbookCourseRepository(directoryProvider: () async => directory);
    expect((await reopened.load(book))!.toJson(), reviewed.toJson());
    await File('${directory.path}/textbooks/${book.pdfSha256}.pdf')
        .writeAsString('test only');
    await TextbookFileService(directoryProvider: () async => directory)
        .removePdf(book.pdfSha256);
    expect((await reopened.load(book))!.toJson(), reviewed.toJson());
    expect(
      await File('${directory.path}/textbooks/${book.pdfSha256}.pdf').exists(),
      isFalse,
    );
    expect(
      await directory
          .list(recursive: true)
          .where((file) => file.path.contains('.course-'))
          .toList(),
      isEmpty,
    );
  });

  test('删除课程数据后读取为空，原书与目录不受影响且可重复删除', () async {
    await repository.importDraft(
      book,
      TextbookCoursePack.fromJson(courseFixture()),
    );
    final pdf = File('${directory.path}/textbooks/${book.pdfSha256}.pdf');
    await pdf.writeAsString('test only');

    await repository.clear(book);

    expect(await repository.load(book), isNull);
    expect(await repository.loadDocument(book), isNull);
    expect(await pdf.exists(), isTrue);
    expect(Directory('${directory.path}/textbooks').existsSync(), isTrue);

    await repository.clear(book);
    expect(await repository.load(book), isNull);
  });

  test('册次/原书身份不匹配拒绝导入，之前草稿保持完整', () async {
    final pack = TextbookCoursePack.fromJson(courseFixture());
    await repository.importDraft(book, pack);
    for (final entry in {
      'pdfSha256': List.filled(64, 'b').join(),
      'pageCount': 4,
      'fileSize': 2000,
      'grade': 2,
      'semester': '上',
    }.entries) {
      final raw = courseFixture();
      (raw['edition'] as Map<String, dynamic>)[entry.key] = entry.value;
      await expectLater(
        repository.importDraft(book, TextbookCoursePack.fromJson(raw)),
        throwsFormatException,
      );
    }
    expect((await repository.load(book))!.toJson(), pack.toJson());
  });

  test('旧审核页不能覆盖重新导入的数据，错误不毒化后续队列', () async {
    final previous = TextbookCoursePack.fromJson(courseFixture());
    await repository.importDraft(book, previous);
    final updated = editTextbookCourseNode(
      previous,
      'word-001',
      {'requirement': 'dictation'},
    );
    await repository.importDraft(book, updated);
    await expectLater(
      repository.save(book, previous, previous: previous),
      throwsFormatException,
    );
    final next =
        editTextbookCourseNode(updated, 'word-001', {'requirement': 'reading'});
    await repository.save(book, next, previous: updated);
    expect((await repository.load(book))!.toJson(), next.toJson());
  });

  test('损坏文件读取失败且不覆盖，可显式重新导入恢复', () async {
    final pack = TextbookCoursePack.fromJson(courseFixture());
    await repository.importDraft(book, pack);
    final file =
        File('${directory.path}/textbooks/courses/${book.pdfSha256}.json');
    await file.writeAsString('{broken');
    await expectLater(repository.load(book), throwsFormatException);
    expect(await file.readAsString(), '{broken');
    await repository.importDraft(book, pack);
    expect((await repository.load(book))!.toJson(), pack.toJson());
  });

  test('流式文件大小限制拒绝过大输入', () async {
    final file = File('${directory.path}/large.json');
    final writer = file.openWrite();
    for (var i = 0; i < 17; i++) {
      writer.add(List.filled(1024 * 1024, 32));
    }
    await writer.close();
    await expectLater(
      repository.readDraft(book, file.path),
      throwsFormatException,
    );
    expect(await repository.load(book), isNull);
  });

  test('真实写入失败保留旧草稿，恢复存储后同一仓库可重试', () async {
    var blocked = false;
    final blocker = File('${directory.path}/not-a-directory');
    await blocker.writeAsString('blocker');
    final repo = TextbookCourseRepository(
        directoryProvider: () async =>
            blocked ? Directory(blocker.path) : directory,);
    final previous = TextbookCoursePack.fromJson(courseFixture());
    await repo.importDraft(book, previous);
    final edited = editTextbookCourseNode(
        previous, 'word-001', {'requirement': 'dictation'},);
    blocked = true;
    await expectLater(
        repo.importDraft(book, edited), throwsA(isA<FileSystemException>()),);
    blocked = false;
    expect((await repo.load(book))!.toJson(), previous.toJson());
    await repo.save(book, edited, previous: previous);
    expect((await repo.load(book))!.toJson(), edited.toJson());
  });
}
