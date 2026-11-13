import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_number_label.dart';

import '../../helpers/textbook_page_number_fixture.dart';

void main() {
  Widget label(TextbookPageNumberService service, int number) => MaterialApp(
    home: TextbookPageNumberLabel(
      service: service,
      pages: [number],
      builder: (_, text) => Text(text),
    ),
  );

  testWidgets('页面切换不沿用上一页标签，迟到结果和重建不串页', (tester) async {
    final first = Completer<TextbookPageText>();
    final second = Completer<TextbookPageText>();
    final loaded = <int>[];
    final service = TextbookPageNumberService(
      pageCount: 2,
      loadPage: (number) {
        loaded.add(number);
        return number == 1 ? first.future : second.future;
      },
    );
    await tester.pumpWidget(label(service, 1));
    expect(find.text('正在读取页码'), findsOneWidget);
    await tester.pumpWidget(label(service, 2));
    expect(find.text('正在读取页码'), findsOneWidget);
    first.complete(printedPageFixture(1, 30));
    await tester.pumpAndSettle();
    expect(find.text('第 30 页'), findsNothing);
    expect(find.text('正在读取页码'), findsOneWidget);
    second.complete(printedPageFixture(2, 31));
    await tester.pumpAndSettle();
    expect(find.text('第 31 页'), findsOneWidget);
    await tester.pumpWidget(label(service, 2));
    await tester.pumpAndSettle();
    expect(loaded, [1, 2]);
  });

  testWidgets('错误与完成无编号分开显示，离页后的未来结果不更新界面', (tester) async {
    final pending = Completer<TextbookPageText>();
    final service = TextbookPageNumberService(
      pageCount: 3,
      loadPage: (number) => number == 1
          ? Future.error(StateError('无法读取'))
          : number == 2
          ? Future.value(printedPageFixture(2, null))
          : pending.future,
    );
    await tester.pumpWidget(label(service, 1));
    await tester.pumpAndSettle();
    expect(find.text('页码读取失败'), findsOneWidget);
    await tester.pumpWidget(label(service, 2));
    await tester.pumpAndSettle();
    expect(find.text('未标页码'), findsOneWidget);
    await tester.pumpWidget(label(service, 3));
    expect(find.text('正在读取页码'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(printedPageFixture(3, 2));
    await tester.pumpAndSettle();
    expect(find.text('第 2 页'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
