import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_dialog.dart';

import '../../helpers/textbook_page_number_fixture.dart';

void main() {
  int? selected;
  Future<void> open(
    WidgetTester tester,
    TextbookPageNumberService? service, {
    int page = 7,
    int pageCount = 8,
    bool large = false,
  }) async {
    selected = null;
    await tester.pumpWidget(
      MaterialApp(
        builder: large
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 140),
                ),
                child: child!,
              )
            : null,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<int>(
                  context: context,
                  builder: (_) => TextbookPageDialog(
                    page: page,
                    pageCount: pageCount,
                    pageNumbers: service,
                  ),
                );
              },
              child: const Text('打开跳页'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开跳页'));
    await tester.pumpAndSettle();
  }

  testWidgets('默认预填实际书页，输入 2 返回 PDF 7', (tester) async {
    final service = pageNumberFixture(pageCount: 8, pages: {6: 1, 7: 2, 8: 3});
    await service.page(7);
    await open(tester, service);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '书页')).selected,
      isTrue,
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '2',
    );
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(selected, 7);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('书页超过 PDF 总数仍能定位，PDF 模式按物理页校验', (tester) async {
    final service = pageNumberFixture(pageCount: 3, pages: {2: 150, 3: 151});
    await open(tester, service, page: 2, pageCount: 3);
    await tester.enterText(find.byType(TextFormField), '150');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    await open(tester, service, page: 2, pageCount: 3);
    await tester.tap(find.text('PDF 页'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '2',
    );
    await tester.enterText(find.byType(TextFormField), '150');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('请填写有效页码'), findsOneWidget);
    expect(selected, isNull);
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(selected, 3);
  });

  testWidgets('部分索引不把首次命中视为唯一，重复书页明确选择', (tester) async {
    final service = pageNumberFixture(pageCount: 8, pages: {2: 1, 6: 1});
    await service.page(2);
    await open(tester, service, page: 2);
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('PDF 第 2 页'), findsOneWidget);
    expect(find.text('PDF 第 6 页'), findsOneWidget);
    await tester.tap(find.text('PDF 第 6 页'));
    await tester.pumpAndSettle();
    expect(selected, 6);
  });

  testWidgets('未找到书页保留弹窗并允许明确 PDF 备用跳转', (tester) async {
    await open(tester, pageNumberFixture(pageCount: 8, pages: {}));
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到书页 2，可使用 PDF 页'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.text('PDF 页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(selected, 7);
  });

  testWidgets('提取失败可重试，同步加载错误不会变成未编号', (tester) async {
    var fail = true;
    final service = TextbookPageNumberService(
      pageCount: 8,
      loadPage: (number) {
        if (fail) throw StateError('暂时读取失败');
        return Future.value(printedPageFixture(number, number == 7 ? 2 : null));
      },
    );
    await open(tester, service);
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('书页码读取失败，请重试或使用 PDF 页'), findsOneWidget);
    expect(service.numbers.pages, isEmpty);
    fail = false;
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(selected, 7);
  });

  testWidgets('扫描中切 PDF 模式可立即跳页，迟到结果不能再次导航', (tester) async {
    final pending = Completer<TextbookPageText>();
    final requested = <int>[];
    final service = TextbookPageNumberService(
      pageCount: 8,
      loadPage: (number) {
        requested.add(number);
        return pending.future;
      },
    );
    await open(tester, service);
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('跳转'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('PDF 页'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '4');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(selected, 4);
    pending.complete(printedPageFixture(1, null));
    await tester.pumpAndSettle();
    expect(requested, [1]);
    expect(selected, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字与键盘下能切换、校验和取消', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, null, large: true);
    await tester.ensureVisible(find.text('PDF 页'));
    await tester.tap(find.text('PDF 页'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('请填写有效页码'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
