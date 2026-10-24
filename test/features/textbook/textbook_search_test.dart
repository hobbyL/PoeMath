import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/textbook/widgets/textbook_search_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

void main() {
  test('中文搜索忽略夹在字间的拼音和换行，保留标点及数字边界', () async {
    final pages = [
      '春\r\nchOn\r\n晓\r\nxiAo。春 chūn 晓 xiǎo。',
      '春，晓；春1晓。',
      '',
    ];
    final results = await searchTextbookPages(
      query: ' 春晓 ',
      pageCount: pages.length,
      loadPageText: (page) async => pages[page - 1],
    ).toList();
    expect(results.map((value) => value.page), [1, 2, 3]);
    expect(results.map((value) => value.matchCount), [2, 0, 0]);
    expect(results.map((value) => value.hasText), [true, true, false]);
    expect(results.first.snippet, '春晓。春晓。');
  });

  test('英文混合查询不区分大小写，按字面搜索正则字符', () async {
    final results = await searchTextbookPages(
      query: 'PDF [1]',
      pageCount: 2,
      loadPageText: (page) async => page == 1 ? 'Pdf \n[1] 和 PDF [2]' : 'PDF 1',
    ).toList();
    expect(results.map((value) => value.matchCount), [1, 0]);
    expect(results.first.snippet, 'Pdf[1]和PDF[2]');
  });

  test('空关键词不加载PDF，关闭流后不继续读取下一页', () async {
    final loaded = <int>[];
    Future<String> load(int page) async {
      loaded.add(page);
      return '春晓';
    }

    expect(
      await searchTextbookPages(query: ' ', pageCount: 3, loadPageText: load)
          .toList(),
      isEmpty,
    );
    expect(loaded, isEmpty);
    final results = await searchTextbookPages(
      query: '春晓',
      pageCount: 3,
      loadPageText: load,
    ).take(1).toList();
    expect(results.single.page, 1);
    expect(loaded, [1]);
  });

  test('扫描异常向界面报告，不能把未扫描页当作无结果', () async {
    await expectLater(
      searchTextbookPages(
        query: '春晓',
        pageCount: 3,
        loadPageText: (page) async {
          if (page == 2) throw StateError('unavailable');
          return '春晓';
        },
      ),
      emitsInOrder([
        isA<TextbookSearchPage>().having((value) => value.page, 'page', 1),
        emitsError(isA<StateError>()),
        emitsDone,
      ]),
    );
  });

  Future<void> open(
    WidgetTester tester,
    TextbookSearch search, {
    bool large = false,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(large ? 2 : 1),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showDialog<int>(
                  context: context,
                  builder: (_) =>
                      TextbookSearchDialog(search: search, pageCount: 3),
                ),
                child: const Text('打开搜索'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
  }

  testWidgets('更换关键词取消旧流，进度和晚到结果不串用，关闭停止扫描', (tester) async {
    var firstCancelled = false;
    var secondCancelled = false;
    final first = StreamController<TextbookSearchPage>.broadcast(
      sync: true,
      onCancel: () => firstCancelled = true,
    );
    final second = StreamController<TextbookSearchPage>.broadcast(
      sync: true,
      onCancel: () => secondCancelled = true,
    );
    await open(tester, (query) => query == '春晓' ? first.stream : second.stream);
    expect(find.text('搜索关键词'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '春晓');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('搜索关键词 0 条'), findsOneWidget);
    first.add(
      const TextbookSearchPage(
        page: 1,
        hasText: true,
        matchCount: 1,
        snippet: '旧结果',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧结果'), findsOneWidget);
    expect(find.text('搜索关键词 1 条'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value,
      1 / 3,
    );
    first.add(
      const TextbookSearchPage(
        page: 2,
        hasText: true,
        matchCount: 2,
        snippet: '另一页结果',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('搜索关键词 2 条'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '小鸭子');
    await tester.pumpAndSettle();
    expect(firstCancelled, isTrue);
    expect(find.text('旧结果'), findsNothing);
    expect(find.text('搜索关键词'), findsOneWidget);
    first.add(
      const TextbookSearchPage(
        page: 2,
        hasText: true,
        matchCount: 1,
        snippet: '迟到旧结果',
      ),
    );
    await tester.tap(find.byTooltip('开始搜索'));
    second.add(
      const TextbookSearchPage(
        page: 3,
        hasText: true,
        matchCount: 2,
        snippet: '新结果',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('迟到旧结果'), findsNothing);
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('第 3 页 · 2 处'), findsOneWidget);
    expect(find.byType(AppTile), findsOneWidget);
    expect(find.text('搜索关键词 1 条'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(secondCancelled, isTrue);
    second.add(const TextbookSearchPage(page: 3, hasText: true));
    final closing = Future.wait([first.close(), second.close()]);
    await tester.pump();
    await closing;
    expect(find.byType(TextbookSearchDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果箭头与页码同行、摘要两行省略，空白处关闭后重开为空且不自动搜索', (tester) async {
    final queries = <String>[];
    const snippet = '第一行内容\n第二行内容\n第三行内容\n第四行内容';
    await open(tester, (query) {
      queries.add(query);
      return Stream.value(
        const TextbookSearchPage(
          page: 2,
          hasText: true,
          matchCount: 1,
          snippet: snippet,
        ),
      );
    });
    expect(find.text('搜索本书'), findsNothing);
    expect(find.byTooltip('关闭搜索'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField), '2022');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('找到 1 页相关内容'), findsNothing);
    expect(find.text('PDF 第 2 页 · 1 处'), findsNothing);
    final title = find.text('第 2 页 · 1 处');
    final summary = find.text(snippet);
    final arrow = find.descendant(
      of: find.byType(AppTile),
      matching: find.byIcon(Icons.chevron_right),
    );
    expect(tester.getCenter(arrow).dy, tester.getCenter(title).dy);
    expect(
      tester.getRect(arrow).left,
      greaterThan(tester.getRect(title).right),
    );
    expect(
      tester.getRect(arrow).bottom,
      lessThanOrEqualTo(tester.getRect(summary).top),
    );
    expect(tester.widget<Text>(summary).maxLines, 2);
    expect(tester.widget<Text>(summary).overflow, TextOverflow.ellipsis);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: summary, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isTrue);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookSearchDialog), findsNothing);
    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.byType(AppTile), findsNothing);
    expect(find.text('搜索关键词'), findsOneWidget);
    expect(find.text('搜索关键词 1 条'), findsNothing);
    expect(queries, ['2022']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('异常可重试，无匹配与无文字状态可区分', (tester) async {
    var calls = 0;
    await open(tester, (query) {
      calls++;
      if (calls == 1) return Stream.error(StateError('unavailable'));
      return searchTextbookPages(
        query: query,
        pageCount: 3,
        loadPageText: (_) async => query == '图片' ? '' : '小鸭子',
      );
    });
    await tester.enterText(find.byType(TextField), '春晓');
    await tester.tap(find.byTooltip('开始搜索'));
    await tester.pumpAndSettle();
    expect(find.text('搜索未完成，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('未找到相关内容'), findsOneWidget);
    expect(find.text('搜索关键词 0 条'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '图片');
    await tester.tap(find.byTooltip('开始搜索'));
    await tester.pumpAndSettle();
    expect(find.text('这本书暂无可搜索的文字'), findsOneWidget);
    expect(find.text('搜索关键词 0 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('短横屏与键盘、大字下搜索内容可滚动，结果仍能点击', (tester) async {
    await open(
      tester,
      (query) => searchTextbookPages(
        query: query,
        pageCount: 3,
        loadPageText: (_) async => '春晓。' * 30,
      ),
      large: true,
      size: const Size(800, 280),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 80);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '春晓');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('textbook-search-result-3'));
    await tester.scrollUntilVisible(
      result,
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(result.hitTestable(), findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.byType(TextbookSearchDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
