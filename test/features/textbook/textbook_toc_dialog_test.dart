import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_toc_dialog.dart';

const _result = TextbookTocResult(
  source: TextbookTocSource.text,
  directoryPages: [4],
  entries: [
    TextbookTocEntry(title: '已定位章节', page: 9, printedPage: 2),
    TextbookTocEntry(title: '待定位子章节', printedPage: 10, level: 1),
  ],
);
TextbookTocProgress _ready(TextbookTocResult result) => TextbookTocProgress(
      phase: TextbookTocPhase.ready,
      scanned: 20,
      total: 20,
      result: result,
    );

void main() {
  Future<void> open(
    WidgetTester tester,
    TextbookTocLoader load, {
    ValueChanged<int?>? selected,
    bool large = false,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final page =
                    await showTextbookToc(context: context, load: load);
                selected?.call(page);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('窄屏大字目录有缩进和长标题时仍可滚动选择', (tester) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(
      tester,
      (_) => Stream.value(
        _ready(
          const TextbookTocResult(
            source: TextbookTocSource.bookmarks,
            entries: [
              TextbookTocEntry(title: '有较长标题的目录子章节仍然可以选择', page: 7, level: 3),
            ],
          ),
        ),
      ),
      large: true,
    );
    final entry = find.byKey(const ValueKey('textbook-toc-entry-0'));
    await tester.ensureVisible(entry);
    final title = find.text('有较长标题的目录子章节仍然可以选择');
    final page = find.text('第 7 页');
    expect(tester.widget<Text>(title).maxLines, 1);
    expect(
      tester.getCenter(title).dy,
      closeTo(tester.getCenter(page).dy, 0.01),
    );
    expect(tester.getRect(page).left, greaterThan(tester.getRect(title).right));
    expect(tester.takeException(), isNull);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(TextbookTocDrawer), findsNothing);
  });

  testWidgets('左侧滑栏普通树行保留课号，可收起单元和子篇且父章节仍能跳页', (tester) async {
    int? selected;
    const tree = TextbookTocResult(
      source: TextbookTocSource.text,
      directoryPages: [4],
      entries: [
        TextbookTocEntry(title: '第一单元 · 识字', isGroup: true),
        TextbookTocEntry(title: '古诗二首', lessonNumber: 1, page: 7, level: 1),
        TextbookTocEntry(title: '春雨', page: 7, level: 2),
        TextbookTocEntry(title: '第二单元 · 阅读', isGroup: true),
        TextbookTocEntry(title: '远山', lessonNumber: 1, page: 8, level: 1),
        TextbookTocEntry(title: '写字表', page: 20),
      ],
    );
    await open(
      tester,
      (_) => Stream.value(_ready(tree)),
      selected: (value) => selected = value,
      settle: false,
    );
    final drawer = find.byType(Drawer);
    expect(tester.getRect(drawer).left, lessThan(0));
    await tester.pumpAndSettle();
    final rect = tester.getRect(drawer);
    expect(rect.left, 0);
    expect(
      rect.right,
      lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
    );
    expect(rect.top, 0);
    expect(
      find.descendant(of: drawer, matching: find.byType(ColoredCard)),
      findsNothing,
    );
    expect(find.text('目录'), findsNothing);
    expect(find.text('查看原目录'), findsNothing);
    expect(find.byTooltip('重新识别目录'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    double arrowX(int index, IconData icon) => tester
        .getCenter(
          find.descendant(
            of: find.byKey(ValueKey('textbook-toc-entry-$index')),
            matching: find.byIcon(icon),
          ),
        )
        .dx;
    final rightColumn = arrowX(0, Icons.expand_more);
    expect(arrowX(1, Icons.expand_more), rightColumn);
    expect(arrowX(2, Icons.chevron_right), rightColumn);
    expect(arrowX(5, Icons.chevron_right), rightColumn);
    final titleRect = tester.getRect(find.text('1：古诗二首'));
    final pageRect = tester.getRect(find.text('第 7 页').first);
    expect(pageRect.center.dy, closeTo(titleRect.center.dy, 0.01));
    expect(pageRect.left - titleRect.right, 4);
    expect(
      tester.getTopLeft(find.text('1：古诗二首')).dx,
      greaterThan(tester.getTopLeft(find.text('第一单元 · 识字')).dx),
    );
    expect(find.text('部分条目暂未定位页码'), findsNothing);
    expect(find.text('1：古诗二首'), findsOneWidget);
    expect(find.text('1：远山'), findsOneWidget);
    await tester.tap(find.byTooltip('收起1：古诗二首'));
    await tester.pumpAndSettle();
    expect(arrowX(1, Icons.chevron_right), rightColumn);
    expect(find.text('春雨'), findsNothing);
    expect(find.text('1：远山'), findsOneWidget);
    await tester.tap(find.text('第一单元 · 识字'));
    await tester.pumpAndSettle();
    expect(find.text('1：古诗二首'), findsNothing);
    expect(find.text('写字表'), findsOneWidget);
    await tester.tap(find.text('第一单元 · 识字'));
    await tester.pumpAndSettle();
    // 单元恢复后，课文自己的收起状态仍保留。
    expect(find.text('春雨'), findsNothing);
    await tester.tap(find.byTooltip('展开1：古诗二首'));
    await tester.pumpAndSettle();
    expect(find.text('春雨'), findsOneWidget);
    await tester.tap(find.text('1：古诗二首'));
    await tester.pumpAndSettle();
    expect(selected, 7);
    expect(find.byType(TextbookTocDrawer), findsNothing);
  });

  testWidgets('明确区分未定位条目，已定位章节可跳转且无原目录入口', (tester) async {
    int? selected;
    await open(
      tester,
      (_) => Stream.value(_ready(_result)),
      selected: (value) => selected = value,
    );
    expect(find.text('部分条目暂未定位页码'), findsOneWidget);
    final unresolved = tester
        .widget<AppTile>(find.byKey(const ValueKey('textbook-toc-entry-1')));
    expect(unresolved.onTap, isNull);
    expect(find.text('查看原目录'), findsNothing);
    await tester.tap(find.text('已定位章节'));
    await tester.pumpAndSettle();
    expect(selected, 9);
  });

  testWidgets('进度可见，点击空白关闭取消读取，无迟到更新', (tester) async {
    var cancelled = false;
    final stream =
        StreamController<TextbookTocProgress>(onCancel: () => cancelled = true);
    stream.add(
      const TextbookTocProgress(
        phase: TextbookTocPhase.locating,
        scanned: 0,
        total: 20,
      ),
    );
    await open(tester, (_) => stream.stream);
    stream.add(
      const TextbookTocProgress(
        phase: TextbookTocPhase.locating,
        scanned: 3,
        total: 20,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在查找目录 3 / 20 页'), findsOneWidget);
    stream.add(
      const TextbookTocProgress(
        phase: TextbookTocPhase.resolving,
        scanned: 8,
        total: 20,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在校准页码 8 / 20 页'), findsOneWidget);
    await tester.tapAt(
      Offset(
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 1,
        1,
      ),
    );
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    stream.add(_ready(_result));
    unawaited(stream.close());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('识别错误可重试，无文字和无目录有不同状态，支持大字短屏', (tester) async {
    tester.view.physicalSize = const Size(360, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final refreshes = <bool>[];
    await open(
      tester,
      (refresh) {
        refreshes.add(refresh);
        return refresh
            ? Stream.value(
                _ready(
                  const TextbookTocResult(
                    entries: [],
                    source: TextbookTocSource.text,
                    hasText: false,
                  ),
                ),
              )
            : Stream.error(StateError('暂时不可读'));
      },
      large: true,
    );
    expect(find.text('目录识别未完成，请重试'), findsOneWidget);
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(refreshes, [false, true]);
    expect(find.text('这本书暂无可识别的文字目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(
      Offset(
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 1,
        1,
      ),
    );
    await tester.pumpAndSettle();
    await open(
      tester,
      (_) => Stream.value(
        _ready(
          const TextbookTocResult(
            entries: [],
            source: TextbookTocSource.text,
          ),
        ),
      ),
    );
    expect(find.text('未识别到可用目录'), findsOneWidget);
  });
}
