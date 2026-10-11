// test/features/assistant/widgets/tool_message_card_test.dart
//
// ToolMessageCard 组件测试：默认折叠（只露标题、藏明细）、点击展开/再点收起，
// 以及工具名 → 中文标签映射。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/assistant/widgets/tool_message_card.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('默认折叠：显示标题与工具图标，明细不可见', (tester) async {
    await _pump(
      tester,
      const ToolMessageCard(title: '工具结果：讲解错题', detail: '题目：25 + 38 = ?'),
    );

    expect(find.text('工具结果：讲解错题'), findsOneWidget);
    expect(find.byIcon(Icons.build_outlined), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget); // 折叠指示
    expect(find.text('题目：25 + 38 = ?'), findsNothing); // 明细隐藏
  });

  testWidgets('点击展开后显示明细，再次点击收起', (tester) async {
    await _pump(
      tester,
      const ToolMessageCard(title: '工具结果：讲解错题', detail: '题目：25 + 38 = ?'),
    );

    await tester.tap(find.text('工具结果：讲解错题'));
    await tester.pumpAndSettle();
    expect(find.text('题目：25 + 38 = ?'), findsOneWidget); // 展开可见
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pumpAndSettle();
    expect(find.text('题目：25 + 38 = ?'), findsNothing); // 收起再次隐藏
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });

  testWidgets('initiallyExpanded=true：初始即展开', (tester) async {
    await _pump(
      tester,
      const ToolMessageCard(
        title: '调用工具：出题',
        detail: '参数：{"grade":2}',
        initiallyExpanded: true,
      ),
    );

    expect(find.text('参数：{"grade":2}'), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
  });

  test('toolDisplayName：已知工具名映射中文，未知名回退原样', () {
    expect(toolDisplayName('generate_word_problems'), '出题');
    expect(toolDisplayName('open_practice'), '打开练习');
    expect(toolDisplayName('explain_mistake'), '讲解错题');
    expect(toolDisplayName('unknown_tool'), 'unknown_tool');
  });
}
