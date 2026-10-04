// test/core/services/llm/llm_client_test.dart
//
// OpenAI 兼容 LLM 客户端测试：URL 规范化、请求头、prompt 结构、
// 容错 JSON 解析、index 对齐、格式重试与错误分类（mock http）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

const _apiKey = 'llm-secret-key-example';
const _config = LlmConfig(
  baseUrl: 'https://api.example.com',
  apiKey: _apiKey,
  model: 'gpt-4o-mini',
);

/// 两个测试用骨架：12 + 4 = 16（加法）、20 - 8 = 12（减法）。
List<ProblemSkeleton> _skeletons() => [
      const ProblemSkeleton(
        operands: [12, 4],
        operators: [Operator.add],
        answer: 16,
        unitHint: '支',
        difficulty: 1,
      ),
      const ProblemSkeleton(
        operands: [20, 8],
        operators: [Operator.subtract],
        answer: 12,
        unitHint: '个',
        difficulty: 1,
      ),
    ];

http.Response _chatResponse(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      }),),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

const _normalArray =
    '[{"index":1,"text":"小明有12支铅笔，妈妈又买了4支，小明一共有多少支铅笔？",'
    '"unit":"支","explanation":"先算 12+4，一共有16支。"},'
    '{"index":2,"text":"树上原来有20个苹果，摘走了8个，还剩多少个苹果？",'
    '"unit":"个","explanation":"20减8等于12，还剩12个。"}]';

