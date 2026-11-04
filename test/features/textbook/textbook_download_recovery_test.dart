import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/repositories/textbook_download_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

class _UnavailableIntents extends TextbookDownloadRepository {
  @override
  Future<void> markPending(String id) async => throw StateError('disk full');
}

void main() {
  late Directory directory;
  final bytes = syntheticPdf();
  final book = textbookFixture(
    id: sha256.convert(bytes).toString(),
    fileSize: bytes.length,
  );
  final entry = TextbookCatalogEntry(
    book: book,
    downloadUrl: Uri.parse('https://example.com/sample.pdf'),
    sourceRepository: 'test/books',
    sourceCommit: 'a' * 40,
    sourcePath: 'sample.pdf',
    editionLabel: '合成测试',
    evidencePdfPages: const [1],
  );
  setUp(() async {
    await setUpHiveForTesting();
    directory = await Directory.systemTemp.createTemp('textbook_resume_');
  });
  tearDown(() async {
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  TextbookFileService files(
    Future<http.StreamedResponse> Function(http.BaseRequest) response,
  ) => TextbookFileService(
    directoryProvider: () async => directory,
    validator: (_) async => 3,
    clientFactory: () =>
        MockClient.streaming((request, _) => response(request)),
  );

  Future<void> reopenMeta() async {
    final name = HiveBoxes.meta.name;
    await HiveBoxes.meta.close();
    HiveBoxes.meta = await Hive.openBox<dynamic>(name, crashRecovery: false);
  }

  test('应用销毁后重开存储和控制器，自动续传同一任务且不重复统计或登记', () async {
    final intents = TextbookDownloadRepository();
    final repo = TextbookRepository();
    await repo.savePage('parent-profile', book, 2);
    final firstChunk = Completer<void>();
    final firstFiles = files((request) async {
      // 请求之前意图必须已持久化。
      expect(intents.pendingIds(), {book.pdfSha256});
      Stream<List<int>> body() async* {
        yield bytes.sublist(0, 128);
        await (request as http.AbortableRequest).abortTrigger;
        throw http.RequestAbortedException(request.url);
      }

      return http.StreamedResponse(body(), 200);
    });
    final first = TextbookDownloadController(
      firstFiles,
      repo,
      (_) => fail('下载未完成不得登记'),
      downloads: intents,
    );
    first.addListener((state) {
      if ((state[book.pdfSha256]?.progress ?? 0) > 0 &&
          !firstChunk.isCompleted) {
        firstChunk.complete();
      }
    });
    final transfer = first.download(entry);
    await firstChunk.future.timeout(const Duration(seconds: 5));
    expect(repo.list(), isEmpty);
    first.dispose();
    await transfer.timeout(const Duration(seconds: 5));
    final partial = File(
      '${directory.path}/textbooks/${book.pdfSha256}.download.pending',
    );
    expect(await partial.readAsBytes(), bytes.sublist(0, 128));
    await reopenMeta();
    expect(TextbookDownloadRepository().pendingIds(), {book.pdfSha256});

    var requests = 0;
    final resumeEntered = Completer<void>();
    final resumeRelease = Completer<void>();
    final installed = <String>[];
    final second = TextbookDownloadController(
      files((request) async {
        requests++;
        expect(request.headers['Range'], 'bytes=128-');
        resumeEntered.complete();
        await resumeRelease.future;
        return http.StreamedResponse(
          Stream.value(bytes.sublist(128)),
          206,
          contentLength: bytes.length - 128,
          headers: {
            'content-range': 'bytes 128-${bytes.length - 1}/${bytes.length}',
          },
        );
      }),
      TextbookRepository(),
      installed.add,
      downloads: TextbookDownloadRepository(),
    );
    addTearDown(second.dispose);
    final restoring = second.restorePending([entry]);
    expect(identical(second.restorePending([entry]), restoring), isTrue);
    await resumeEntered.future.timeout(const Duration(seconds: 5));
    await second.download(entry);
    expect(requests, 1);
    resumeRelease.complete();
    await restoring;
    await second.restorePending([entry]);
    expect(requests, 1);
    expect(installed, [book.pdfSha256]);
    expect(second.state, isEmpty);
    expect(TextbookDownloadRepository().pendingIds(), isEmpty);
    expect(repo.list().map((b) => b.pdfSha256), [book.pdfSha256]);
    expect(repo.reading('parent-profile', book.pdfSha256).page, 2);
    expect(
      await File('${directory.path}/textbooks/${book.pdfSha256}.pdf')
          .readAsBytes(),
      bytes,
    );
    expect(await partial.exists(), isFalse);
  });

  test('主动取消清理意图和部分文件，重进不会自动重下', () async {
    final intents = TextbookDownloadRepository();
    final copied = Completer<void>();
    var requests = 0;
    final downloadFiles = files((request) async {
      requests++;
      Stream<List<int>> body() async* {
        yield bytes.sublist(0, 128);
        await (request as http.AbortableRequest).abortTrigger;
        throw http.RequestAbortedException(request.url);
      }

      return http.StreamedResponse(body(), 200);
    });
    final controller = TextbookDownloadController(
      downloadFiles,
      TextbookRepository(),
      (_) {},
      downloads: intents,
    );
    controller.addListener((state) {
      if ((state[book.pdfSha256]?.progress ?? 0) > 0 && !copied.isCompleted) {
        copied.complete();
      }
    });
    final transfer = controller.download(entry);
    await copied.future.timeout(const Duration(seconds: 5));
    controller.cancel(book.pdfSha256);
    await transfer.timeout(const Duration(seconds: 5));
    expect(
      controller.state[book.pdfSha256]!.status,
      TextbookDownloadStatus.cancelled,
    );
    expect(intents.pendingIds(), isEmpty);
    expect(
      await File(
        '${directory.path}/textbooks/${book.pdfSha256}.download.pending',
      ).exists(),
      isFalse,
    );
    expect(TextbookRepository().list(), isEmpty);
    controller.dispose();
    await reopenMeta();
    final reopened = TextbookDownloadController(
      downloadFiles,
      TextbookRepository(),
      (_) {},
      downloads: TextbookDownloadRepository(),
    );
    addTearDown(reopened.dispose);
    await reopened.restorePending([entry]);
    expect(requests, 1);
    expect(reopened.state, isEmpty);
  });

  test('完整文件已发布但登记前退出，重进离线补登记且清理任务', () async {
    final intents = TextbookDownloadRepository();
    await intents.markPending(book.pdfSha256);
    final downloadFiles = files(
      (_) async => http.StreamedResponse(Stream.value(bytes), 200),
    );
    await downloadFiles.downloadPdf(entry: entry, token: TextbookImportToken());
    expect(TextbookRepository().list(), isEmpty);
    await reopenMeta();
    var requests = 0;
    final installed = <String>[];
    final restored = TextbookDownloadController(
      files((_) async {
        requests++;
        throw const SocketException('offline');
      }),
      TextbookRepository(),
      installed.add,
      downloads: TextbookDownloadRepository(),
    );
    addTearDown(restored.dispose);
    await restored.restorePending([entry]);
    expect(requests, 0);
    expect(installed, [book.pdfSha256]);
    expect(TextbookRepository().find(book.pdfSha256)!.fileSize, bytes.length);
    expect(TextbookDownloadRepository().pendingIds(), isEmpty);
  });

  test('排队中的任务取消立即保存，不等待前一册下载结束', () async {
    final intents = TextbookDownloadRepository();
    final firstChunk = Completer<void>();
    var requests = 0;
    final downloadFiles = files((request) async {
      requests++;
      Stream<List<int>> body() async* {
        yield bytes.sublist(0, 128);
        await (request as http.AbortableRequest).abortTrigger;
        throw http.RequestAbortedException(request.url);
      }

      return http.StreamedResponse(body(), 200);
    });
    final controller = TextbookDownloadController(
      downloadFiles,
      TextbookRepository(),
      (_) {},
      downloads: intents,
    );
    controller.addListener((state) {
      if ((state[book.pdfSha256]?.progress ?? 0) > 0 &&
          !firstChunk.isCompleted) {
        firstChunk.complete();
      }
    });
    final first = controller.download(entry);
    await firstChunk.future.timeout(const Duration(seconds: 5));
    final other = TextbookCatalogEntry(
      book: textbookFixture(id: 'b' * 64, fileSize: bytes.length),
      downloadUrl: entry.downloadUrl,
      sourceRepository: entry.sourceRepository,
      sourceCommit: entry.sourceCommit,
      sourcePath: entry.sourcePath,
      editionLabel: entry.editionLabel,
      evidencePdfPages: entry.evidencePdfPages,
    );
    final key =
        '${TextbookDownloadRepository.keyPrefix}${other.book.pdfSha256}';
    final queued = HiveBoxes.meta.watch(key: key).first;
    final second = controller.download(other);
    await queued.timeout(const Duration(seconds: 5));
    expect(intents.pendingIds(), {book.pdfSha256, other.book.pdfSha256});
    final cancelled = HiveBoxes.meta
        .watch(key: key)
        .firstWhere((event) => event.deleted);
    controller.cancel(other.book.pdfSha256);
    await cancelled.timeout(const Duration(seconds: 5));
    expect(intents.pendingIds(), {book.pdfSha256});
    expect(controller.state[book.pdfSha256]!.active, isTrue);
    expect(requests, 1);
    controller.dispose();
    await Future.wait([first, second]).timeout(const Duration(seconds: 5));
    expect(intents.pendingIds(), {book.pdfSha256});
    expect(requests, 1);
  });

  test('任务保存失败不发网络请求；损坏或目录外任务不自动下载', () async {
    var requests = 0;
    final downloadFiles = files((_) async {
      requests++;
      return http.StreamedResponse(Stream.value(bytes), 200);
    });
    final failed = TextbookDownloadController(
      downloadFiles,
      TextbookRepository(),
      (_) {},
      downloads: _UnavailableIntents(),
    );
    addTearDown(failed.dispose);
    await failed.download(entry);
    expect(requests, 0);
    expect(failed.state[book.pdfSha256]!.status, TextbookDownloadStatus.failed);
    final prefix = TextbookDownloadRepository.keyPrefix;
    await HiveBoxes.meta.put('${prefix}invalid', true);
    await HiveBoxes.meta.put('$prefix${book.pdfSha256}', 'corrupt');
    await TextbookDownloadRepository().markPending('b' * 64);
    final restored = TextbookDownloadController(
      downloadFiles,
      TextbookRepository(),
      (_) {},
      downloads: TextbookDownloadRepository(),
    );
    addTearDown(restored.dispose);
    await restored.restorePending([entry]);
    expect(requests, 0);
    expect(TextbookDownloadRepository().pendingIds(), {'b' * 64});
    expect(HiveBoxes.meta.get('$prefix${book.pdfSha256}'), 'corrupt');
  });
}
