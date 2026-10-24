import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

import '../test/helpers/textbook_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实PDF目录与逐页文字落盘，重建文档后目录直接就绪并可换词搜索', (tester) async {
    final directory = await Directory.systemTemp.createTemp('content_cache_');
    final bytes = syntheticPdf(bookmarks: true);
    final file = await File('${directory.path}/sample.pdf').writeAsBytes(bytes);
    final book = textbookFixture(
      id: sha256.convert(bytes).toString(),
      fileSize: bytes.length,
    );
    TextbookTocLoader? toc;
    TextbookSearch? search;
    Future<void> open() async {
      toc = null;
      search = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextbookPdfPreview(
              options: TextbookViewerOptions(
                path: file.path,
                contentCache: TextbookContentCache(
                  book: book,
                  directoryProvider: () async => directory,
                ),
                initialPage: 1,
                onPageChanged: (_) {},
                onReady: (_) {},
                onRetry: () {},
                onTocReady: (value) => toc = value,
                onSearchReady: (value) => search = value,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 300 && (toc == null || search == null); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(toc, isNotNull);
      expect(search, isNotNull);
    }

    try {
      await open();
      final firstToc = await toc!(false).toList();
      expect(firstToc.first.phase, TextbookTocPhase.locating);
      expect(firstToc.last.result!.entries.map((e) => e.page), [2, 3]);
      final firstSearch = await search!('sample').toList();
      expect(firstSearch.map((page) => page.matchCount), [1, 1, 1]);
      final cacheDirectory = Directory(
        '${directory.path}/textbooks/cache/${book.pdfSha256}',
      );
      Future<Map<String, DateTime>> snapshot() async {
        final result = <String, DateTime>{};
        await for (final entry in cacheDirectory.list()) {
          result[entry.path] = (await entry.stat()).modified;
        }
        return result;
      }

      final before = await snapshot();
      expect(before.length, 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await open();
      final nextToc = await toc!(false).toList();
      expect(nextToc.map((event) => event.phase), [TextbookTocPhase.ready]);
      expect(
        nextToc.single.result!.entries.map((e) => e.title),
        ['Chapter', 'Section'],
      );
      final nextSearch = await search!('PoeMath').toList();
      expect(nextSearch.map((page) => page.matchCount), [1, 1, 1]);
      final after = await snapshot();
      expect(after, before);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await directory.delete(recursive: true);
    }
  });
  testWidgets('真实内置目录保留层级，复用原书阅读文档', (tester) async {
    final directory = await Directory.systemTemp.createTemp('toc_bookmarks_');
    final file = await File('${directory.path}/sample.pdf')
        .writeAsBytes(syntheticPdf(bookmarks: true));
    TextbookTocLoader? load;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextbookPdfView(
              options: TextbookViewerOptions(
                path: file.path,
                initialPage: 1,
                onPageChanged: (_) {},
                onReady: (_) {},
                onRetry: () {},
                onTocReady: (value) => load = value,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 300 && load == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(load, isNotNull);
      final result = (await load!(false).last).result!;
      expect(result.source, TextbookTocSource.bookmarks);
      expect(result.entries.map((e) => e.title), ['Chapter', 'Section']);
      expect(result.entries.map((e) => e.page), [2, 3]);
      expect(result.entries.map((e) => e.level), [0, 1]);
      expect((await load!(false).last).result, same(result));
    } finally {
      await tester.pumpWidget(const SizedBox());
      await directory.delete(recursive: true);
    }
  });
  const local = String.fromEnvironment('TEXTBOOK_TOC_ACCEPTANCE');
  for (final sample in [
    (
      path:
          '/data/user/0/com.poemath.app/files/textbooks/294652c84058ac8d60364e3e04e4cd5ebd37ecf189293b5308ce26c46cfa498f.pdf',
      pages: [4, 5, 6],
      count: 42,
      targets: {
        '春夏秋冬': 7,
        '小公鸡和小鸭子': 31,
        '静夜思': 44,
        '池上': 66,
        '小池': 67,
        '文具的家': 83,
      },
    ),
    (
      path: '/data/user/0/com.poemath.app/cache/poemath-toc-grade2-first.pdf',
      pages: [4, 5],
      count: 43,
      targets: {'小蝌蚪找妈妈': 6, '读读童话故事': 20, '彩虹': 33, '江雪': 86, '词语表': 121},
    ),
    (
      path: '/data/user/0/com.poemath.app/cache/poemath-toc-grade6-second.pdf',
      pages: [4, 5],
      count: 61,
      targets: {
        '北京的春节': 7,
        '漫步世界名著花园': 46,
        '学弈': 85,
        '采薇（节选）': 116,
        '清平乐': 125,
      },
    ),
  ]) {
    testWidgets(
      '真实PDF自动目录：${sample.path.split('/').last}',
      (tester) async {
        TextbookTocLoader? load;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextbookPdfPreview(
                options: TextbookViewerOptions(
                  path: sample.path,
                  initialPage: 1,
                  onPageChanged: (_) {},
                  onReady: (_) {},
                  onRetry: () {},
                  onTocReady: (value) => load = value,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 300 && load == null; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(load, isNotNull);
        final document =
            tester.widget<PdfPageView>(find.byType(PdfPageView).first).document;
        final result =
            (await load!(false).last.timeout(const Duration(minutes: 2)))
                .result!;
        debugPrint(
          'TOC_ACCEPTANCE count=${result.entries.length} resolved=${result.entries.where((e) => e.page != null).length} pages=${result.directoryPages}',
        );
        expect(result.source, TextbookTocSource.text);
        expect(result.directoryPages, sample.pages);
        if (sample.count > 0) {
          final numbered = result.entries.where((e) => e.printedPage != null);
          expect(numbered.length, sample.count);
          expect(numbered.every((e) => e.page != null), isTrue);
          expect(
            result.entries.where((e) => e.isGroup).length,
            greaterThanOrEqualTo(sample.count == 61 ? 7 : 8),
          );
          expect(
            result.entries.where((e) => e.lessonNumber == 1).length,
            greaterThanOrEqualTo(2),
          );
          expect(result.entries.last.level, 0);
          final child = result.entries.firstWhere(
            (e) =>
                e.title ==
                (sample.count == 42
                    ? '池上'
                    : sample.count == 43
                        ? '江雪'
                        : '学弈'),
          );
          expect(child.level, 2);
          String parentTitle(String title, int level) {
            final index = result.entries.indexWhere((e) => e.title == title);
            return result.entries
                .take(index)
                .lastWhere((e) => e.level == level)
                .title;
          }

          if (sample.count == 42) {
            expect(parentTitle('池上', 1), '古诗二首');
            expect(
              result.entries.firstWhere((e) => e.title == '动物儿歌').lessonNumber,
              5,
            );
          } else if (sample.count == 43) {
            expect(parentTitle('雾在哪里', 0), contains('第七单元'));
            expect(parentTitle('江雪', 1), '古诗二首');
          } else {
            expect(parentTitle('为人民服务', 0), '第四单元');
            expect(parentTitle('依依惜别', 0), '第六单元');
            expect(parentTitle('采薇（节选）', 0), '古诗词诵读');
            expect(parentTitle('学弈', 1), '文言文二则');
          }
        }
        for (final target in sample.targets.entries) {
          expect(
            result.entries
                .where((e) => e.title == target.key)
                .map((e) => e.page),
            [target.value],
            reason: target.key,
          );
        }
        expect((await load!(false).last).result, same(result));
        expect(
          tester.widget<PdfPageView>(find.byType(PdfPageView).first).document,
          same(document),
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
      skip: local.isEmpty,
    );
  }
}
