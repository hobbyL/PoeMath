// test/core/services/llm/llm_client_chat_stream_test.dart
//
// LlmClient.chatStream 测试：多轮 messages 组装、SSE 增量拼接、
// 请求契约（stream:true + Bearer 头 + 不泄露 key）、错误分类、
// ChatMessage 的 tool 角色字段序列化。
//
// 与 explainStream 同传输层，差别在 messages 组装（system + 多轮）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';

const _apiKey = 'llm-secret-key-example';
const _config = LlmConfig(
  baseUrl: 'https://api.example.com',
  apiKey: _apiKey,
  model: 'gpt-4o-mini',
);

/// 把若干 SSE 文本片段包装成「分片到达」的流式响应。
http.StreamedResponse _sse(List<String> chunks, {int statusCode = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks.map(utf8.encode)),
      statusCode,
      headers: const {'content-type': 'text/event-stream; charset=utf-8'},
    );

/// 单条 SSE data 行（含结尾空行），content 包进 choices[0].delta.content。
String _sseData(String content) {
  final json = jsonEncode({
    'choices': [
      {
        'delta': {'content': content},
      },
    ],
  });
  return 'data: $json\n\n';
}

void main() {
  group('chatStream', () {
    test('多轮 messages 逐片 yield；请求含 system 首条 + stream:true + Bearer',
        () async {
      late String capturedBody;
      late Map<String, String> capturedHeaders;
      late String capturedUrl;
      final client = LlmClient(
        httpClient: MockClient.streaming((request, bodyStream) async {
          capturedHeaders = request.headers;
          capturedUrl = request.url.toString();
          capturedBody = await bodyStream.bytesToString();
          return _sse([
            _sseData('你好'),
            _sseData('，小朋友。'),
            'data: [DONE]\n\n',
          ]);
        }),
      );

      final chunks = await client
          .chatStream(
            config: _config,
            systemPrompt: '你是助手',
            messages: const [
              ChatMessage(role: ChatRole.user, content: '第一问'),
              ChatMessage(role: ChatRole.assistant, content: '第一答'),
              ChatMessage(role: ChatRole.user, content: '第二问'),
            ],
          )
          .toList();

      expect(chunks.join(), '你好，小朋友。');
      expect(capturedUrl, 'https://api.example.com/v1/chat/completions');
      expect(capturedHeaders['authorization'], 'Bearer $_apiKey');

      final body = jsonDecode(capturedBody) as Map<String, dynamic>;
      expect(body['stream'], true);
      expect(body['model'], 'gpt-4o-mini');
      expect(body['max_tokens'], 1024); // 对话默认档
      final messages = body['messages'] as List<dynamic>;
      // system + 3 轮会话消息。
      expect(messages, hasLength(4));
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], '你是助手');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], '第一问');
      expect(messages[2]['role'], 'assistant');
      expect(messages[3]['role'], 'user');
      expect(messages[3]['content'], '第二问');
      // 普通会话轮次不应带 tool 字段。
      expect((messages[1] as Map).containsKey('tool_call_id'), isFalse);
      expect((messages[1] as Map).containsKey('name'), isFalse);
      // key 绝不进请求体。
      expect(capturedBody, isNot(contains(_apiKey)));
    });

    test('role=tool 消息序列化 tool_call_id 与 name', () async {
      late String capturedBody;
      final client = LlmClient(
        httpClient: MockClient.streaming((request, bodyStream) async {
          capturedBody = await bodyStream.bytesToString();
          return _sse([_sseData('收到'), 'data: [DONE]\n\n']);
        }),
      );

      await client
          .chatStream(
            config: _config,
            systemPrompt: 's',
            messages: const [
              ChatMessage(role: ChatRole.user, content: '出题'),
              ChatMessage(
                role: ChatRole.tool,
                content: '已生成 3 道题',
                toolCallId: 'call_abc',
                name: 'generate_word_problems',
              ),
            ],
          )
          .toList();

      final body = jsonDecode(capturedBody) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final toolMsg = messages[2] as Map<String, dynamic>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['content'], '已生成 3 道题');
      expect(toolMsg['tool_call_id'], 'call_abc');
      expect(toolMsg['name'], 'generate_word_problems');
    });

    test('中文多字节字符跨分片边界不乱码', () async {
      final bytes = utf8.encode(_sseData('你好世界，床前明月光'));
      final mid = bytes.length ~/ 2;
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              bytes.sublist(0, mid),
              bytes.sublist(mid),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          ),
        ),
      );

      final text = (await client
              .chatStream(
                config: _config,
                systemPrompt: 's',
                messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
              )
              .toList())
          .join();
      expect(text, '你好世界，床前明月光');
    });

    test('全程无 content（仅 [DONE]）抛 LlmResponseFormatError', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => _sse(['data: [DONE]\n\n']),
        ),
      );

      await expectLater(
        client
            .chatStream(
              config: _config,
              systemPrompt: 's',
              messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
            )
            .toList(),
        throwsA(isA<LlmResponseFormatError>()),
      );
    });

    test('keep-alive 注释行 / 空行 / 坏 JSON 行跳过不中断', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => _sse([
            ': keep-alive\n\n',
            '\n',
            'data: not-json\n\n',
            _sseData('有效内容'),
            'data: [DONE]\n\n',
          ]),
        ),
      );

      final text = (await client
              .chatStream(
                config: _config,
                systemPrompt: 's',
                messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
              )
              .toList())
          .join();
      expect(text, '有效内容');
    });

    test('401 映射为 LlmAuthError', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => _sse(const [], statusCode: 401),
        ),
      );

      await expectLater(
        client
            .chatStream(
              config: _config,
              systemPrompt: 's',
              messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
            )
            .toList(),
        throwsA(isA<LlmAuthError>()),
      );
    });

    test('5xx 映射为 LlmServerError', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => _sse(const [], statusCode: 503),
        ),
      );

      await expectLater(
        client
            .chatStream(
              config: _config,
              systemPrompt: 's',
              messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
            )
            .toList(),
        throwsA(isA<LlmServerError>()),
      );
    });

    test('事件间隔超时映射为 LlmNetworkError（对话档）', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            Stream<List<int>>.fromFuture(
              Future.delayed(
                const Duration(milliseconds: 300),
                () => utf8.encode(_sseData('迟到')),
              ),
            ),
            200,
          ),
        ),
        chatTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        client
            .chatStream(
              config: _config,
              systemPrompt: 's',
              messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
            )
            .toList(),
        throwsA(isA<LlmNetworkError>()),
      );
    });

    test('空 Key（Ollama）省略 Authorization 头', () async {
      late Map<String, String> capturedHeaders;
      final client = LlmClient(
        httpClient: MockClient.streaming((request, bodyStream) async {
          capturedHeaders = request.headers;
          return _sse([_sseData('内容'), 'data: [DONE]\n\n']);
        }),
      );

      const ollamaConfig = LlmConfig(
        baseUrl: 'http://localhost:11434',
        apiKey: '',
        model: 'qwen2.5:7b',
      );
      await client
          .chatStream(
            config: ollamaConfig,
            systemPrompt: 's',
            messages: const [ChatMessage(role: ChatRole.user, content: 'u')],
          )
          .toList();

      expect(capturedHeaders.containsKey('authorization'), isFalse);
    });
  });
}
