import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:hive/hive.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  late Directory directory;
  late File source;
  late TextbookFileService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_files_');
    source = await File('${directory.path}/input.pdf')
        .writeAsBytes('%PDF-1.4\nlocal sample\n%%EOF'.codeUnits);
    service = TextbookFileService(
      directoryProvider: () async => directory,
      validator: (_) async => 3,
    );
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('流式导入按真实哈希发布，取消/失败不发布半份文件', () async {
    final progress = <int>[];
    final imported = await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
      onProgress: (copied, _) => progress.add(copied),
    );
    final bytes = await source.readAsBytes();
    expect(imported.sha256, sha256.convert(bytes).toString());
    expect(imported.pageCount, 3);
    expect(imported.size, bytes.length);
    expect(
      await File('${directory.path}/textbooks/${imported.sha256}.pdf')
          .readAsBytes(),
      bytes,
    );
    expect(progress.last, bytes.length);
    expect(
      Directory('${directory.path}/textbooks')
          .listSync()
          .map((file) => file.path),
      ['${directory.path}/textbooks/${imported.sha256}.pdf'],
    );
  });

  test('非 PDF 头和超限文件拒绝，原文件保持完整', () async {
    final invalid =
        await File('${directory.path}/invalid.pdf').writeAsString('not a PDF');
    await expectLater(
      service.importPdf(
        sourcePath: invalid.path,
        token: TextbookImportToken(),
      ),
      throwsA(isA<TextbookFileException>()),
    );
    final limited = TextbookFileService(
      directoryProvider: () async => directory,
      validator: (_) async => 3,
      maxFileSize: 8,
    );
    await expectLater(
      limited.importPdf(
        sourcePath: source.path,
        token: TextbookImportToken(),
      ),
      throwsA(isA<TextbookFileException>()),
    );
    expect(await invalid.readAsString(), 'not a PDF');
    expect(Directory('${directory.path}/textbooks').listSync(), isEmpty);
  });

  test('复制阶段取消，临时文件清理且后续可重试', () async {
    final token = TextbookImportToken();
    await expectLater(
      service.importPdf(
        sourcePath: source.path,
        token: token,
        onProgress: (_, __) => token.cancel(),
      ),
      throwsA(isA<TextbookImportCancelled>()),
    );
    expect(Directory('${directory.path}/textbooks').listSync(), isEmpty);
    final next = await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
    );
    expect(next.pageCount, 3);
  });

  test('验证期间取消不会替换已有可读文件', () async {
    final first = await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
    );
    final entered = Completer<void>();
    final release = Completer<int>();
    final waiting = TextbookFileService(
      directoryProvider: () async => directory,
      validator: (_) {
        entered.complete();
        return release.future;
      },
    );
    final token = TextbookImportToken();
    final pending = waiting.importPdf(sourcePath: source.path, token: token);
    final assertion =
        expectLater(pending, throwsA(isA<TextbookImportCancelled>()));
    await entered.future;
    token.cancel();
    release.complete(3);
    await assertion;
    expect(
      await File('${directory.path}/textbooks/${first.sha256}.pdf')
          .readAsBytes(),
      await source.readAsBytes(),
    );
    expect(Directory('${directory.path}/textbooks').listSync().length, 1);
  });

  test('PDF 解析失败或页数无效拒绝，错误不污染重试链', () async {
    var attempts = 0;
    final failing = TextbookFileService(
      directoryProvider: () async => directory,
      validator: (_) async {
        attempts++;
        if (attempts == 1) throw const FormatException('broken');
        return 3;
      },
    );
    await expectLater(
      failing.importPdf(
        sourcePath: source.path,
        token: TextbookImportToken(),
      ),
      throwsA(isA<TextbookFileException>()),
    );
    expect(Directory('${directory.path}/textbooks').listSync(), isEmpty);
    expect(
      (await failing.importPdf(
        sourcePath: source.path,
        token: TextbookImportToken(),
      ))
          .pageCount,
      3,
    );
    final empty = TextbookFileService(
      directoryProvider: () async => directory,
      validator: (_) async => 0,
    );
    await expectLater(
      empty.importPdf(sourcePath: source.path, token: TextbookImportToken()),
      throwsA(isA<TextbookFileException>()),
    );
    expect(Directory('${directory.path}/textbooks').listSync().length, 1);
  });

  test('移除 PDF 后书目与页码保留，同文件重导恢复，不同哈希独立', () async {
    Hive.init(directory.path);
    final repo =
        TextbookRepository(box: await Hive.openBox<dynamic>('textbook'));
    final imported = await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
    );
    final book = Textbook(
      pdfSha256: imported.sha256,
      title: '原登记',
      grade: 1,
      semester: '上',
      publisher: '',
      editionNote: '',
      originalFileName: 'input.pdf',
      pageCount: imported.pageCount,
      fileSize: imported.size,
      importedAt: DateTime.utc(2026),
    );
    await repo.addIfAbsent(book);
    await repo.savePage('child', book, 2);
    final cache = service.contentCache(book);
    await cache.rememberText(1, '可复用的书籍内容');
    await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
    );
    expect(
      await TextbookFileService(directoryProvider: () async => directory)
          .contentCache(book)
          .pageText(1, () => throw StateError('同SHA不应丢缓存')),
      '可复用的书籍内容',
    );
    await service.removePdf(book.pdfSha256);
    expect(
      await Directory('${directory.path}/textbooks/cache/${book.pdfSha256}')
          .exists(),
      isFalse,
    );
    expect(await service.installedPath(book), isNull);
    expect(repo.reading('child', book.pdfSha256).page, 2);
    expect(repo.find(book.pdfSha256)?.title, '原登记');
    final reinstall = await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
    );
    expect(reinstall.sha256, book.pdfSha256);
    expect(await cache.pageText(1, () async => '重导后重新提取'), '重导后重新提取');
    await TextbookFileService(directoryProvider: () async => directory)
        .removePdf(book.pdfSha256);
    expect(
      await Directory('${directory.path}/textbooks/cache/${book.pdfSha256}')
          .exists(),
      isFalse,
    );
    await service.importPdf(
      sourcePath: source.path,
      token: TextbookImportToken(),
    );
    expect(
      await service.installedPath(book),
      '${directory.path}/textbooks/${book.pdfSha256}.pdf',
    );
    final other = textbookFixture(id: List.filled(64, 'b').join());
    expect(repo.reading('child', other.pdfSha256).page, 1);
  });

  test('路径只允许 SHA，无法删除任意来源文件', () async {
    await expectLater(
      service.removePdf('../input'),
      throwsA(isA<TextbookFileException>()),
    );
    expect(await source.exists(), isTrue);
  });

  test('仅清理所选 Android picker 副本，保留来源、其他副本及越界符号链接目标', () async {
    final cache = await Directory('${directory.path}/file_picker')
        .create(recursive: true);
    final selected =
        await File('${cache.path}/selected.pdf').writeAsString('copy');
    final other = await File('${cache.path}/other.pdf').writeAsString('other');
    final link = await Link('${cache.path}/linked.pdf').create(source.path);
    final pickerFiles = TextbookFileService(
      directoryProvider: () async => directory,
      pickerCacheDirectoryProvider: () async => cache,
      validator: (_) async => 3,
    );
    await pickerFiles.discardPickerCopy(source.path);
    await pickerFiles.discardPickerCopy(link.path);
    await pickerFiles.discardPickerCopy(selected.path);
    expect(await selected.exists(), isFalse);
    expect(await other.exists(), isTrue);
    expect(await source.exists(), isTrue);
    expect(await link.exists(), isTrue);
  });
}
