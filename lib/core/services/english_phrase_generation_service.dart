import 'dart:convert';

import 'package:poemath/core/prompts/generation_prompt_defaults.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/domain/english_phrase_generation.dart';

class EnglishPhraseGenerationService {
  const EnglishPhraseGenerationService(this.client);
  final LlmClient client;

  Future<List<EnglishTarget>> generate({
    required LlmConfig config,
    required EnglishPhraseBatch batch,
    required int grade,
    required String semester,
    required String unitTitle,
    required String lessonTitle,
    required bool Function() isActive,
    String? promptOverride,
  }) async {
    void check() {
      if (!isActive()) throw const LlmGenerationCancelled();
    }

    check();
    if (batch.seeds.isEmpty ||
        batch.seeds.length > EnglishPhraseBatch.maxWords) {
      throw const FormatException('本批单词数量无效');
    }
    final now = DateTime.now();
    List<EnglishTarget>? parsed;
    final completion = await client.chatComplete(
      config: config,
      systemPrompt: buildEnglishPhraseGenerationPrompt(promptOverride),
      messages: [
        ChatMessage(
          role: ChatRole.user,
          content: jsonEncode({
            'grade': grade,
            'semester': semester,
            'unit': unitTitle,
            'lesson': lessonTitle,
            'words': [
              for (final seed in batch.seeds)
                {
                  'id': seed.target.id,
                  'word': seed.target.text,
                  'meaning': seed.target.meaning,
                  'needed': seed.missing,
                },
            ],
            'excluded': batch.existingTexts.toList(),
          }),
        ),
      ],
      maxTokens: batch.seeds.length * 280 + 300,
      validate: (reply) {
        if (reply.hasToolCalls) throw const FormatException('短语响应不能调用工具');
        parsed = batch.parse(reply.content ?? '', now: now);
      },
    );
    check();
    await client.acceptCompletion(completion);
    check();
    return parsed!;
  }
}
