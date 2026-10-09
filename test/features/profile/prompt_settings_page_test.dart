// test/features/profile/prompt_settings_page_test.dart
//
// AI 讲解提示词设置页 widget 测试：初始展示内置默认全文、编辑保存落
// Hive、清空保存 = 恢复默认、超 2000 字拒绝、恢复默认确认弹层先展示
// 默认全文再确认、已是默认时恢复按钮禁用。
//
// Hive 写链 tap 须在 runAsync 真实异步区执行（本仓既有结论）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/prompts/explain_prompt_defaults.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/prompt_settings_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 提示词长度上限（与页面常量一致；断言用「恰好 +1」边界）。
const int _maxLength = 2000;

/// 测试环境无平台安全存储通道，覆写为内存实现。
/// 页面本体不触凭据，但 settingsRepositoryProvider watch 它，须可构造。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> keys = {};

  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {
    keys[configId] = apiKey;
  }

  @override
  Future<String?> readLlmApiKeyFor(String configId) =>
      Future.value(keys[configId]);

  @override
  Future<void> deleteLlmApiKeyFor(String configId) async {
    keys.remove(configId);
  }

  @override
  Future<String?> readLlmApiKey() => Future.value(null);
}

Future<void> _pumpPage(WidgetTester tester) async {
  // 两区块多行编辑框内容较长，放大视口避免懒挂载与 tap 越界。
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(
          _MemoryCredentialStore(),
        ),
      ],
      child: const MaterialApp(home: PromptSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Hive 写链 tap：runAsync 真实异步区内触发并留足真实时间。
Future<void> _tapReal(
  WidgetTester tester,
  Finder finder, {
  Duration delay = const Duration(milliseconds: 150),
}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(delay);
  });
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// 定位某场景区块（按区块标题）内带 [buttonLabel] 文案的按钮。
/// 不限定按钮类型（保存是 FilledButton，恢复默认是 TextButton），
/// 直接匹配区块内文本。
Finder _sectionButton(String sectionTitle, String buttonLabel) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(sectionTitle),
      matching: find.byType(ColoredCard),
    ),
    matching: find.text(buttonLabel),
  );
}

/// 取第 [index] 个 TextField 的当前文本（0 = 诗词，1 = 口算）。
String _fieldText(WidgetTester tester, int index) {
  final field = tester.widget<TextField>(find.byType(TextField).at(index));
  return field.controller?.text ?? '';
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('未自定义时：两区块展示内置默认全文与「内置默认」标注',
      (tester) async {
    await _pumpPage(tester);

    expect(find.text('诗词讲解'), findsOneWidget);
    expect(find.text('口算解析'), findsOneWidget);
    expect(find.text('内置默认'), findsNWidgets(2));
    expect(find.text('已自定义'), findsNothing);

    expect(_fieldText(tester, 0), kPoemExplainSystemPrompt);
    expect(_fieldText(tester, 1), kMathExplainSystemPrompt);
  });

  testWidgets('已有自定义时：标注「已自定义」且编辑框展示覆盖值',
      (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_poem_explain_prompt', '我的诗词风格');
    });
    await _pumpPage(tester);

    expect(find.text('已自定义'), findsOneWidget);
    expect(find.text('内置默认'), findsOneWidget);
    expect(_fieldText(tester, 0), '我的诗词风格');
    expect(_fieldText(tester, 1), kMathExplainSystemPrompt);
  });

  testWidgets('编辑诗词提示词保存：落 Hive 且标注变「已自定义」',
      (tester) async {
    await _pumpPage(tester);

    await tester.enterText(find.byType(TextField).first, '新诗词提示');
    await _tapReal(tester, _sectionButton('诗词讲解', '保存'));

    expect(
      HiveBoxes.settings.get('llm_poem_explain_prompt'),
      '新诗词提示',
    );
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('已自定义'), findsOneWidget);
    // 口算侧不受影响。
    expect(
      HiveBoxes.settings.get('llm_math_explain_prompt'),
      isNull,
    );

    // SnackBar 消退后排空异步链。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('清空保存 = 恢复默认：删 key、标注回「内置默认」、框回默认全文',
      (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_math_explain_prompt', '我的口算风格');
    });
    await _pumpPage(tester);
    expect(find.text('已自定义'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '   ');
    await _tapReal(tester, _sectionButton('口算解析', '保存'));

    expect(HiveBoxes.settings.get('llm_math_explain_prompt'), isNull);
    expect(find.text('内置默认'), findsNWidgets(2));
    expect(find.text('已恢复默认'), findsOneWidget);
    expect(_fieldText(tester, 1), kMathExplainSystemPrompt);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('超过 2000 字拒绝保存：不落盘且 SnackBar 提示', (tester) async {
    await _pumpPage(tester);

    final tooLong = '超' * (_maxLength + 1);
    await tester.enterText(find.byType(TextField).first, tooLong);
    await _tapReal(tester, _sectionButton('诗词讲解', '保存'));

    expect(HiveBoxes.settings.get('llm_poem_explain_prompt'), isNull);
    expect(find.text('提示词超长，已取消保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('恢复默认：确认弹层先展示默认全文，确认后删 key 回默认',
      (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_poem_explain_prompt', '改坏了的风格');
    });
    await _pumpPage(tester);

    // 打开弹层也须在真实异步区 tap：_reset 协程从这次 tap 启动，
    // `await showDialog` 的续体（含 Hive 删除）继承该区。若在 fake 区
    // 启动，Hive 写队列会被 fake 区微任务拦截（fake_async 拦截
    // scheduleMicrotask），box.close() 在 tearDown 永久挂起。
    await _tapReal(tester, _sectionButton('诗词讲解', '恢复默认'));

    // 弹层先只读展示内置默认全文，用户决定前可先看原来是什么样。
    expect(
      find.text('内置默认提示词如下，确认后将替换当前内容：'),
      findsOneWidget,
    );
    expect(find.text(kPoemExplainSystemPrompt), findsOneWidget);
    // 当前自定义值不出现在弹层中（编辑框自身内容不算）。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('改坏了的风格'),
      ),
      findsNothing,
    );

    // 确认恢复：与保存路径同构（tap 同步触发 Navigator.pop → 真实区内
    // showDialog 续体执行 Hive 删除并完整落盘）。
    await _tapReal(tester, find.widgetWithText(FilledButton, '恢复默认'));

    expect(HiveBoxes.settings.get('llm_poem_explain_prompt'), isNull);
    expect(find.text('内置默认'), findsNWidgets(2));
    expect(_fieldText(tester, 0), kPoemExplainSystemPrompt);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('恢复默认弹层可取消：key 与编辑框保持自定义值', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_poem_explain_prompt', '我的诗词风格');
    });
    await _pumpPage(tester);

    await tester.tap(_sectionButton('诗词讲解', '恢复默认'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      HiveBoxes.settings.get('llm_poem_explain_prompt'),
      '我的诗词风格',
    );
    expect(_fieldText(tester, 0), '我的诗词风格');
    expect(find.text('已自定义'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('已是默认时恢复按钮禁用：点击不弹确认层', (tester) async {
    await _pumpPage(tester);

    final resetBtn = _sectionButton('诗词讲解', '恢复默认');
    // 恢复默认是 TextButton.icon：已是默认态时 onPressed 为 null。
    final resetButtonWidget = tester.widget<TextButton>(
      find.ancestor(
        of: resetBtn,
        matching: find.byType(TextButton),
      ),
    );
    expect(resetButtonWidget.onPressed, isNull);

    await _tapReal(tester, resetBtn);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('内置默认提示词如下，确认后将替换当前内容：'),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 2));
  });
}
