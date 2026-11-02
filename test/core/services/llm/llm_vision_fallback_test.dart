import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';

ChatMessage _imageMessage(int bytes) => ChatMessage(
      role: ChatRole.user,
      content: '观察实际图片',
      contentParts: [
        {'type': 'text', 'text': '观察实际图片'},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/png;base64,${base64Encode(Uint8List(bytes))}',
          },
        },
      ],
    );

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

  const visionConfig = LlmConfig(
    baseUrl: 'https://vision.example.com',
    apiKey: '',
    model: 'gpt-4o-mini',
  );

  test('视觉请求保留完整 512 KiB 图片，并按完整轮次裁剪旧历史', () async {
    final imageMessage = _imageMessage(PictureStoryImageService.maxUploadBytes);
    final bodies = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        bodies.add(request.body);
        return response();
      }),
    );
    addTearDown(client.close);
    final result = await client.chatComplete(
      config: visionConfig,
      systemPrompt: '观察实际画面',
      messages: [
        ChatMessage(role: ChatRole.user, content: 'a' * (160 * 1024)),
        const ChatMessage(role: ChatRole.assistant, content: '旧回答'),
        imageMessage,
      ],
      requiresVision: true,
    );
    expect(result.content, 'observed');
    expect(bodies, hasLength(1));
    expect(utf8.encode(bodies.single).length, lessThan(1024 * 1024));
    final body = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(body['messages'], [
      {'role': 'system', 'content': '观察实际画面'},
      imageMessage.toJson(),
    ]);
  });

  test('普通文本请求仍拒绝超过 256 KiB 的当前轮', () async {
    var sends = 0;
    final client = LlmClient(
      httpClient: MockClient((_) async {
        sends++;
        return response();
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.chatComplete(
        config: visionConfig,
        systemPrompt: '回答问题',
        messages: [
          ChatMessage(role: ChatRole.user, content: '文' * (100 * 1024)),
        ],
      ),
      throwsA(
        isA<LlmResponseFormatError>().having(
          (error) => error.message,
          '文字上下文超限',
          '本轮内容过长，请缩短问题或新建会话',
        ),
      ),
    );
    expect(sends, 0);
  });

  test('视觉上下文超限和完整请求超过 1 MiB 均在发送前拒绝', () async {
    final imageMessage = _imageMessage(PictureStoryImageService.maxUploadBytes);
    for (final (:context, :prompt, :message) in [
      (
        context: [_imageMessage(PictureStoryImageService.maxUploadBytes * 2)],
        prompt: '观察实际画面',
        message: '本轮内容过长，请缩短问题或新建会话',
      ),
      (
        context: [imageMessage],
        prompt: '文' * (130 * 1024),
        message: '请求内容过长，请缩短后重试',
      ),
    ]) {
      var sends = 0;
      final client = LlmClient(
        httpClient: MockClient((_) async {
          sends++;
          return response();
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.chatComplete(
          config: visionConfig,
          systemPrompt: prompt,
          messages: context,
          requiresVision: true,
        ),
        throwsA(
          isA<LlmResponseFormatError>().having(
            (error) => error.message,
            '本地拒绝原因',
            message,
          ),
        ),
      );
      expect(sends, 0);
    }
  });

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
