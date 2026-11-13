import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';

import '../../helpers/textbook_fixture.dart';
import '../../helpers/textbook_page_number_fixture.dart';

void main() {
  final book = textbookFixture(pageCount: 8);
  late Directory directory;
  TextbookContentCache reopen() => TextbookContentCache(
    book: book,
    directoryProvider: () async => directory,
  );
  File stored(String name) =>
      File('${directory.path}/textbooks/cache/${book.pdfSha256}/$name.json');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_page_numbers_');
  });
  tearDown(() => directory.delete(recursive: true));

  test('插入未编号页后仍按实际页脚定位，冷启动复用数字和空页', () async {
    final printed = <int, int?>{
      1: null,
      2: null,
      3: 1,
      4: 2,
      5: null,
      6: 3,
      7: 4,
      8: null,
    };
    final loads = <int>[];
    final service = TextbookPageNumberService(
      pageCount: 8,
      cache: reopen(),
      loadPage: (page) async {
        loads.add(page);
        return printedPageFixture(page, printed[page]);
      },
    );
    final events = await service.scan().toList();
    expect(events.map((e) => e.scanned), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(events.last.numbers.pages, printed);
    expect(events.last.numbers.complete, isTrue);
    expect(service.numbers.targets(2), [4]);
    expect(service.numbers.targets(3), [6]);
    expect(loads, [1, 2, 3, 4, 5, 6, 7, 8]);
    final second = TextbookPageNumberService(
      pageCount: 8,
      cache: reopen(),
      loadPage: (_) => throw StateError('有效映射不应重开 PDF'),
    );
    expect((await second.load([1, 6, 7])).pages, printed);
    expect((await second.scan().last).numbers.pages, printed);
  });

  test('同页请求去重，不同页并发完成不丢失结果', () async {
    final cache = reopen();
    final first = Completer<int?>();
    final second = Completer<int?>();
    var loads = 0;
    final one = cache.pageNumber(6, () {
      loads++;
      return first.future;
    });
    final duplicate = cache.pageNumber(6, () => throw StateError('重复提取'));
    final two = cache.pageNumber(7, () => second.future);
    first.complete(1);
    second.complete(2);
    expect(await Future.wait([one, duplicate, two]), [1, 1, 2]);
    expect(loads, 1);
    expect((await reopen().readPageNumbers()).pages, {6: 1, 7: 2});
  });

  test('缓存目录无法写入时仍可读取和定位书页，不破坏原有文件', () async {
    final blocker = await File('${directory.path}/blocked')
        .writeAsString('existing file');
    final cache = TextbookContentCache(
      book: book,
      directoryProvider: () async => Directory(blocker.path),
    );
    final loads = <int>[];
    final service = TextbookPageNumberService(
      pageCount: book.pageCount,
      cache: cache,
      loadPage: (page) async {
        loads.add(page);
        return printedPageFixture(page, page == 7 ? 2 : null);
      },
    );
    expect(await service.page(7), 2);
    expect(await service.page(7), 2);
    expect(loads, [7]);
    final complete = (await service.scan().last).numbers;
    expect(complete.complete, isTrue);
    expect(complete.label(7), '第 2 页');
    expect(complete.targets(2), [7]);
    expect(await blocker.readAsString(), 'existing file');
  });

  test('错物理页和加载失败不记成无编号，后续可以重试', () async {
    final cache = reopen();
    var wrong = true;
    final service = TextbookPageNumberService(
      pageCount: 8,
      cache: cache,
      loadPage: (number) async => printedPageFixture(wrong ? 8 : number, 2),
    );
    await expectLater(service.page(7), throwsFormatException);
    expect(cache.pageNumbers.pages, isEmpty);
    wrong = false;
    expect(await service.page(7), 2);
    expect((await reopen().readPageNumbers()).pages, {7: 2});
    final plain = TextbookPageNumberService(
      pageCount: 8,
      loadPage: (_) => throw StateError('同步加载失败'),
    );
    await expectLater(plain.page(1), throwsStateError);
    expect(plain.numbers.pages, isEmpty);
  });

  test('损坏、旧算法及错误 PDF 身份回退，不采用错误映射', () async {
    await reopen().pageNumber(7, () async => 2);
    final raw = jsonDecode(
      await stored('printed-pages').readAsString(),
    ) as Map<String, dynamic>;
    final invalid = [
      '{',
      jsonEncode({...raw, 'sha256': List.filled(64, 'b').join()}),
      jsonEncode({...raw, 'pageCount': 9}),
      jsonEncode({...raw, 'pdfSize': book.fileSize + 1}),
      jsonEncode({
        ...raw,
        'data': {
          'pageNumberVersion': -1,
          'pages': {'7': 9},
        },
      }),
      jsonEncode({
        ...raw,
        'data': {
          'pageNumberVersion': TextbookContentCache.pageNumberVersion,
          'pages': {'9': 2},
        },
      }),
    ];
    for (final content in invalid) {
      await stored('printed-pages').writeAsString(content);
      final cache = reopen();
      var loads = 0;
      expect(
        await cache.pageNumber(7, () async {
          loads++;
          return 2;
        }),
        2,
      );
      expect(loads, 1);
      expect((await reopen().readPageNumbers()).pages, {7: 2});
    }
  });

  test('清理后的迟到结果不能复活缓存，新的请求仍可提取', () async {
    final cache = reopen();
    final started = Completer<void>();
    final late = Completer<int?>();
    final pending = cache.pageNumber(7, () {
      started.complete();
      return late.future;
    });
    final rejected = expectLater(pending, throwsStateError);
    await started.future;
    await cache.clear();
    late.complete(2);
    await rejected;
    expect(cache.pageNumbers.pages, isEmpty);
    expect(await stored('printed-pages').exists(), isFalse);
    expect(await cache.pageNumber(7, () async => 2), 2);
    expect((await reopen().readPageNumbers()).pages, {7: 2});
  });

  test('旧 raw text 失效，可见布局仍复用，新文字能冷启动读取', () async {
    final layout = printedPageFixture(7, 2);
    await reopen().pageLayout(7, () async => layout);
    await stored('page-7').writeAsString(
      jsonEncode({
        'version': TextbookContentCache.formatVersion,
        'sha256': book.pdfSha256,
        'pageCount': book.pageCount,
        'pdfSize': book.fileSize,
        'data': '旧隐藏邻页文字',
      }),
    );
    final cache = reopen();
    var loads = 0;
    expect(
      await cache.pageText(7, () async {
        loads++;
        return (await cache.cachedPageLayout(7))!.text;
      }),
      layout.text,
    );
    expect(loads, 1);
    expect(
      await reopen().pageText(7, () => throw StateError('重读')),
      layout.text,
    );
    expect((await reopen().cachedPageLayout(7))!.toJson(), layout.toJson());
  });

  test('取消扫描只保留已完成页，不继续加载剩余页面', () async {
    final requested = <int>[];
    final service = TextbookPageNumberService(
      pageCount: 8,
      loadPage: (number) async {
        requested.add(number);
        return printedPageFixture(number, number);
      },
    );
    final events = await service.scan().take(1).toList();
    expect(events.single.numbers.pages, {1: 1});
    expect(requested, [1]);
  });
}