void main() {
  group('normalizeBaseUrl', () {
    test('末尾无 /v1 则自动补', () {
      expect(
        LlmClient.normalizeBaseUrl('https://api.example.com').toString(),
        'https://api.example.com/v1',
      );
    });

    test('已有 /v1 不重复补', () {
      expect(
        LlmClient.normalizeBaseUrl('https://api.example.com/v1').toString(),
        'https://api.example.com/v1',
      );
    });

    test('裸域名补 https 与 /v1 并去尾斜杠', () {
      expect(
        LlmClient.normalizeBaseUrl('api.example.com/').toString(),
        'https://api.example.com/v1',
      );
    });

    test('非法输入抛 FormatException', () {
      expect(
        () => LlmClient.normalizeBaseUrl('not a url'),
        throwsFormatException,
      );
      expect(() => LlmClient.normalizeBaseUrl(''), throwsFormatException);
      expect(
        () => LlmClient.normalizeBaseUrl('ftp://x.com'),
        throwsFormatException,
      );
    });
  });

  group('generateWordProblems', () {
    test('正常解析并按 index 对齐 skeleton', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse(_normalArray);
        }),
      );

      final result = await client.generateWordProblems(
        config: _config,
        skeletons: _skeletons(),
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      expect(result.drafts, hasLength(2));
      expect(result.drafts[0].index, 1);
      expect(result.drafts[0].text, contains('12'));
      expect(result.drafts[0].unit, '支');
      expect(result.drafts[1].index, 2);

      // 请求契约：POST {base}/chat/completions + Bearer + 模型名。
      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://api.example.com/v1/chat/completions',);
      expect(captured.headers['authorization'], 'Bearer $_apiKey');
      final body =
          jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
      // user prompt 含骨架数字与单位提示。
      final userContent = messages[1]['content'] as String;
      expect(userContent, contains('[12,4]'));
      expect(userContent, contains('支'));
      expect(userContent, contains('小学3年级上学期'));
      // API Key 不得出现在请求体。
      expect(captured.body, isNot(contains(_apiKey)));
    });

    test('code fence 包裹与前后杂质文本可解析', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async {
          return _chatResponse(
            '以下是生成的题目：\n```json\n$_normalArray\n```\n希望有帮助！',
          );
        }),
      );

      final result = await client.generateWordProblems(
        config: _config,
        skeletons: _skeletons(),
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      expect(result.drafts, hasLength(2));
    });

    test('index 缺失或越界的条目被丢弃，顺序仍按 skeleton', () async {
      // index 2 缺失、index 99 越界多余。
      const content =
          '[{"index":99,"text":"多余","unit":"个","explanation":"x"},'
          '{"index":1,"text":"小明有12支铅笔","unit":"支","explanation":"y"}]';
      final client = LlmClient(
        httpClient: MockClient((_) async => _chatResponse(content)),
      );

      final result = await client.generateWordProblems(
        config: _config,
        skeletons: _skeletons(),
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      expect(result.drafts, hasLength(1));
      expect(result.drafts[0].index, 1);
    });

    test('JSON 解析失败整批重试，第 2 次成功', () async {
      var calls = 0;
      final client = LlmClient(
        httpClient: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return _chatResponse('抱歉，我无法输出 JSON。');
          }
          return _chatResponse(_normalArray);
        }),
      );

      final result = await client.generateWordProblems(
        config: _config,
        skeletons: _skeletons(),
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      expect(calls, 2);
      expect(result.drafts, hasLength(2));
    });

    test('重试 2 次仍失败抛 LlmResponseFormatError', () async {
      var calls = 0;
      final client = LlmClient(
        httpClient: MockClient((_) async {
          calls++;
          return _chatResponse('这不是 JSON');
        }),
      );

      await expectLater(
        client.generateWordProblems(
          config: _config,
          skeletons: _skeletons(),
          grade: 3,
          semester: '上',
          topic: 'addition',
        ),
        throwsA(
          isA<LlmResponseFormatError>()
              .having(
                (error) => error.toString(),
                '不暴露 API Key',
                allOf(isNot(contains(_apiKey)), isNot(contains('llm-secret'))),
              ),
        ),
      );
      expect(calls, 3); // 1 次首请求 + 2 次重试
    });

    test('401 映射为 LlmAuthError 且不重试', () async {
      var calls = 0;
      final client = LlmClient(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'error': {'message': 'invalid key'}})),
            401,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );

      await expectLater(
        client.generateWordProblems(
          config: _config,
          skeletons: _skeletons(),
          grade: 3,
          semester: '上',
          topic: 'addition',
        ),
        throwsA(isA<LlmAuthError>()),
      );
      expect(calls, 1);
    });

    test('5xx 映射为 LlmServerError', () async {
      final client = LlmClient(
        httpClient: MockClient(
          (_) async => http.Response.bytes(const [], 503),
        ),
      );

      await expectLater(
        client.generateWordProblems(
          config: _config,
          skeletons: _skeletons(),
          grade: 3,
          semester: '上',
          topic: 'addition',
        ),
        throwsA(isA<LlmServerError>()),
      );
    });

    test('超时映射为 LlmNetworkError', () async {
      final client = LlmClient(
        httpClient: MockClient(
          (_) async => Future.delayed(
            const Duration(seconds: 5),
            () => _chatResponse(_normalArray),
          ),
        ),
        generateTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        client.generateWordProblems(
          config: _config,
          skeletons: _skeletons(),
          grade: 3,
          semester: '上',
          topic: 'addition',
        ),
        throwsA(isA<LlmNetworkError>()),
      );
    });

    test('空 skeletons 直接返回空结果不发请求', () async {
      var calls = 0;
      final client = LlmClient(
        httpClient: MockClient((_) async {
          calls++;
          return _chatResponse('[]');
        }),
      );

      final result = await client.generateWordProblems(
        config: _config,
        skeletons: const [],
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      expect(result.drafts, isEmpty);
      expect(calls, 0);
    });
  });

  group('listModels', () {
    test('解析 data[].id 并排序', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'data': [
                {'id': 'gpt-4o-mini'},
                {'id': 'qwen2.5:7b'},
                {'id': 'gpt-4o'},
              ],
            }),),
            200,
          );
        }),
      );

      final models = await client.listModels(_config);
      expect(models, ['gpt-4o', 'gpt-4o-mini', 'qwen2.5:7b']);
    });

    test('非 2xx 抛 LlmModelsUnavailable（UI 退化手填）', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async => http.Response.bytes(const [], 404)),
      );

      await expectLater(
        client.listModels(_config),
        throwsA(isA<LlmModelsUnavailable>()),
      );
    });
  });

  group('testConnection', () {
    test('发送 max_tokens=1 真实请求，2xx 通过', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse('好');
        }),
      );

      await client.testConnection(_config);

      expect(captured.url.toString(),
          'https://api.example.com/v1/chat/completions',);
      final body =
          jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['max_tokens'], 1);
      expect(body['model'], 'gpt-4o-mini');
    });

    test('空 Key（Ollama）省略 Authorization 头', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse('好');
        }),
      );

      const ollamaConfig = LlmConfig(
        baseUrl: 'http://localhost:11434',
        apiKey: '',
        model: 'qwen2.5:7b',
      );
      await client.testConnection(ollamaConfig);

      expect(captured.url.toString(),
          'http://localhost:11434/v1/chat/completions',);
      expect(captured.headers.containsKey('authorization'), isFalse);
    });
  });
}
