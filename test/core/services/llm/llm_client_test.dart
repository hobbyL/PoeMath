// test/core/services/llm/llm_client_test.dart
//
// OpenAI 兼容 LLM 客户端测试：URL 规范化、请求头、prompt 结构、
// 容错 JSON 解析、index 对齐、格式重试与错误分类（mock http）；
// explain 讲解接口的请求契约、空输出与错误分类。

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

/// 第三个测试用骨架：36 ÷ 4 = 9（除法）。
ProblemSkeleton _divisionSkeleton() => const ProblemSkeleton(
      operands: [36, 4],
      operators: [Operator.divide],
      answer: 9,
      unitHint: '瓶',
      difficulty: 1,
    );

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

    test('http 本地回环地址放行（Ollama 等本地服务）', () {
      expect(
        LlmClient.normalizeBaseUrl('http://localhost:11434').toString(),
        'http://localhost:11434/v1',
      );
      expect(
        LlmClient.normalizeBaseUrl('http://127.0.0.1:8080/v1').toString(),
        'http://127.0.0.1:8080/v1',
      );
      expect(
        LlmClient.normalizeBaseUrl('http://[::1]:11434').toString(),
        'http://[::1]:11434/v1',
      );
    });

    test('http 公网地址抛 FormatException（防 API Key 明文传输）', () {
      expect(
        () => LlmClient.normalizeBaseUrl('http://api.example.com'),
        throwsFormatException,
      );
      // 以 "127." 开头的公网子域名不是回环地址，同样拒绝。
      expect(
        () => LlmClient.normalizeBaseUrl('http://127.evil.com/v1'),
        throwsFormatException,
      );
    });

    test('https 任意 host 不受影响', () {
      expect(
        LlmClient.normalizeBaseUrl('https://api.example.com').toString(),
        'https://api.example.com/v1',
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

    test('生成请求含 max_tokens 且随题数线性增长', () async {
      final captured = <http.Request>[];
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured.add(request);
          return _chatResponse(_normalArray);
        }),
      );

      List<ProblemSkeleton> skeletonsOf(int count) => List.generate(
            count,
            (i) => ProblemSkeleton(
              operands: [i + 1, 2],
              operators: const [Operator.multiply],
              answer: (i + 1) * 2,
              unitHint: '个',
              difficulty: 1,
            ),
          );

      // 10 题 = 10 * 220 + 400 = 2600；20 题 = 20 * 220 + 400 = 4800。
      await client.generateWordProblems(
        config: _config,
        skeletons: skeletonsOf(10),
        grade: 3,
        semester: '上',
        topic: 'addition',
      );
      await client.generateWordProblems(
        config: _config,
        skeletons: skeletonsOf(20),
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      expect(captured, hasLength(2));
      final firstBody =
          jsonDecode(captured[0].body) as Map<String, dynamic>;
      final secondBody =
          jsonDecode(captured[1].body) as Map<String, dynamic>;
      expect(firstBody['max_tokens'], 2600);
      expect(secondBody['max_tokens'], 4800);
    });

    test('index 为数字字符串也能对齐（"index":"3"）', () async {
      const content =
          '[{"index":"1","text":"小明有12支铅笔，妈妈又买了4支，一共有多少支铅笔？",'
          '"unit":"支","explanation":"12加4等于16。"},'
          '{"index":"3","text":"36瓶水平均分给4个小组，每组分到多少瓶水？",'
          '"unit":"瓶","explanation":"36除以4等于9。"}]';
      final client = LlmClient(
        httpClient: MockClient((_) async => _chatResponse(content)),
      );

      final skeletons = [..._skeletons(), _divisionSkeleton()];
      final result = await client.generateWordProblems(
        config: _config,
        skeletons: skeletons,
        grade: 3,
        semester: '上',
        topic: 'addition',
      );

      // 仅第 1、3 个骨架有草稿，字符串 index 正确对齐。
      expect(result.drafts, hasLength(2));
      expect(result.drafts[0].index, 1);
      expect(result.drafts[1].index, 3);
      expect(result.drafts[1].text, contains('36瓶水'));
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

    test('顶层为数组时仅保留 Map.id 与 String 元素（垃圾条目丢弃）', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode([
                  {'id': 'a'},
                  42,
                  true,
                  null,
                  'b',
                ],),),
            200,
          );
        }),
      );

      final models = await client.listModels(_config);
      expect(models, ['a', 'b']);
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

  group('explain', () {
    test('返回讲解文本（trim）；请求契约为 chat/completions + Bearer 头', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse('  第一段讲解。\n第二段讲解。  ');
        }),
      );

      final result = await client.explain(
        config: _config,
        systemPrompt: '你是老师',
        userPrompt: '讲讲《静夜思》',
      );

      expect(result.text, '第一段讲解。\n第二段讲解。');

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(captured.headers['authorization'], 'Bearer $_apiKey');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');
      expect(body['max_tokens'], 800);
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], '你是老师');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], '讲讲《静夜思》');
      // API Key 只走 Authorization 头，不入请求体。
      expect(captured.body, isNot(contains(_apiKey)));
    });

    test('maxTokens 可覆盖', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse('ok');
        }),
      );

      await client.explain(
        config: _config,
        systemPrompt: 's',
        userPrompt: 'u',
        maxTokens: 500,
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['max_tokens'], 500);
    });

    test('content 为空白抛 LlmResponseFormatError 且不重试', () async {
      var calls = 0;
      final client = LlmClient(
        httpClient: MockClient((_) async {
          calls++;
          return _chatResponse('   \n  ');
        }),
      );

      await expectLater(
        client.explain(config: _config, systemPrompt: 's', userPrompt: 'u'),
        throwsA(
          isA<LlmResponseFormatError>().having(
            (error) => error.toString(),
            '不暴露 API Key',
            allOf(isNot(contains(_apiKey)), isNot(contains('llm-secret'))),
          ),
        ),
      );
      // 讲解不做格式重试（失败即交 UI 重试）。
      expect(calls, 1);
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
        client.explain(config: _config, systemPrompt: 's', userPrompt: 'u'),
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
        client.explain(config: _config, systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<LlmServerError>()),
      );
    });

    test('超时映射为 LlmNetworkError（explainTimeout 独立于出题）', () async {
      final client = LlmClient(
        httpClient: MockClient(
          (_) async => Future.delayed(
            const Duration(seconds: 5),
            () => _chatResponse('慢'),
          ),
        ),
        explainTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        client.explain(config: _config, systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<LlmNetworkError>()),
      );
    });

    test('空 Key（Ollama）省略 Authorization 头', () async {
      late http.Request captured;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          captured = request;
          return _chatResponse('讲解内容');
        }),
      );

      const ollamaConfig = LlmConfig(
        baseUrl: 'http://localhost:11434',
        apiKey: '',
        model: 'qwen2.5:7b',
      );
      final result = await client.explain(
        config: ollamaConfig,
        systemPrompt: 's',
        userPrompt: 'u',
      );

      expect(result.text, '讲解内容');
      expect(captured.headers.containsKey('authorization'), isFalse);
    });
  });

  group('explainStream', () {
    test('逐片 yield 增量并拼接；请求含 stream:true + Bearer 头', () async {
      late String capturedBody;
      late Map<String, String> capturedHeaders;
      late String capturedUrl;
      final client = LlmClient(
        httpClient: MockClient.streaming((request, bodyStream) async {
          capturedHeaders = request.headers;
          capturedUrl = request.url.toString();
          capturedBody = await bodyStream.bytesToString();
          return _sse([
            _sseData('第一段。'),
            _sseData('第二段。'),
            'data: [DONE]\n\n',
          ]);
        }),
      );

      final chunks = await client
          .explainStream(
            config: _config,
            systemPrompt: '你是老师',
            userPrompt: '讲讲',
          )
          .toList();

      expect(chunks.join(), '第一段。第二段。');
      expect(capturedUrl, 'https://api.example.com/v1/chat/completions');
      expect(capturedHeaders['authorization'], 'Bearer $_apiKey');
      final body = jsonDecode(capturedBody) as Map<String, dynamic>;
      expect(body['stream'], true);
      expect(body['model'], 'gpt-4o-mini');
      expect(body['max_tokens'], 800);
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
      expect(capturedBody, isNot(contains(_apiKey)));
    });

    test('中文多字节字符跨分片边界不乱码', () async {
      // 把一条含中文的 SSE 行的 UTF-8 字节从中间切断成两片。
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
              .explainStream(config: _config, systemPrompt: 's', userPrompt: 'u')
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
            .explainStream(config: _config, systemPrompt: 's', userPrompt: 'u')
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
              .explainStream(config: _config, systemPrompt: 's', userPrompt: 'u')
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
            .explainStream(config: _config, systemPrompt: 's', userPrompt: 'u')
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
            .explainStream(config: _config, systemPrompt: 's', userPrompt: 'u')
            .toList(),
        throwsA(isA<LlmServerError>()),
      );
    });

    test('事件间隔超时映射为 LlmNetworkError', () async {
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
        explainTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        client
            .explainStream(config: _config, systemPrompt: 's', userPrompt: 'u')
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
          .explainStream(config: ollamaConfig, systemPrompt: 's', userPrompt: 'u')
          .toList();

      expect(capturedHeaders.containsKey('authorization'), isFalse);
    });
  });
}
