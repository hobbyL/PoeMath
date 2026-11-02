import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late BackupService backup;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp('picture_story_prompts_');
    backup = BackupService(
      pictureStoryImages: PictureStoryImageService(
        directoryProvider: () async => directory,
      ),
    );
  });

  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  Future<String> payloadWithSettings(Map<String, dynamic> settings) async {
    final data = jsonDecode(
      await backup.exportToJson(includeCredentials: false),
    ) as Map<String, dynamic>;
    data['settings'] = settings;
    return jsonEncode(data);
  }

  test('旧共享教学偏好保留在两项中，生图仍含原有画风要求，读取不写入', () async {
    final legacy = '旧' * 2000;
    await HiveBoxes.settings.put('llm_picture_story_prompt', legacy);
    final settings = SettingsRepository();
    final imagePrompt = settings.pictureStoryImageGenerationPromptOverride!;
    expect(imagePrompt, contains('平面手绘儿童教材插图'));
    expect(imagePrompt, endsWith(legacy));
    expect(imagePrompt.runes.length, lessThanOrEqualTo(2800));
    expect(settings.pictureStoryQuestionGenerationPromptOverride, legacy);
    expect(HiveBoxes.settings.get('llm_picture_story_prompt'), legacy);
    expect(
      HiveBoxes.settings.containsKey('llm_picture_story_image_prompt'),
      isFalse,
    );
    expect(
      HiveBoxes.settings.containsKey('llm_picture_story_question_prompt'),
      isFalse,
    );
  });

  test('两项独立保存和恢复默认，重读后旧偏好不会覆盖已恢复的任一项', () async {
    var settings = SettingsRepository();
    await settings.setPictureStoryGenerationPrompt('原有教学要求');
    final originalImage = settings.pictureStoryImageGenerationPromptOverride;
    await settings.setPictureStoryQuestionGenerationPrompt('  出题要三个短问题  ');
    expect(settings.pictureStoryQuestionGenerationPromptOverride, '出题要三个短问题');
    expect(settings.pictureStoryImageGenerationPromptOverride, originalImage);
    await settings.resetPictureStoryQuestionGenerationPrompt();
    expect(settings.pictureStoryQuestionGenerationPromptOverride, isNull);
    expect(settings.pictureStoryImageGenerationPromptOverride, originalImage);
    await settings.setPictureStoryImageGenerationPrompt('  水彩人物互动  ');
    expect(settings.pictureStoryImageGenerationPromptOverride, '水彩人物互动');
    expect(settings.pictureStoryQuestionGenerationPromptOverride, isNull);
    await settings.resetPictureStoryImageGenerationPrompt();
    settings = SettingsRepository();
    expect(settings.pictureStoryImageGenerationPromptOverride, isNull);
    expect(settings.pictureStoryQuestionGenerationPromptOverride, isNull);
    expect(HiveBoxes.settings.get('llm_picture_story_image_prompt'), '');
    expect(HiveBoxes.settings.get('llm_picture_story_question_prompt'), '');
    expect(HiveBoxes.settings.get('llm_picture_story_prompt'), '原有教学要求');
  });

  test('生成配置签名分别响应生图和出题设置，独立设置后不受旧共享键改变影响', () async {
    final settings = SettingsRepository();
    final initial = settings.pictureStoryGenerationSignature;
    await settings.setPictureStoryImageGenerationPrompt('人物动作清楚');
    final imageChanged = settings.pictureStoryGenerationSignature;
    expect(imageChanged, isNot(initial));
    await settings.setPictureStoryQuestionGenerationPrompt('先观察再讲述');
    final questionChanged = settings.pictureStoryGenerationSignature;
    expect(questionChanged, isNot(imageChanged));
    await settings.setPictureStoryGenerationPrompt('旧共享键发生变化');
    expect(settings.pictureStoryGenerationSignature, questionChanged);
    await settings.resetPictureStoryImageGenerationPrompt();
    expect(settings.pictureStoryGenerationSignature, isNot(questionChanged));
  });

  test('仓储拒绝超长独立提示词，原始内容保持完整', () async {
    final settings = SettingsRepository();
    await settings.setPictureStoryImageGenerationPrompt('原图要求');
    await settings.setPictureStoryQuestionGenerationPrompt('原出题要求');
    await expectLater(
      settings.setPictureStoryImageGenerationPrompt('图' * 2801),
      throwsFormatException,
    );
    await expectLater(
      settings.setPictureStoryQuestionGenerationPrompt('题' * 2001),
      throwsFormatException,
    );
    expect(settings.pictureStoryImageGenerationPromptOverride, '原图要求');
    expect(settings.pictureStoryQuestionGenerationPromptOverride, '原出题要求');
  });

  test('备份往返保留独立提示词和显式默认，旧共享偏好不重新生效', () async {
    final settings = SettingsRepository();
    await settings.setPictureStoryGenerationPrompt('旧教学偏好');
    await settings.resetPictureStoryImageGenerationPrompt();
    await settings.setPictureStoryQuestionGenerationPrompt('观察人物的手势');
    final text = await backup.exportToJson(includeCredentials: false);
    final exported = (jsonDecode(text) as Map)['settings'] as Map;
    expect(exported['llm_picture_story_image_prompt'], '');
    expect(exported['llm_picture_story_question_prompt'], '观察人物的手势');
    await settings.setPictureStoryImageGenerationPrompt('目标设备原生图要求');
    await settings.setPictureStoryQuestionGenerationPrompt('目标设备原出题要求');
    await backup.restoreFromJson(text);
    final restored = SettingsRepository();
    expect(restored.pictureStoryImageGenerationPromptOverride, isNull);
    expect(restored.pictureStoryQuestionGenerationPromptOverride, '观察人物的手势');
    expect(HiveBoxes.settings.get('llm_picture_story_prompt'), '旧教学偏好');
  });

  test('旧备份共享提示词恢复到两项，覆盖目标设备原设置且保留旧原文', () async {
    final text = await payloadWithSettings({
      'llm_picture_story_prompt': '原书风格，鼓励孩子讲述',
    });
    final settings = SettingsRepository();
    await settings.setPictureStoryImageGenerationPrompt('目标设备生图偏好');
    await settings.setPictureStoryQuestionGenerationPrompt('目标设备出题偏好');
    await backup.restoreFromJson(text);
    final restored = SettingsRepository();
    expect(
      restored.pictureStoryImageGenerationPromptOverride,
      contains('平面手绘儿童教材插图'),
    );
    expect(
      restored.pictureStoryImageGenerationPromptOverride,
      endsWith('原书风格，鼓励孩子讲述'),
    );
    expect(
      restored.pictureStoryQuestionGenerationPromptOverride,
      '原书风格，鼓励孩子讲述',
    );
    expect(HiveBoxes.settings.get('llm_picture_story_prompt'), '原书风格，鼓励孩子讲述');
  });

  test('混合备份显式默认优先，坏类型不经旧共享偏好覆盖本机有效设置', () async {
    final text = await payloadWithSettings({
      'llm_picture_story_prompt': '旧备份教学要求',
      'llm_picture_story_image_prompt': '',
      'llm_picture_story_question_prompt': true,
    });
    final settings = SettingsRepository();
    await settings.setPictureStoryImageGenerationPrompt('本机生图要求');
    await settings.setPictureStoryQuestionGenerationPrompt('本机有效出题要求');
    await backup.restoreFromJson(text);
    expect(settings.pictureStoryImageGenerationPromptOverride, isNull);
    expect(settings.pictureStoryQuestionGenerationPromptOverride, '本机有效出题要求');
  });

  test('旧备份缺少提示词段时保留本机两项独立设置', () async {
    final text = await payloadWithSettings({});
    final settings = SettingsRepository();
    await settings.setPictureStoryImageGenerationPrompt('本机生图要求');
    await settings.setPictureStoryQuestionGenerationPrompt('本机出题要求');
    await backup.restoreFromJson(text);
    expect(settings.pictureStoryImageGenerationPromptOverride, '本机生图要求');
    expect(settings.pictureStoryQuestionGenerationPromptOverride, '本机出题要求');
  });
}
