import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';

import '../../helpers/textbook_fixture.dart';

void main() {
  late Directory root;
  late String id;
  late Textbook book;
  late TextbookFileService service;
  late Directory cacheDirectory;
  late Directory audioDirectory;
  late File pdf;
  late File toc;
  late File page;
  late File cover;
  late File course;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('poemath-usage');
    id = List.filled(64, 'a').join();
    book = textbookFixture(id: id, fileSize: 5);
    service = TextbookFileService(directoryProvider: () async => root);

    final textbooks = '${root.path}/textbooks';
    cacheDirectory = Directory('$textbooks/cache/$id');
    audioDirectory = Directory('${root.path}/textbook-audio/$id');
    await cacheDirectory.create(recursive: true);
    await audioDirectory.create(recursive: true);
    pdf = await File('$textbooks/$id.pdf').writeAsBytes([1, 2, 3, 4, 5]);
    toc = await File('${cacheDirectory.path}/toc.json').writeAsString('{}');
    page = await File('${cacheDirectory.path}/page-1.json')
        .writeAsString('{"a":1}');
    cover =
        await File('${cacheDirectory.path}/cover-v1.png').writeAsBytes([0, 0, 0]);
    await File('${audioDirectory.path}/key.mp3').writeAsBytes([1, 2, 3, 4]);
    // 元数据不计入音频占用。
    await File('${audioDirectory.path}/key.mp3.json').writeAsString('{}');
    await Directory('$textbooks/courses').create(recursive: true);
    course = await File('$textbooks/courses/$id.json')
        .writeAsString('{"course":1}');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('统计原书、封面、目录提取、朗读音频与课程数据', () async {
    final usage = await service.storageUsage(book);
    expect(usage.pdfBytes, 5);
    expect(usage.coverBytes, 3);
    expect(usage.contentFiles, 2);
    expect(usage.contentBytes, '{}'.length + '{"a":1}'.length);
    expect(usage.audioFiles, 1);
    expect(usage.audioBytes, 4);
    expect(usage.courseBytes, '{"course":1}'.length);
    expect(usage.hasDerived, isTrue);
    expect(
      usage.derivedBytes,
      usage.coverBytes + usage.contentBytes + usage.audioBytes,
    );
  });

  test('清理提取内容保留封面，清理封面不影响原书与课程', () async {
    await service.clearExtractedContent(book);
    expect(await toc.exists(), isFalse);
    expect(await page.exists(), isFalse);
    expect(await cover.exists(), isTrue, reason: '封面重新生成更贵，应保留');

    await service.clearCover(book);
    expect(await cover.exists(), isFalse);
    expect(await pdf.exists(), isTrue);
    expect(await course.exists(), isTrue);
  });

  test('清理朗读音频与全部派生数据不动原书和课程', () async {
    await service.clearNarration(book);
    expect(await audioDirectory.exists(), isFalse);

    await service.clearDerived(book);
    expect(await cacheDirectory.exists(), isFalse);
    expect(await pdf.exists(), isTrue);
    expect(await course.exists(), isTrue);
    final usage = await service.storageUsage(book);
    expect(usage.hasDerived, isFalse);
    expect(usage.pdfBytes, 5);
    expect(usage.courseBytes, greaterThan(0));
  });

  test('未导入的书籍统计为空', () async {
    final other = textbookFixture(id: List.filled(64, 'b').join());
    final usage = await service.storageUsage(other);
    expect(usage.pdfBytes, 0);
    expect(usage.hasDerived, isFalse);
  });
}
