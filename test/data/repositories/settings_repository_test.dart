// test/data/repositories/settings_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  late SettingsRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    repo = SettingsRepository();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  group('SettingsRepository', () {
    group('themeMode', () {
      test('默认值为 system', () {
        expect(repo.themeMode, 'system');
      });

      test('setThemeMode 保存并读取', () async {
        await repo.setThemeMode('dark');
        expect(repo.themeMode, 'dark');

        await repo.setThemeMode('light');
        expect(repo.themeMode, 'light');
      });
    });

    group('soundEnabled', () {
      test('默认值为 true', () {
        expect(repo.soundEnabled, isTrue);
      });

      test('setSoundEnabled 保存并读取', () async {
        await repo.setSoundEnabled(false);
        expect(repo.soundEnabled, isFalse);
      });
    });

    group('hapticEnabled', () {
      test('默认值为 true', () {
        expect(repo.hapticEnabled, isTrue);
      });

      test('setHapticEnabled 保存并读取', () async {
        await repo.setHapticEnabled(false);
        expect(repo.hapticEnabled, isFalse);
      });
    });

    group('selectedGrade', () {
      test('默认值为 1', () {
        expect(repo.selectedGrade, 1);
      });

      test('setSelectedGrade 保存并读取', () async {
        await repo.setSelectedGrade(3);
        expect(repo.selectedGrade, 3);
      });
    });

    group('ttsSpeed', () {
      test('默认值为 0.5', () {
        expect(repo.ttsSpeed, 0.5);
      });

      test('setTtsSpeed 保存并读取', () async {
        await repo.setTtsSpeed(0.8);
        expect(repo.ttsSpeed, 0.8);
      });
    });

    group('pinyinVisible', () {
      test('默认值为 true', () {
        expect(repo.pinyinVisible, isTrue);
      });

      test('setPinyinVisible 保存并读取', () async {
        await repo.setPinyinVisible(false);
        expect(repo.pinyinVisible, isFalse);
      });
    });

    group('AI 讲解提示词覆盖', () {
      test('poemExplainPromptOverride 默认 null（未自定义）', () {
        expect(repo.poemExplainPromptOverride, isNull);
      });

      test('mathExplainPromptOverride 默认 null（未自定义）', () {
        expect(repo.mathExplainPromptOverride, isNull);
      });

      test('setPoemExplainPrompt 保存后读取 roundtrip（trim 保留）', () async {
        await repo.setPoemExplainPrompt('  自定义诗词提示  ');
        expect(repo.poemExplainPromptOverride, '自定义诗词提示');
        expect(
          HiveBoxes.settings.get('llm_poem_explain_prompt'),
          '自定义诗词提示',
        );
      });

      test('setMathExplainPrompt 保存后读取 roundtrip（trim 保留）', () async {
        await repo.setMathExplainPrompt('自定义口算提示');
        expect(repo.mathExplainPromptOverride, '自定义口算提示');
        expect(
          HiveBoxes.settings.get('llm_math_explain_prompt'),
          '自定义口算提示',
        );
      });

      test('set 空串 / 纯空白 = 删 key（恢复默认）', () async {
        await repo.setPoemExplainPrompt('先有自定义');
        await repo.setPoemExplainPrompt('   ');
        expect(repo.poemExplainPromptOverride, isNull);
        expect(HiveBoxes.settings.get('llm_poem_explain_prompt'), isNull);
      });

      test('reset 删除覆盖 key，getter 回落 null', () async {
        await repo.setMathExplainPrompt('先有自定义');
        await repo.resetMathExplainPrompt();
        expect(repo.mathExplainPromptOverride, isNull);
        expect(HiveBoxes.settings.get('llm_math_explain_prompt'), isNull);
      });

      test('历史脏数据：空串防御性读作 null', () async {
        await HiveBoxes.settings.put('llm_poem_explain_prompt', '');
        expect(repo.poemExplainPromptOverride, isNull);
        // 脏数据不被清除（getter 只做读取防御），但语义上视为未自定义。
      });

      test('assistantPromptOverride 默认 null（未自定义）', () {
        expect(repo.assistantPromptOverride, isNull);
      });

      test('setAssistantPrompt 保存后读取 roundtrip（trim 保留）', () async {
        await repo.setAssistantPrompt('  我的助手人设  ');
        expect(repo.assistantPromptOverride, '我的助手人设');
        expect(
          HiveBoxes.settings.get('llm_assistant_prompt'),
          '我的助手人设',
        );
      });

      test('setAssistantPrompt 空串 / 纯空白 = 删 key（恢复默认）', () async {
        await repo.setAssistantPrompt('先有自定义');
        await repo.setAssistantPrompt('   ');
        expect(repo.assistantPromptOverride, isNull);
        expect(HiveBoxes.settings.get('llm_assistant_prompt'), isNull);
      });

      test('resetAssistantPrompt 删除覆盖 key，getter 回落 null', () async {
        await repo.setAssistantPrompt('先有自定义');
        await repo.resetAssistantPrompt();
        expect(repo.assistantPromptOverride, isNull);
        expect(HiveBoxes.settings.get('llm_assistant_prompt'), isNull);
      });
    });

    // 悬浮球坐标（设备绑定：随屏幕尺寸失效，不入备份白名单）。
    group('assistantBubble 位置', () {
      test('无存档时 dx/dy 为 null', () {
        expect(repo.assistantBubbleDx, isNull);
        expect(repo.assistantBubbleDy, isNull);
      });

      test('set 后读取 roundtrip（落到约定 key）', () async {
        await repo.setAssistantBubbleDx(12.5);
        await repo.setAssistantBubbleDy(340.75);

        expect(repo.assistantBubbleDx, 12.5);
        expect(repo.assistantBubbleDy, 340.75);
        expect(HiveBoxes.settings.get('assistant_bubble_dx'), 12.5);
        expect(HiveBoxes.settings.get('assistant_bubble_dy'), 340.75);
      });

      test('重复写入取最新值', () async {
        await repo.setAssistantBubbleDx(10);
        await repo.setAssistantBubbleDx(99.5);
        expect(repo.assistantBubbleDx, 99.5);
      });

      test('整数存值经 num 转 double 读出', () async {
        await HiveBoxes.settings.put('assistant_bubble_dy', 8);
        expect(repo.assistantBubbleDy, 8.0);
      });
    });
  });
}
