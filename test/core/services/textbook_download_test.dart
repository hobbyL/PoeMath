import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import '../../helpers/textbook_fixture.dart';

TextbookCatalogEntry entryFor(List<int> bytes, {String? sha}) =>
    TextbookCatalogEntry(
      book: Textbook(
        pdfSha256: sha ?? sha256.convert(bytes).toString(),
        title: '测试语文教材',
        grade: 3,
        semester: '上',
        publisher: '测试出版社',
        editionNote: '测试版本',
        originalFileName: 'sample.pdf',
        pageCount: 3,
        fileSize: bytes.length,
        importedAt: DateTime.utc(2026),
      ),
      downloadUrl:
          Uri.parse('https://raw.githubusercontent.com/test/books/sample.pdf'),
      sourceRepository: 'test/books',
      sourceCommit: List.filled(40, 'a').join(),
      sourcePath: 'sample.pdf',
      editionLabel: '合成测试版',
      evidencePdfPages: const [1],
    );

void main() {
  late Directory directory;
  final bytes = syntheticPdf();
  final entry = entryFor(bytes);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_download_');
  });
  tearDown(() async => directory.delete(recursive: true));

  TextbookFileService service(
    Future<http.StreamedResponse> Function(http.BaseRequest) response, {
    Future<int> Function(String)? validator,
    Duration timeout = const Duration(seconds: 30),
    int maxSize = 250 * 1024 * 1024,
  }) =>
      TextbookFileService(
        directoryProvider: () async => directory,
        validator: validator ?? (_) async => 3,
        requestTimeout: timeout,
        maxFileSize: maxSize,
        clientFactory: () =>
            MockClient.streaming((request, _) => response(request)),
      );

  test('流式下载校验完整哈希与页数后发布，可离线读取且无需重下载', () async {
    var requests = 0;
    final progress = <int>[];
    final files = service(
      (request) async {
        requests++;
        expect(request.url, entry.downloadUrl);
        expect(request.followRedirects, isFalse);
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 7), bytes.sublist(7)]),
          200,
          contentLength: bytes.length,
        );
      },
      validator: (path) async {
        expect(await File(path).readAsBytes(), bytes);
        expect(path.endsWith('.pending'), isTrue);
        return 3;
      },
    );
    final imported = await files.downloadPdf(
      entry: entry,
      token: TextbookImportToken(),
      onProgress: (received, total) {
        expect(total, bytes.length);
        progress.add(received);
      },
    );
    expect(imported.sha256, entry.book.pdfSha256);
    expect(imported.pageCount, 3);
    expect(imported.size, bytes.length);
    expect(progress, [0, 7, bytes.length]);
    final path = await files.installedPath(entry.book);
    expect(await File(path!).readAsBytes(), bytes);
    expect(requests, 1);
    expect(Directory('${directory.path}/textbooks').listSync().length, 1);
  });

  test('响应头失败、断流、无效头及哈希错误均保留旧文件，之后可重试', () async {
    var attempt = 0;
    var validated = 0;
    final files = service(
      (_) async {
        attempt++;
        switch (attempt) {
          case 1:
            return http.StreamedResponse(Stream.value(bytes), 429);
          case 2:
            return http.StreamedResponse(
                Stream.value(bytes.sublist(0, 10)), 200,);
          case 3:
            return http.StreamedResponse(
              Stream.value(List.filled(bytes.length, 0)),
              200,
            );
          case 4:
            return http.StreamedResponse(
                Stream.value([...bytes]..[20] = 0), 200,);
          default:
            return http.StreamedResponse(Stream.value(bytes), 200);
        }
      },
      validator: (_) async {
        validated++;
        return 3;
      },
    );
    final folder = await Directory('${directory.path}/textbooks').create();
    final old = await File('${folder.path}/${entry.book.pdfSha256}.pdf')
        .writeAsBytes(bytes);
    for (var i = 0; i < 4; i++) {
      await expectLater(
        files.downloadPdf(entry: entry, token: TextbookImportToken()),
        throwsA(isA<TextbookFileException>()),
      );
      expect(await old.readAsBytes(), bytes);
      expect(folder.listSync().length, 1);
    }
    expect(validated, 0);
    await files.downloadPdf(entry: entry, token: TextbookImportToken());
    expect(validated, 1);
    expect(await old.readAsBytes(), bytes);
  });

  test('头部大小不匹配、实际超量、超过上限与页数不匹配拒绝发布', () async {
    final cases = [
      service(
        (_) async =>
            http.StreamedResponse(Stream.value(bytes), 200, contentLength: 1),
      ),
      service(
        (_) async => http.StreamedResponse(Stream.value([...bytes, 0]), 200),
      ),
      service(
        (_) async => http.StreamedResponse(Stream.value(bytes), 200),
        maxSize: 8,
      ),
      service(
        (_) async => http.StreamedResponse(Stream.value(bytes), 200),
        validator: (_) async => 2,
      ),
    ];
    for (final files in cases) {
      await expectLater(
        files.downloadPdf(entry: entry, token: TextbookImportToken()),
        throwsA(isA<TextbookFileException>()),
      );
      expect(await files.installedPath(entry.book), isNull);
      expect(Directory('${directory.path}/textbooks').listSync(), isEmpty);
    }
  });

  test('预取消不发请求，等待响应时取消立即中止请求', () async {
    final entered = Completer<void>();
    var requests = 0;
    final files = service((request) async {
      requests++;
      entered.complete();
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    await expectLater(
      files.downloadPdf(entry: entry, token: TextbookImportToken()..cancel()),
      throwsA(isA<TextbookDownloadCancelled>()),
    );
    expect(requests, 0);
    final token = TextbookImportToken();
    final download = files.downloadPdf(entry: entry, token: token);
    final assertion =
        expectLater(download, throwsA(isA<TextbookDownloadCancelled>()));
    await entered.future;
    token.cancel();
    await assertion.timeout(const Duration(seconds: 2));
    expect(requests, 1);
    expect(await Directory('${directory.path}/textbooks').exists(), isFalse);
  });

  test('正文空闲时取消立即清理，校验期间取消不替换旧文件', () async {
    final stream = StreamController<List<int>>();
    final copied = Completer<void>();
    final files = service((request) async {
      unawaited(
        (request as http.AbortableRequest).abortTrigger!.then((_) {
          if (!stream.isClosed) {
            stream.addError(http.RequestAbortedException(request.url));
            unawaited(stream.close());
          }
        }),
      );
      return http.StreamedResponse(stream.stream, 200);
    });
    final token = TextbookImportToken();
    final download = files.downloadPdf(
      entry: entry,
      token: token,
      onProgress: (received, _) {
        if (received > 0) copied.complete();
      },
    );
    final assertion =
        expectLater(download, throwsA(isA<TextbookDownloadCancelled>()));
    stream.add(bytes.sublist(0, 7));
    await copied.future;
    token.cancel();
    await assertion.timeout(const Duration(seconds: 2));
    expect(Directory('${directory.path}/textbooks').listSync(), isEmpty);

    final old =
        await File('${directory.path}/textbooks/${entry.book.pdfSha256}.pdf')
            .writeAsBytes(bytes);
    final validating = Completer<void>();
    final release = Completer<int>();
    final validationFiles = service(
      (_) async => http.StreamedResponse(Stream.value(bytes), 200),
      validator: (_) {
        validating.complete();
        return release.future;
      },
    );
    final validationToken = TextbookImportToken();
    final validation =
        validationFiles.downloadPdf(entry: entry, token: validationToken);
    final rejected =
        expectLater(validation, throwsA(isA<TextbookDownloadCancelled>()));
    await validating.future;
    validationToken.cancel();
    release.complete(3);
    await rejected;
    expect(await old.readAsBytes(), bytes);
    expect(Directory('${directory.path}/textbooks').listSync().length, 1);
  });

  test('空闲超时可重试，持续有数据不按总时长超时', () async {
    final stalled = StreamController<List<int>>();
    final files = service(
      (_) async => http.StreamedResponse(stalled.stream, 200),
      timeout: const Duration(milliseconds: 40),
    );
    await expectLater(
      files.downloadPdf(entry: entry, token: TextbookImportToken()),
      throwsA(
        isA<TextbookFileException>()
            .having((e) => e.message, 'message', contains('超时')),
      ),
    );
    await stalled.close();
    expect(Directory('${directory.path}/textbooks').listSync(), isEmpty);
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < bytes.length; i += 100) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        yield bytes.sublist(i, (i + 100).clamp(0, bytes.length));
      }
    }

    final slow = service(
      (_) async => http.StreamedResponse(chunks(), 200),
      timeout: const Duration(milliseconds: 80),
    );
    await slow.downloadPdf(entry: entry, token: TextbookImportToken());
    expect(
      await File((await slow.installedPath(entry.book))!).readAsBytes(),
      bytes,
    );
  });

  test('raw来源限流时切到相同blob，仍按原SHA和大小校验；取消不请求备用', () async {
    final fallbackEntry = TextbookCatalogEntry(
      book: entry.book,
      downloadUrl: entry.downloadUrl,
      sourceRepository: entry.sourceRepository,
      sourceCommit: entry.sourceCommit,
      sourcePath: entry.sourcePath,
      editionLabel: entry.editionLabel,
      evidencePdfPages: entry.evidencePdfPages,
      sourceBlobSha: List.filled(40, 'b').join(),
    );
    final urls = <Uri>[];
    final files = service((request) async {
      urls.add(request.url);
      if (request.url == entry.downloadUrl) {
        return http.StreamedResponse(const Stream.empty(), 429);
      }
      expect(request.url, fallbackEntry.fallbackDownloadUrl);
      expect(request.headers['Accept'], 'application/vnd.github.raw+json');
      return http.StreamedResponse(Stream.value(bytes), 200);
    });
    await files.downloadPdf(entry: fallbackEntry, token: TextbookImportToken());
    expect(urls, [entry.downloadUrl, fallbackEntry.fallbackDownloadUrl]);
    expect(await File((await files.installedPath(entry.book))!).readAsBytes(),
        bytes,);
    urls.clear();
    await expectLater(
        files.downloadPdf(
            entry: fallbackEntry, token: TextbookImportToken()..cancel(),),
        throwsA(isA<TextbookDownloadCancelled>()),);
    expect(urls, isEmpty);
  });
}
