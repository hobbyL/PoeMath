import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';

void main() {
  const messages = [
    ChatMessage(
      role: ChatRole.user,
      content: '看图',
      contentParts: [
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, String>{'url': 'data:image/png;base64,abc'},
        },
      ],
    ),
  ];
  http.Response response() => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'observed'},
            }
          ],
        }),
        200,
      );

  test('当前配置的 GPT 和 Grok 型号可以进入视觉请求', () {
    for (final model in ['gpt-5.6-sol', 'gpt-6-astra', 'grok-4.7']) {
      expect(
        LlmConfig(baseUrl: 'https://example.com', apiKey: '', model: model)
            .supportsVision,
        isTrue,
      );
    }
  });

  test('视觉请求只向视觉候选回退，失败不会把图传给纯文本模型', () async {
    final models = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        final model = (jsonDecode(request.body)
            as Map<String, dynamic>)['model'] as String;
        models.add(model);
        return model == 'gpt-4o-mini'
            ? http.Response('unavailable', 503)
            : response();
      }),
    );
    addTearDown(client.close);
    const config = LlmConfig(
      baseUrl: 'https://example.com',
      apiKey: '',
      model: 'deepseek-chat',
      models: ['gpt-4o-mini', 'text-only', 'qwen3-vl'],
    );
    final result = await client.chatComplete(
      config: config,
      systemPrompt: 'Observe',
      messages: messages,
      requiresVision: true,
    );
    expect(result.content, 'observed');
    expect(models, ['gpt-4o-mini', 'qwen3-vl']);
  });

  test('默认厂商没有视觉候选时，使用具有视觉模型的备用厂商', () async {
    final hosts = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        hosts.add(request.url.host);
        return response();
      }),
    );
    addTearDown(client.close);
    const config = LlmConfig(
      baseUrl: 'https://text.example.com',
      apiKey: '',
      model: 'deepseek-chat',
      fallbacks: [
        LlmConfig(
          baseUrl: 'https://vision.example.com',
          apiKey: '',
          model: 'gpt-6-astra',
        ),
      ],
    );
    expect(config.supportsVision, isTrue);
    await client.chatComplete(
      config: config,
      systemPrompt: 'Observe',
      messages: messages,
      requiresVision: true,
    );
    expect(hosts, ['vision.example.com']);
  });

  test('没有视觉候选时零请求失败，普通文本调用仍可用', () async {
    var sends = 0;
    final client = LlmClient(
      httpClient: MockClient((_) async {
        sends++;
        return response();
      }),
    );
    addTearDown(client.close);
    const config = LlmConfig(
      baseUrl: 'https://example.com',
      apiKey: '',
      model: 'deepseek-chat',
    );
    await expectLater(
      client.chatComplete(
        config: config,
        systemPrompt: 'Observe',
        messages: messages,
        requiresVision: true,
      ),
      throwsA(isA<LlmResponseFormatError>()),
    );
    expect(sends, 0);
    await client.chatComplete(
      config: config,
      systemPrompt: 'Answer',
      messages: const [ChatMessage(role: ChatRole.user, content: 'hello')],
    );
    expect(sends, 1);
  });
}
