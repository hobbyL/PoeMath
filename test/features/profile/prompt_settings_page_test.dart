// test/features/profile/prompt_settings_page_test.dart
//
// AI 提示词设置页 widget 测试：初始展示内置默认全文、编辑保存落 Hive、
// 清空保存 = 恢复默认、长度校验、恢复默认确认弹层先展示默认全文
// 再确认、已是默认时恢复按钮禁用，独立生图、出题与讲解、助手共用相同操作。
//
// Hive 写链 tap 须在 runAsync 真实异步区执行（本仓既有结论）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/prompts/assistant_prompt_defaults.dart';
import 'package:poemath/core/prompts/explain_prompt_defaults.dart';
import 'package:poemath/core/prompts/generation_prompt_defaults.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/prompt_settings_page.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

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

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(800, 2400),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(
          _MemoryCredentialStore(),
        ),
      ],
      child: MaterialApp(
        home: const PromptSettingsPage(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
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
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
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

/// 定位某场景区块内的编辑框。区块数量增加后，`find.byType(TextField).last`
/// 之类的序数定位会随区块顺序漂移，按标题定位才对新增区块免疫。
Finder _sectionField(String sectionTitle) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(sectionTitle),
      matching: find.byType(ColoredCard),
    ),
    matching: find.byType(TextField),
  );
}

