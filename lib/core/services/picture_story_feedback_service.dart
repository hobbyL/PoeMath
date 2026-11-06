import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:poemath/core/prompts/picture_story_feedback_prompt.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 一次页面内点评，输入、校验与模型回写共用同一份答案快照。
class PictureStoryFeedbackService {
  PictureStoryFeedbackService({
    required this.settings,
    required this.httpClient,
    required this.onSelectionChanged,
  });
  final SettingsRepository settings;
  final http.Client httpClient;
  final void Function() onSelectionChanged;
  LlmClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  Future<String> evaluate({
    required PictureStoryPrompt prompt,
    required String answer,
    required Uint8List? image,
    required bool Function() isActive,
  }) async {
    if (answer.trim().isEmpty) {
      return unavailablePictureStoryFeedback('请先填写表达文字。');
    }
    if (answer.runes.length > 6000) {
      return unavailablePictureStoryFeedback('表达超过 6000 字，请精简后再点评。');
    }
    if (image == null) {
      return unavailablePictureStoryFeedback('题图暂时无法读取，回答已保留，可稍后重试。');
    }
    bool active() => !_cancelled && isActive();
    try {
      final config = await settings.readLlmConfigForScenario(
        LlmScenario.pictureStoryFeedback,
      );
      if (!active()) return unavailablePictureStoryFeedback('点评已暂停，可重新发起。');
      if (config == null || !config.supportsVision) {
        return unavailablePictureStoryFeedback('请家长为“看图说话点评”配置支持看图的模型。');
      }
      final preference = settings.pictureStoryFeedbackPromptOverride;
      if ((preference?.runes.length ?? 0) >
          kPictureStoryFeedbackPromptMaxLength) {
        return unavailablePictureStoryFeedback('点评提示词过长，请家长缩短后重试。');
      }
      final client = _client = createRuntimeLlmClient(
        httpClient: httpClient,
        settings: settings,
        isActive: active,
        onSelectionChanged: onSelectionChanged,
      );
      final input = jsonEncode({
        'answer': answer,
        'title': prompt.title,
        'questions': [
          for (final (i, question) in prompt.questions.indexed)
            {'id': '${i + 1}', 'question': question},
        ],
        'sceneFacts': prompt.sceneFacts,
        'goals': prompt.goals,
        'reference': prompt.reference,
      });
      final completion = await client.chatComplete(
        config: config,
        systemPrompt: buildPictureStoryFeedbackPrompt(preference),
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: input,
            contentParts: [
              {'type': 'text', 'text': input},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(image)}',
                },
              },
            ],
          ),
        ],
        requiresVision: true,
        maxTokens: 4000,
        validate: (completion) => PictureStoryEvaluation.parse(
          completion.content ?? '',
          answer: answer,
          questionCount: prompt.questions.length,
        ),
      );
      final evaluation = PictureStoryEvaluation.parse(
        completion.content ?? '',
        answer: answer,
        questionCount: prompt.questions.length,
      );
      if (!active()) return unavailablePictureStoryFeedback('点评已暂停，可重新发起。');
      await client.acceptCompletion(completion);
      return evaluation.encode(answer: answer, prompts: prompt.questions);
    } on Object {
      // 不回显供应商正文、凭据或答案；原回答始终可回听和重试。
      return unavailablePictureStoryFeedback('点评暂时不可用，回答已保留，可稍后重试。');
    } finally {
      _client?.close();
      _client = null;
    }
  }
}
