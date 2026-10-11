// test/core/services/llm/chat_complete_test.dart
//
// LlmClient.chatComplete（非流式工具调用）测试：
//   - 解析含 tool_calls 的响应 → ToolCall 列表（id/name/argumentsJson）；
//   - 纯 content 响应 → toolCalls 为空（退化纯聊天）；
//   - content 与 tool_calls 同时缺失 → 格式错误；
//   - 请求契约：tools / tool_choice 写入 body，空 tools 不带该字段；
//   - 错误分类：401→Auth、500→Server、网络→Network；
//   - Key 安全：apiKey 仅在 Authorization 头，不入请求体。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/llm/chat_completion.dart';
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

const _messages = <ChatMessage>[
  ChatMessage(role: ChatRole.user, content: '帮我出 3 道加法题'),
];

/// 工具 schema（已序列化，模拟 AssistantTool.toSchema() 的产出）。
const _tools = <Map<String, Object?>>[
  <String, Object?>{
    'type': 'function',
    'function': <String, Object?>{
      'name': 'generate_word_problems',
      'description': '生成应用题',
      'parameters': <String, Object?>{'type': 'object'},
    },
  },
];

http.Response _jsonResponse(Map<String, Object?> body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 带 tool_calls 的 message 响应。
http.Response _toolCallResponse() => _jsonResponse(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{
            'role': 'assistant',
            'content': null,
            'tool_calls': <Object?>[
              <String, Object?>{
                'id': 'call_1',
                'type': 'function',
                'function': <String, Object?>{
                  'name': 'generate_word_problems',
                  'arguments':
                      '{"grade":3,"semester":"上","topic":"addition","count":3}',
                },
              },
            ],
          },
        },
      ],
    });

/// 纯文本 message 响应。
http.Response _contentResponse(String content) =>
    _jsonResponse(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'role': 'assistant', 'content': content},
        },
      ],
    });

void main() {
  group('chatComplete 解析', () {
    test('解析 tool_calls：id/name/argumentsJson', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async => _toolCallResponse()),
      );

      final comp = await client.chatComplete(
        config: _config,
        systemPrompt: 'sys',
        messages: _messages,
        tools: _tools,
      );

      expect(comp.hasToolCalls, isTrue);
      expect(comp.toolCalls, hasLength(1));
      expect(comp.toolCalls.first.id, 'call_1');
      expect(comp.toolCalls.first.name, 'generate_word_problems');
      expect(comp.toolCalls.first.argumentsJson, contains('"count":3'));
      expect(comp.content, anyOf(isNull, isEmpty));
    });

    test('纯 content：toolCalls 为空', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async => _contentResponse('你好呀～')),
      );

      final comp = await client.chatComplete(
        config: _config,
        systemPrompt: 'sys',
        messages: _messages,
      );

      expect(comp.hasToolCalls, isFalse);
      expect(comp.content, '你好呀～');
    });

    test('content 与 tool_calls 同时缺失 → 格式错误', () async {
      final client = LlmClient(
        httpClient: MockClient(
          (_) async => _jsonResponse(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'role': 'assistant'},
              },
            ],
          }),
        ),
      );

      expect(
        () => client.chatComplete(
          config: _config,
          systemPrompt: 'sys',
          messages: _messages,
        ),
        throwsA(isA<LlmResponseFormatError>()),
      );
    });
  });

  group('chatComplete 请求契约', () {
    test('tools / tool_choice 写入 body；apiKey 仅在头部', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _toolCallResponse();
        }),
      );

      await client.chatComplete(
        config: _config,
        systemPrompt: 'sys',
        messages: _messages,
        tools: _tools,
        toolChoice: 'auto',
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(captured.headers['authorization'], 'Bearer $_apiKey');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['tools'], isA<List<dynamic>>());
      expect((body['tools'] as List<dynamic>).first['function']['name'],
          'generate_word_problems',);
      expect(body['tool_choice'], 'auto');
      final messages = body['messages'] as List<dynamic>;
      expect(messages.first['role'], 'system');
      // Key 安全：apiKey 不得出现在请求体。
      expect(captured.body, isNot(contains(_apiKey)));
    });

    test('空 tools 不写 tools / tool_choice 字段', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _contentResponse('纯聊天');
        }),
      );

      await client.chatComplete(
        config: _config,
        systemPrompt: 'sys',
        messages: _messages,
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });

    test('assistant 消息回灌 tool_calls 序列化为 tool_calls 数组', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _contentResponse('ok');
        }),
      );

      await client.chatComplete(
        config: _config,
        systemPrompt: 'sys',
        messages: const <ChatMessage>[
          ChatMessage(role: ChatRole.user, content: '出题'),
          ChatMessage(
            role: ChatRole.assistant,
            content: '',
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'call_1',
                name: 'generate_word_problems',
                argumentsJson: '{"count":3}',
              ),
            ],
          ),
          ChatMessage(
            role: ChatRole.tool,
            content: '已生成 3 道题',
            toolCallId: 'call_1',
            name: 'generate_word_problems',
          ),
        ],
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      // [system, user, assistant(tool_calls), tool]
      final assistant = messages[2] as Map<String, dynamic>;
      final calls = assistant['tool_calls'] as List<dynamic>;
      expect(calls.first['id'], 'call_1');
      expect(calls.first['function']['name'], 'generate_word_problems');
      expect(calls.first['function']['arguments'], '{"count":3}');
      final toolMsg = messages[3] as Map<String, dynamic>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['tool_call_id'], 'call_1');
      expect(toolMsg['name'], 'generate_word_problems');
    });
  });

  group('chatComplete 错误分类', () {
    test('401 → LlmAuthError', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async => http.Response.bytes(const [], 401)),
      );
      expect(
        () => client.chatComplete(
          config: _config,
          systemPrompt: 'sys',
          messages: _messages,
        ),
        throwsA(isA<LlmAuthError>()),
      );
    });

    test('500 → LlmServerError', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async => http.Response.bytes(const [], 500)),
      );
      expect(
        () => client.chatComplete(
          config: _config,
          systemPrompt: 'sys',
          messages: _messages,
        ),
        throwsA(isA<LlmServerError>()),
      );
    });

    test('网络异常 → LlmNetworkError', () async {
      final client = LlmClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('boom'),
        ),
      );
      expect(
        () => client.chatComplete(
          config: _config,
          systemPrompt: 'sys',
          messages: _messages,
        ),
        throwsA(isA<LlmNetworkError>()),
      );
    });
  });
}
