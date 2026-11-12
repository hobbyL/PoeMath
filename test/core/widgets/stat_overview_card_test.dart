// test/core/widgets/stat_overview_card_test.dart
//
// 统计概览卡组件测试：渲染全部统计项的数值与标签。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/widgets/stat_overview_card.dart';

void main() {
  testWidgets('StatOverviewCard 渲染全部统计项的数值与标签', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatOverviewCard(
            items: [
              StatOverviewItem(value: '12', label: '已做题'),
              StatOverviewItem(value: '85%', label: '正确率'),
              StatOverviewItem(value: '3', label: '错题'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final value in ['12', '85%', '3']) {
      expect(find.text(value), findsOneWidget);
    }
    for (final label in ['已做题', '正确率', '错题']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('窄屏双倍字号保留长数值和标签且不横向溢出', (tester) async {
    const size = Size(320, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: StatOverviewCard(
                items: [
                  StatOverviewItem(value: '12345', label: '已学诗词'),
                  StatOverviewItem(value: '23456', label: '数学做题'),
                  StatOverviewItem(value: '7890', label: '总星星'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final text in ['12345', '23456', '7890', '已学诗词', '数学做题', '总星星']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
      tester.getRect(find.byType(StatOverviewCard)).right,
      lessThanOrEqualTo(size.width - 16),
    );
  });
}
