import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/core/services/textbook_toc_service.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

import '../../helpers/textbook_fixture.dart';
import '../../helpers/textbook_draft_fixture.dart';
import 'package:poemath/data/models/textbook_page_text.dart';

const _tree = TextbookTocResult(
  source: TextbookTocSource.text,
  directoryPages: [1],
  hasText: true,
  entries: [
    TextbookTocEntry(title: '第一单元', isGroup: true),
    TextbookTocEntry(
      title: '古诗二首',
      page: 2,
      printedPage: 1,
      lessonNumber: 1,
      level: 1,
    ),
    TextbookTocEntry(title: '春晓', page: 3, printedPage: 2, level: 2),
    TextbookTocEntry(title: '未定位', printedPage: 3),
  ],
);

void main() {
  late Directory directory;
  final book = textbookFixture();
  TextbookContentCache reopen() => TextbookContentCache(
        book: book,
        directoryProvider: () async => directory,
      );
  File stored(String name) => File(
        '${directory.path}/textbooks/cache/${book.pdfSha256}/$name.json',
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_content_');
  });
  tearDown(() => directory.delete(recursive: true));

  test('目录树持久化完整往返，新识别服务命中后不再调用PDF读取', () async {
    await reopen().writeToc(_tree);
    final toc = TextbookTocService(
      pageCount: 3,
      cache: reopen(),
      loadOutline: () => throw StateError('不应重读书签'),
      loadPage: (_) => throw StateError('不应重读文字'),
    );
    final events = await toc.scan().toList();
    expect(events.map((event) => event.phase), [TextbookTocPhase.ready]);
    expect(encodeTextbookToc(events.single.result!), encodeTextbookToc(_tree));
    expect((await stored('toc').readAsString()).contains('古诗二首'), isTrue);
  });

  test('识别服务完成后自动落盘，显式重试可替换旧目录', () async {
    final first = TextbookTocService(
      pageCount: 3,
      cache: reopen(),
      loadOutline: () async => [const TextbookTocEntry(title: '章节', page: 2)],
      loadPage: (_) => throw StateError('书签不需要正文'),
    );
    await first.scan().last;
    expect((await reopen().readToc())!.entries.single.title, '章节');
    final second = TextbookTocService(
      pageCount: 3,
      cache: reopen(),
      loadOutline: () async => [const TextbookTocEntry(title: '刷新章节', page: 3)],
      loadPage: (_) => throw StateError('书签不需要正文'),
    );
    expect((await second.scan().last).result!.entries.single.title, '章节');
    expect(
      (await second.scan(refresh: true).last).result!.entries.single.page,
      3,
    );
    expect((await reopen().readToc())!.entries.single.title, '刷新章节');
  });

  test('第一次搜索逐页缓存，重建服务换词和空页均不再提取PDF', () async {
    final loads = <int>[];
    final cache = reopen();
    final first = await searchTextbookPages(
      query: '春晓',
      pageCount: 3,
      loadPageText: (page) => cache.pageText(page, () async {
        loads.add(page);
        return ['春 chūn 晓 xiǎo。', '', '春天的远山'][page - 1];
      }),
    ).toList();
    expect(first.map((page) => page.matchCount), [1, 0, 0]);
    expect(loads, [1, 2, 3]);
    final next = reopen();
    final second = await searchTextbookPages(
      query: '远山',
      pageCount: 3,
      loadPageText: (page) => next.pageText(
        page,
        () => throw StateError('不应再提取文字'),
      ),
    ).toList();
    expect(second.map((page) => page.matchCount), [0, 0, 1]);
    expect(second.map((page) => page.hasText), [true, false, true]);
  });

  test('取消搜索保留已完成页，重新进入只读取未缓存页', () async {
    final cache = reopen();
    final first = searchTextbookPages(
      query: '春',
      pageCount: 3,
      loadPageText: (page) => cache.pageText(page, () async => '春$page'),
    );
    await first.take(1).toList();
    final loads = <int>[];
    final next = reopen();
    final pages = await searchTextbookPages(
      query: '春',
      pageCount: 3,
      loadPageText: (page) => next.pageText(page, () async {
        loads.add(page);
        return '春$page';
      }),
    ).toList();
    expect(loads, [2, 3]);
    expect(pages.map((page) => page.matchCount), [1, 1, 1]);
  });

  test('目录提取的原文供搜索复用，不同PDF哈希互不命中', () async {
    await reopen().rememberText(2, '共用原文');
    expect(await reopen().pageText(2, () => throw StateError('不应重读')), '共用原文');
    final other = TextbookContentCache(
      book: textbookFixture(id: List.filled(64, 'b').join()),
      directoryProvider: () async => directory,
    );
    expect(await other.pageText(2, () async => '另一本书'), '另一本书');
    expect(await reopen().pageText(2, () async => '错误'), '共用原文');
  });

  test('并发同页请求只提取一次，读取失败不污染下一次重试', () async {
    final cache = reopen();
    var calls = 0;
    final pending = Completer<String>();
    final a = cache.pageText(1, () {
      calls++;
      return pending.future;
    });
    final b = cache.pageText(1, () => throw StateError('不能并发重复提取'));
    pending.complete('一页');
    expect(await a, '一页');
    expect(await b, '一页');
    expect(calls, 1);
    await expectLater(
      cache.pageText(2, () => throw StateError('原生读取失败')),
      throwsStateError,
    );
    expect(await cache.pageText(2, () async => '恢复'), '恢复');
  });

  test('损坏JSON、版本/身份/页数不匹配及非法目录均回退重建', () async {
    await reopen().rememberText(1, '旧文字');
    final original = jsonDecode(await stored('page-1').readAsString())
        as Map<String, dynamic>;
    for (final entry in <String, Object>{
      'version': 999,
      'sha256': 'wrong',
      'pageCount': 4,
      'pdfSize': 999,
    }.entries) {
      await stored('page-1')
          .writeAsString(jsonEncode({...original, entry.key: entry.value}));
      expect(
        await reopen().pageText(1, () async => '重建${entry.key}'),
        '重建${entry.key}',
      );
    }
    await stored('page-1').writeAsString('{broken');
    expect(await reopen().pageText(1, () async => '重新读取'), '重新读取');
    await reopen().writeToc(_tree);
    final toc =
        jsonDecode(await stored('toc').readAsString()) as Map<String, dynamic>;
    final data = toc['data'] as Map<String, dynamic>;
    for (final changed in [
      {...data, 'tocVersion': 999},
      {
        ...data,
        'directoryPages': [4],
      },
      {
        ...data,
        'entries': [
          {'title': '非法章节', 'page': 9},
        ],
      },
    ]) {
      await stored('toc').writeAsString(jsonEncode({...toc, 'data': changed}));
      expect(await reopen().readToc(), isNull);
    }
  });

  test('删除缓存时在途文字/目录不得晚到写回，之后可以重新缓存', () async {
    final cache = reopen();
    await cache.rememberText(1, '已有页');
    await cache.writeToc(_tree);
    final entered = Completer<void>();
    final pending = Completer<String>();
    final revision = cache.revision;
    final work = cache.pageText(2, () {
      entered.complete();
      return pending.future;
    });
    await entered.future;
    await cache.clear();
    pending.complete('迟到页');
    await work;
    await cache.writeToc(_tree, generation: revision);
    expect(await stored('page-1').exists(), isFalse);
    expect(await stored('page-2').exists(), isFalse);
    expect(await stored('toc').exists(), isFalse);
    expect(await cache.readToc(), isNull);
    expect(await cache.pageText(2, () async => '重新导入'), '重新导入');
    expect(await reopen().pageText(2, () => throw StateError('应命中')), '重新导入');
  });

  test('存储不可写时结果仍可用，下一实例可重建', () async {
    final blocked =
        await File('${directory.path}/blocked').writeAsString('file');
    final cache = TextbookContentCache(
      book: book,
      directoryProvider: () async => Directory(blocked.path),
    );
    expect(await cache.pageText(1, () async => '仍可搜索'), '仍可搜索');
    await cache.writeToc(_tree);
    expect(await cache.readToc(), same(_tree));
    expect(await reopen().pageText(1, () async => '重新提取'), '重新提取');
  });

  test('布局缓存按版本冷启动复用，清理后迟到布局和页文都不能复活', () async {
    final cache = reopen();
    final page = layoutFixturePage(2, ['自有布局']);
    await cache.pageLayout(2, () async => page);
    expect(
        (await reopen().pageLayout(2, () => throw StateError('应命中'))).toJson(),
        page.toJson(),);
    final entered = Completer<void>();
    final loaded = Completer<TextbookPageText>();
    final pending = cache.pageLayout(3, () {
      entered.complete();
      return loaded.future;
    });
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    await cache.clear();
    loaded.complete(layoutFixturePage(3, ['迟到文字']));
    await rejected;
    for (final name in ['layout-2', 'layout-3', 'page-2', 'page-3']) {
      expect(await stored(name).exists(), isFalse);
    }
    expect(
        (await cache.pageLayout(2, () async => page)).toJson(), page.toJson(),);
    final raw = jsonDecode(await stored('layout-2').readAsString())
        as Map<String, dynamic>;
    (raw['data'] as Map)['layoutVersion'] = 0;
    await stored('layout-2').writeAsString(jsonEncode(raw));
    var calls = 0;
    await reopen().pageLayout(2, () async {
      calls++;
      return page;
    });
    expect(calls, 1);
  });
}
