import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_config.dart';

void main() {
  test('多模态消息序列化为 content parts', () {
    const message = ChatMessage(
      role: ChatRole.user,
      content: '请看图',
      contentParts: [
        <String, Object?>{'type': 'text', 'text': '请看图'},
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, String>{'url': 'data:image/png;base64,abc'},
        },
      ],
    );

    final json = message.toJson();
    expect(json['content'], isA<List<Map<String, Object?>>>());
    expect((json['content'] as List).length, 2);
  });

  test('视觉模型识别只按候选模型名称开启', () {
    const vision = LlmConfig(
      baseUrl: 'https://example.com/v1',
      apiKey: '',
      model: 'gpt-4o-mini',
    );
    const textOnly = LlmConfig(
      baseUrl: 'https://example.com/v1',
      apiKey: '',
      model: 'deepseek-chat',
    );

    expect(vision.supportsVision, isTrue);
    expect(textOnly.supportsVision, isFalse);
  });
}
