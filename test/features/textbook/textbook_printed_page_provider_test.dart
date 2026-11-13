import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/textbook_fixture.dart';
import '../../helpers/textbook_page_number_fixture.dart';

class _CachedFiles extends TextbookFileService {
  _CachedFiles(this.cache);
  final TextbookContentCache cache;
  var pathReads = 0;

  @override
  TextbookContentCache contentCache(Textbook book) => cache;

  @override
  Future<String?> installedPath(Textbook book) async {
    pathReads++;
    throw StateError('已有布局缓存不应重新打开 PDF');
  }
}

void main() {
  final book = textbookFixture(pageCount: 8);
  late Directory directory;
  TextbookContentCache reopen() => TextbookContentCache(
    book: book,
    directoryProvider: () async => directory,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('printed_page_provider_');
  });
  tearDown(() => directory.delete(recursive: true));

  test('书架和续读按保存物理页复用冷布局，只缓存实际请求页', () async {
    await reopen().pageLayout(7, () async => printedPageFixture(7, 2));
    await reopen().pageLayout(1, () async => printedPageFixture(1, null));
    final files = _CachedFiles(reopen());
    final container = ProviderContainer(
      overrides: [
        textbookLocalListProvider.overrideWithValue([book]),
        textbookFileServiceProvider.overrideWithValue(files),
        textbookPathProvider(book.pdfSha256)
            .overrideWith((_) async => '/unused.pdf'),
      ],
    );
    addTearDown(container.dispose);
    final provider = textbookPrintedPageProvider((
      bookId: book.pdfSha256,
      page: 7,
    ));
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    expect(await container.read(provider.future), 2);
    expect(files.pathReads, 0);
    expect((await reopen().readPageNumbers()).pages, {7: 2});
    final cover = textbookPrintedPageProvider((
      bookId: book.pdfSha256,
      page: 1,
    ));
    final coverSubscription = container.listen(cover, (_, __) {});
    addTearDown(coverSubscription.close);
    expect(await container.read(cover.future), isNull);
    expect((await reopen().readPageNumbers()).pages, {1: null, 7: 2});
  });

  test('缺文件错误保留为错误状态，不缓存为未编号', () async {
    final cache = reopen();
    final container = ProviderContainer(
      overrides: [
        textbookLocalListProvider.overrideWithValue([book]),
        textbookFileServiceProvider.overrideWithValue(_CachedFiles(cache)),
        textbookPathProvider(book.pdfSha256).overrideWith((_) async => null),
      ],
    );
    addTearDown(container.dispose);
    final provider = textbookPrintedPageProvider((
      bookId: book.pdfSha256,
      page: 7,
    ));
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    await expectLater(container.read(provider.future), throwsStateError);
    expect(container.read(provider).hasError, isTrue);
    expect(cache.pageNumbers.pages, isEmpty);
  });
}
