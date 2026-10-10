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
}
