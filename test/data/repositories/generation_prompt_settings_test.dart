import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsRepository settings;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    settings = SettingsRepository();
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('两种出题提示词独立保存，空白保存和重置删除覆盖而不写入默认副本', () async {
    expect(settings.wordProblemGenerationPromptOverride, isNull);
    expect(settings.pictureStoryGenerationPromptOverride, isNull);
    await settings.setWordProblemGenerationPrompt('  优先选择自然观察情境  ');
    await settings.setPictureStoryGenerationPrompt('  引导先观察再表达  ');
    expect(settings.wordProblemGenerationPromptOverride, '优先选择自然观察情境');
    expect(settings.pictureStoryGenerationPromptOverride, '引导先观察再表达');
    await settings.setWordProblemGenerationPrompt('   ');
    expect(HiveBoxes.settings.containsKey('llm_word_problem_prompt'), isFalse);
    expect(settings.pictureStoryGenerationPromptOverride, '引导先观察再表达');
    await settings.resetPictureStoryGenerationPrompt();
    expect(HiveBoxes.settings.containsKey('llm_picture_story_prompt'), isFalse);
    expect(settings.pictureStoryGenerationPromptOverride, isNull);
  });

  test('坏类型和历史空白提示词只读回落，不改写原始设置', () async {
    await HiveBoxes.settings.put('llm_word_problem_prompt', 42);
    await HiveBoxes.settings.put('llm_picture_story_prompt', '  ');
    expect(settings.wordProblemGenerationPromptOverride, isNull);
    expect(settings.pictureStoryGenerationPromptOverride, isNull);
    expect(HiveBoxes.settings.get('llm_word_problem_prompt'), 42);
    expect(HiveBoxes.settings.get('llm_picture_story_prompt'), '  ');
  });

  test('未获家长授权时不能保存或重置任一出题提示词', () async {
    await settings.setWordProblemGenerationPrompt('原应用题偏好');
    await settings.setPictureStoryGenerationPrompt('原看图说话偏好');
    lockParentForTesting();
    for (final work in [
      () => settings.setWordProblemGenerationPrompt('新内容'),
      () => settings.resetWordProblemGenerationPrompt(),
      () => settings.setPictureStoryGenerationPrompt('新内容'),
      () => settings.resetPictureStoryGenerationPrompt(),
    ]) {
      await expectLater(work(), throwsA(isA<ParentAccessDenied>()));
    }
    expect(settings.wordProblemGenerationPromptOverride, '原应用题偏好');
    expect(settings.pictureStoryGenerationPromptOverride, '原看图说话偏好');
  });

  test('真实备份生产和恢复完整保留两种提示词，旧备份及坏类型不清除本机偏好', () async {
    await settings.setWordProblemGenerationPrompt('优先选择自然观察情境');
    await settings.setPictureStoryGenerationPrompt('引导先观察再表达');
    final backup = BackupService();
    final data = await backup.exportToJson();
    final exported = (jsonDecode(data) as Map<String, dynamic>)['settings']
        as Map<String, dynamic>;
    expect({
      for (final key in ['llm_word_problem_prompt', 'llm_picture_story_prompt'])
        key: exported[key],
    }, {
      'llm_word_problem_prompt': '优先选择自然观察情境',
      'llm_picture_story_prompt': '引导先观察再表达',
    });
    await settings.resetWordProblemGenerationPrompt();
    await settings.resetPictureStoryGenerationPrompt();
    await backup.restoreFromJson(data);
    expect(settings.wordProblemGenerationPromptOverride, '优先选择自然观察情境');
    expect(settings.pictureStoryGenerationPromptOverride, '引导先观察再表达');
    for (final values in [
      <String, Object>{},
      {'llm_word_problem_prompt': 1, 'llm_picture_story_prompt': false},
    ]) {
      await backup
          .restoreFromJson(jsonEncode({'version': 1, 'settings': values}));
      expect(settings.wordProblemGenerationPromptOverride, '优先选择自然观察情境');
      expect(settings.pictureStoryGenerationPromptOverride, '引导先观察再表达');
    }
  });

  test('看图说话提示词修改使生成配置签名失效，其他场景的修改不影响它', () async {
    final signature = settings.pictureStoryGenerationSignature;
    await settings.setWordProblemGenerationPrompt('只选小动物情境');
    expect(settings.pictureStoryGenerationSignature, signature);
    await settings.setPictureStoryGenerationPrompt('优先用儿童水彩画场景');
    expect(settings.pictureStoryGenerationSignature, isNot(signature));
    await settings.resetPictureStoryGenerationPrompt();
    expect(settings.pictureStoryGenerationSignature, signature);
  });
}
