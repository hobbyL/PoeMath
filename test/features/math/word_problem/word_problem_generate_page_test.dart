// test/features/math/word_problem/word_problem_generate_page_test.dart
//
// 生成页 widget 测试：未配置 LLM 时显示引导态。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/math/word_problem/word_problem_generate_page.dart';

import '../../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('未配置 LLM 时显示引导态而非生成表单', (tester) async {
    // Hive settings 中无 llmBaseUrl/llmModel → readLlmConfig 返回 null。
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WordProblemGeneratePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未配置 AI 出题服务'), findsOneWidget);
    expect(find.text('去配置'), findsOneWidget);
    // 不显示生成表单
    expect(find.text('知识点'), findsNothing);
    expect(find.text('生成 5 题'), findsNothing);
  });
}