/// 按场景标题读取当前文本，场景增减不会改变定位。
String _fieldText(WidgetTester tester, String title) {
  final field = tester.widget<TextField>(_sectionField(title));
  return field.controller?.text ?? '';
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
  });

  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  testWidgets('未自定义时：六个场景展示内置默认全文与「内置默认」标注', (tester) async {
    await _pumpPage(tester);

    expect(find.text('AI 生成应用题'), findsOneWidget);
    expect(find.text('看图说话生图'), findsOneWidget);
    expect(find.text('根据图片出题'), findsOneWidget);
    expect(_fieldText(tester, 'AI 生成应用题'), kWordProblemGenerationSystemPrompt);
    expect(
      _fieldText(tester, '看图说话生图'),
      kPictureStoryImageGenerationSystemPrompt,
    );
    expect(
      _fieldText(tester, '根据图片出题'),
      kPictureStoryQuestionGenerationSystemPrompt,
    );
    expect(find.text('诗词讲解'), findsOneWidget);
    expect(find.text('口算解析'), findsOneWidget);
    expect(find.text('AI 助手人设'), findsOneWidget);
    expect(find.text('内置默认'), findsNWidgets(6));
    expect(find.text('已自定义'), findsNothing);

    expect(_fieldText(tester, '诗词讲解'), kPoemExplainSystemPrompt);
    expect(_fieldText(tester, '口算解析'), kMathExplainSystemPrompt);
  });

  testWidgets('已有自定义时：标注「已自定义」且编辑框展示覆盖值', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_poem_explain_prompt', '我的诗词风格');
    });
    await _pumpPage(tester);

    expect(find.text('已自定义'), findsOneWidget);
    expect(find.text('内置默认'), findsNWidgets(5));
    expect(_fieldText(tester, '诗词讲解'), '我的诗词风格');
    expect(_fieldText(tester, '口算解析'), kMathExplainSystemPrompt);
    expect(_fieldText(tester, 'AI 助手人设'), kAssistantSystemPrompt);
  });

  testWidgets('编辑诗词提示词保存：落 Hive 且标注变「已自定义」', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(_sectionField('诗词讲解'), '新诗词提示');
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

  testWidgets('清空保存 = 恢复默认：删 key、标注回「内置默认」、框回默认全文', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_math_explain_prompt', '我的口算风格');
    });
    await _pumpPage(tester);
    expect(find.text('已自定义'), findsOneWidget);

    await tester.enterText(_sectionField('口算解析'), '   ');
    await _tapReal(tester, _sectionButton('口算解析', '保存'));

    expect(HiveBoxes.settings.get('llm_math_explain_prompt'), isNull);
    expect(find.text('内置默认'), findsNWidgets(6));
    expect(find.text('已恢复默认'), findsOneWidget);
    expect(_fieldText(tester, '口算解析'), kMathExplainSystemPrompt);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('超过 2000 字拒绝保存：不落盘且 SnackBar 提示', (tester) async {
    await _pumpPage(tester);

    final tooLong = '超' * (_maxLength + 1);
    await tester.enterText(_sectionField('诗词讲解'), tooLong);
    await _tapReal(tester, _sectionButton('诗词讲解', '保存'));

    expect(HiveBoxes.settings.get('llm_poem_explain_prompt'), isNull);
    expect(find.text('诗词讲解提示词超长，已取消保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('恢复默认：确认弹层先展示默认全文，确认后删 key 回默认', (tester) async {
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
    expect(find.text('内置默认'), findsNWidgets(6));
    expect(_fieldText(tester, '诗词讲解'), kPoemExplainSystemPrompt);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('恢复默认弹层可取消：key 与编辑框保持自定义值', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_poem_explain_prompt', '我的诗词风格');
    });
    await _pumpPage(tester);

    await _tapReal(tester, _sectionButton('诗词讲解', '恢复默认'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      HiveBoxes.settings.get('llm_poem_explain_prompt'),
      '我的诗词风格',
    );
    expect(_fieldText(tester, '诗词讲解'), '我的诗词风格');
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

  for (final (title, key, defaultText, maxLength, keepsMarker) in [
    (
      'AI 生成应用题',
      'llm_word_problem_prompt',
      kWordProblemGenerationSystemPrompt,
      _maxLength,
      false
    ),
    (
      '看图说话生图',
      'llm_picture_story_image_prompt',
      kPictureStoryImageGenerationSystemPrompt,
      kPictureStoryImagePromptMaxLength,
      true
    ),
    (
      '根据图片出题',
      'llm_picture_story_question_prompt',
      kPictureStoryQuestionGenerationSystemPrompt,
      kPictureStoryQuestionPromptMaxLength,
      true
    ),
  ]) {
    testWidgets('$title：保存后重新进入保留内容，取消恢复不改写，确认和清空均恢复默认', (tester) async {
      await _pumpPage(tester);
      await tester.enterText(_sectionField(title), '  我的出题偏好  ');
      await _tapReal(tester, _sectionButton(title, '保存'));
      expect(HiveBoxes.settings.get(key), '我的出题偏好');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpPage(tester);
      expect(_fieldText(tester, title), '我的出题偏好');
      await _tapReal(tester, _sectionButton(title, '恢复默认'));
      expect(find.text(defaultText), findsOneWidget);
      await _tapReal(tester, find.widgetWithText(TextButton, '取消'));
      expect(HiveBoxes.settings.get(key), '我的出题偏好');
      expect(_fieldText(tester, title), '我的出题偏好');

      await _tapReal(tester, _sectionButton(title, '恢复默认'));
      await _tapReal(tester, find.widgetWithText(FilledButton, '恢复默认'));
      expect(HiveBoxes.settings.containsKey(key), keepsMarker);
      expect(HiveBoxes.settings.get(key), keepsMarker ? '' : null);
      expect(_fieldText(tester, title), defaultText);
      await tester.enterText(_sectionField(title), '再次自定义');
      await _tapReal(tester, _sectionButton(title, '保存'));
      await tester.enterText(_sectionField(title), '   ');
      await _tapReal(tester, _sectionButton(title, '保存'));
      expect(HiveBoxes.settings.containsKey(key), keepsMarker);
      expect(HiveBoxes.settings.get(key), keepsMarker ? '' : null);
      expect(_fieldText(tester, title), defaultText);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('$title：超过该场景长度上限不保存', (tester) async {
      await _pumpPage(tester);
      await tester.enterText(_sectionField(title), '超' * (maxLength + 1));
      await _tapReal(tester, _sectionButton(title, '保存'));
      expect(HiveBoxes.settings.containsKey(key), isFalse);
      expect(find.text('$title提示词超长，已取消保存'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('旧教学偏好下两项分别编辑和恢复默认，重开后互不覆盖', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_picture_story_prompt', '采用短句表达');
    });
    await _pumpPage(tester);
    final originalImage = _fieldText(tester, '看图说话生图');
    expect(originalImage, contains('平面手绘儿童教材插图'));
    expect(originalImage, endsWith('采用短句表达'));
    expect(_fieldText(tester, '根据图片出题'), '采用短句表达');
    await tester.enterText(_sectionField('根据图片出题'), '三个观察问题');
    await _tapReal(tester, _sectionButton('根据图片出题', '保存'));
    expect(
      HiveBoxes.settings.get('llm_picture_story_question_prompt'),
      '三个观察问题',
    );
    expect(_fieldText(tester, '看图说话生图'), originalImage);
    await _tapReal(tester, _sectionButton('根据图片出题', '恢复默认'));
    await _tapReal(tester, find.widgetWithText(FilledButton, '恢复默认'));
    expect(
      _fieldText(tester, '根据图片出题'),
      kPictureStoryQuestionGenerationSystemPrompt,
    );
    expect(_fieldText(tester, '看图说话生图'), originalImage);
    await tester.enterText(_sectionField('看图说话生图'), '水彩人物互动');
    await _tapReal(tester, _sectionButton('看图说话生图', '保存'));
    expect(HiveBoxes.settings.get('llm_picture_story_image_prompt'), '水彩人物互动');
    expect(
      _fieldText(tester, '根据图片出题'),
      kPictureStoryQuestionGenerationSystemPrompt,
    );
    await tester.enterText(_sectionField('看图说话生图'), '  ');
    await _tapReal(tester, _sectionButton('看图说话生图', '保存'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpPage(tester);
    expect(
      _fieldText(tester, '看图说话生图'),
      kPictureStoryImageGenerationSystemPrompt,
    );
    expect(
      _fieldText(tester, '根据图片出题'),
      kPictureStoryQuestionGenerationSystemPrompt,
    );
    expect(HiveBoxes.settings.get('llm_picture_story_prompt'), '采用短句表达');
    expect(HiveBoxes.settings.get('llm_picture_story_image_prompt'), '');
    expect(HiveBoxes.settings.get('llm_picture_story_question_prompt'), '');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('六个场景在小屏大字号下均可滚动到编辑和操作按钮，无布局溢出', (tester) async {
    await _pumpPage(tester, size: const Size(320, 900), scale: 2);
    for (final title in [
      'AI 生成应用题',
      '看图说话生图',
      '根据图片出题',
      '诗词讲解',
      '口算解析',
      'AI 助手人设',
    ]) {
      await tester.ensureVisible(_sectionField(title));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_sectionButton(title, '保存'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('助手人设区块：编辑保存落 llm_assistant_prompt 键', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(_sectionField('AI 助手人设'), '你是韵算小助手');
    await _tapReal(tester, _sectionButton('AI 助手人设', '保存'));

    expect(HiveBoxes.settings.get('llm_assistant_prompt'), '你是韵算小助手');
    expect(find.text('已保存'), findsOneWidget);
    // 另两区块不受影响。
    expect(HiveBoxes.settings.get('llm_poem_explain_prompt'), isNull);
    expect(HiveBoxes.settings.get('llm_math_explain_prompt'), isNull);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('助手人设区块：已有覆盖值时展示覆盖值并标注「已自定义」', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_assistant_prompt', '你是严格老师');
    });
    await _pumpPage(tester);

    expect(_fieldText(tester, 'AI 助手人设'), '你是严格老师');
    expect(find.text('已自定义'), findsOneWidget);
    expect(find.text('内置默认'), findsNWidgets(5));
  });

  testWidgets('助手人设区块：清空保存 = 恢复默认，框回 kAssistantSystemPrompt', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_assistant_prompt', '你是严格老师');
    });
    await _pumpPage(tester);

    await tester.enterText(_sectionField('AI 助手人设'), '');
    await _tapReal(tester, _sectionButton('AI 助手人设', '保存'));

    expect(HiveBoxes.settings.get('llm_assistant_prompt'), isNull);
    expect(_fieldText(tester, 'AI 助手人设'), kAssistantSystemPrompt);
    expect(find.text('内置默认'), findsNWidgets(6));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('助手人设区块：恢复默认确认后删 key 回内置默认全文', (tester) async {
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_assistant_prompt', '改坏了的助手人设');
    });
    await _pumpPage(tester);

    await _tapReal(tester, _sectionButton('AI 助手人设', '恢复默认'));
    expect(find.text('恢复助手人设默认'), findsOneWidget);
    expect(find.text(kAssistantSystemPrompt), findsOneWidget);

    await _tapReal(tester, find.widgetWithText(FilledButton, '恢复默认'));

    expect(HiveBoxes.settings.get('llm_assistant_prompt'), isNull);
    expect(_fieldText(tester, 'AI 助手人设'), kAssistantSystemPrompt);

    await tester.pump(const Duration(seconds: 5));
  });
}
