import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  late SettingsRepository settings;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    settings = SettingsRepository();
    for (final id in ['a', 'b']) {
      await settings.saveLlmProviderConfig(
        id: id,
        name: id,
        baseUrl: 'https://$id.example.com/v1',
        model: 'gpt-4o',
        models: ['gpt-4o', 'gpt-4o-mini'],
        apiKey: '',
      );
    }
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('升级继承实际助手选择，之后助手修改不影响点评，主动跟随默认可持久化', () async {
    await settings.setScenarioSelection(
      LlmScenario.assistant,
      providerId: 'b',
      model: 'gpt-4o-mini',
    );
    await settings.migratePictureStoryFeedbackSelection();
    await settings.setScenarioSelection(
      LlmScenario.assistant,
      providerId: 'a',
      model: 'gpt-4o',
    );
    await settings.migratePictureStoryFeedbackSelection();
    final config = await settings.readLlmConfigForScenario(
      LlmScenario.pictureStoryFeedback,
    );
    expect(config!.selection!.providerId, 'b');
    expect(config.model, 'gpt-4o-mini');
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: null,
      model: null,
    );
    await settings.migratePictureStoryFeedbackSelection();
    expect(
      settings.providerIdForScenario(LlmScenario.pictureStoryFeedback),
      isNull,
    );
    expect(
      HiveBoxes.settings.get(LlmScenario.pictureStoryFeedback.settingsKey),
      '',
    );
  });

  test('独立提示词长度、重置与绑定随备份往返，默认标记不重新继承助手', () async {
    await settings.setPictureStoryFeedbackPrompt('先检查人物动作，再给建议');
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: 'b',
      model: 'gpt-4o-mini',
    );
    final backup = BackupService();
    final saved = await backup.exportToJson();
    expect(saved, contains('先检查人物动作，再给建议'));
    await settings.resetPictureStoryFeedbackPrompt();
    await backup.restoreFromJson(saved);
    expect(settings.pictureStoryFeedbackPromptOverride, '先检查人物动作，再给建议');
    expect(
      settings.providerIdForScenario(LlmScenario.pictureStoryFeedback),
      'b',
    );
    await expectLater(
      settings.setPictureStoryFeedbackPrompt('字' * 2001),
      throwsFormatException,
    );
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: null,
      model: null,
    );
    final defaults = await backup.exportToJson();
    expect(jsonDecode(defaults), isA<Map<String, dynamic>>());
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: 'b',
      model: 'gpt-4o',
    );
    await backup.restoreFromJson(defaults);
    await settings.migratePictureStoryFeedbackSelection();
    expect(
      settings.providerIdForScenario(LlmScenario.pictureStoryFeedback),
      isNull,
    );
  });

  test('删除点评供应商后跟随默认，不能重新继承助手绑定', () async {
    await settings.setScenarioSelection(
      LlmScenario.assistant,
      providerId: 'b',
      model: 'gpt-4o-mini',
    );
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: 'a',
      model: 'gpt-4o',
    );
    await settings.deleteLlmProviderConfig('a');
    await settings.migratePictureStoryFeedbackSelection();
    expect(
      settings.providerIdForScenario(LlmScenario.pictureStoryFeedback),
      isNull,
    );
    expect(
      HiveBoxes.settings.get(LlmScenario.pictureStoryFeedback.settingsKey),
      '',
    );
  });

  test('旧单供应商先完成迁移，点评绑定继承有效模型而非提前标记默认', () async {
    await HiveBoxes.settings.putAll({
      'llm_providers': '[]',
      'llm_base_url': 'https://legacy.example.com/v1',
      'llm_model': 'gpt-4o-mini',
      'llm_provider_name': '旧配置',
    });
    await settings.migratePictureStoryFeedbackSelection();
    final inherited = settings.providerIdForScenario(
      LlmScenario.pictureStoryFeedback,
    );
    expect(inherited, isNotNull);
    expect(inherited, settings.llmProviders.single.id);
    expect(
      settings.modelForScenario(LlmScenario.pictureStoryFeedback),
      'gpt-4o-mini',
    );
    await settings.saveLlmProviderConfig(
      id: 'new',
      name: 'new',
      baseUrl: 'https://new.example.com/v1',
      model: 'gpt-4o',
      apiKey: '',
    );
    await settings.setLlmActiveProvider('new');
    await settings.migratePictureStoryFeedbackSelection();
    expect(
      settings.providerIdForScenario(LlmScenario.pictureStoryFeedback),
      inherited,
    );
  });
}
