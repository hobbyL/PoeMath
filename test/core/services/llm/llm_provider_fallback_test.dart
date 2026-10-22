import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';

const _config = LlmConfig(
  baseUrl: 'https://first.example/v1',
  apiKey: 'first-key',
  model: 'A',
  models: ['A', 'B', 'A'],
  fallbacks: [
    LlmConfig(
      baseUrl: 'https://second.example/v1',
      apiKey: 'second-key',
      model: 'A',
      models: ['A', 'C'],
    ),
    LlmConfig(baseUrl: 'https://third.example/v1', apiKey: '', model: 'D'),
  ],
);

Map<String, dynamic> _body(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

String _attempt(http.Request request) =>
    '${request.url.host}:${_body(request.body)['model']}';

http.Response _completion(String text) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'content': text},
            },
          ],
        }),
      ),
      200,
    );

List<int> _delta(String text) => utf8.encode('data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': text},
            },
          ],
        })}\n\n');

void main() {
  test('逐供应商默认再候选，同名模型不混淆端点与凭据，成功即停', () async {
    final attempts = <String>[];
    final successes = <LlmConfig>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        attempts.add(_attempt(request));
        expect(request.url.path, '/v1/chat/completions');
        expect(
          request.headers['authorization'],
          switch (request.url.host) {
            'first.example' => 'Bearer first-key',
            'second.example' => 'Bearer second-key',
            _ => null,
          },
        );
        expect(request.body, isNot(contains('first-key')));
        expect(request.body, isNot(contains('second-key')));
        return _attempt(request) == 'second.example:C'
            ? _completion('成功回答')
            : http.Response('', 503);
      }),
      onSelectionSucceeded: (original, successful) async {
        expect(identical(original, _config), isTrue);
        successes.add(successful);
      },
    );
    addTearDown(client.close);
    final result =
        await client.explain(config: _config, systemPrompt: '', userPrompt: '');
    expect(result.text, '成功回答');
    expect(attempts, [
      'first.example:A',
      'first.example:B',
      'second.example:A',
      'second.example:C',
    ]);
    expect(successes.single.baseUrl, 'https://second.example/v1');
    expect(successes.single.model, 'C');
  });

  test('401淘汰整家供应商，下一供应商同名默认成功也上报', () async {
    final attempts = <String>[];
    final successes = <LlmConfig>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        attempts.add(_attempt(request));
        return request.url.host == 'first.example'
            ? http.Response('', 401)
            : _completion('可用');
      }),
      onSelectionSucceeded: (_, successful) async => successes.add(successful),
    );
    addTearDown(client.close);
    expect(
      (await client.explain(
        config: _config,
        systemPrompt: '',
        userPrompt: '',
      ))
          .text,
      '可用',
    );
    expect(attempts, ['first.example:A', 'second.example:A']);
    expect(successes.single.baseUrl, 'https://second.example/v1');
    expect(successes.single.model, 'A');
  });

  test('全部供应商失败只遍历一轮，最后错误保留且不保存', () async {
    final attempts = <String>[];
    var saved = false;
    final client = LlmClient(
      httpClient: MockClient((request) async {
        attempts.add(_attempt(request));
        return http.Response(
          '',
          request.url.host == 'third.example' ? 429 : 503,
        );
      }),
      onSelectionSucceeded: (_, __) async => saved = true,
    );
    addTearDown(client.close);
    await expectLater(
      client.explain(config: _config, systemPrompt: '', userPrompt: ''),
      throwsA(
        isA<LlmServerError>()
            .having((error) => error.message, 'message', contains('429')),
      ),
    );
    expect(attempts, [
      'first.example:A',
      'first.example:B',
      'second.example:A',
      'second.example:C',
      'third.example:D',
    ]);
    expect(saved, isFalse);
  });

  test('工具探测只记住供应商，后续请求保留工具历史，最终流成功才保存', () async {
    final attempts = <String>[];
    final successes = <LlmConfig>[];
    const history = [
      ChatMessage(role: ChatRole.user, content: '题目'),
      ChatMessage(
        role: ChatRole.tool,
        toolCallId: 'call-1',
        content: '已执行的工具结果',
      ),
    ];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        final body = _body(request.body);
        final stream = body['stream'] == true;
        attempts.add('${_attempt(request)}:$stream');
        expect((body['messages'] as List).last, history.last.toJson());
        if (request.url.host == 'first.example') return http.Response('', 401);
        if (!stream) return _completion('探测');
        return http.Response.bytes(
          [..._delta('最终回答'), ...utf8.encode('data: [DONE]\n\n')],
          200,
        );
      }),
      onSelectionSucceeded: (_, successful) async => successes.add(successful),
    );
    addTearDown(client.close);
    await client.chatComplete(
      config: _config,
      systemPrompt: '',
      messages: history,
    );
    await client.chatComplete(
      config: _config,
      systemPrompt: '',
      messages: history,
    );
    expect(successes, isEmpty);
    expect(
      await client
          .chatStream(config: _config, systemPrompt: '', messages: history)
          .join(),
      '最终回答',
    );
    expect(attempts, [
      'first.example:A:false',
      'second.example:A:false',
      'second.example:A:false',
      'second.example:A:true',
    ]);
    expect(successes.single.baseUrl, 'https://second.example/v1');
  });

  test('流式未输出时跨供应商并丢弃空白', () async {
    final attempts = <String>[];
    final client = LlmClient(
      httpClient: MockClient.streaming((request, body) async {
        final model = _body(await body.bytesToString())['model'];
        attempts.add('${request.url.host}:$model');
        if (request.url.host == 'first.example') {
          return http.StreamedResponse(Stream.value([]), 401);
        }
        return http.StreamedResponse(
          () async* {
            if (model == 'A') {
              yield _delta(' \n');
              throw http.ClientException('断开');
            }
            yield _delta('有效回答');
            yield utf8.encode('data: [DONE]\n\n');
          }(),
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(
      await client
          .explainStream(config: _config, systemPrompt: '', userPrompt: '')
          .join(),
      '有效回答',
    );
    expect(
      attempts,
      ['first.example:A', 'second.example:A', 'second.example:C'],
    );
  });

  test('已有可见输出后失败，保留部分文字且不切换或保存', () async {
    final attempts = <String>[];
    final chunks = <String>[];
    var saved = false;
    final client = LlmClient(
      httpClient: MockClient.streaming((request, body) async {
        attempts.add(
          '${request.url.host}:${_body(await body.bytesToString())['model']}',
        );
        if (request.url.host == 'first.example') {
          return http.StreamedResponse(Stream.value([]), 401);
        }
        return http.StreamedResponse(
          () async* {
            yield _delta('部分回答');
            throw http.ClientException('断开');
          }(),
          200,
        );
      }),
      onSelectionSucceeded: (_, __) async => saved = true,
    );
    addTearDown(client.close);
    await expectLater(
      client
          .explainStream(config: _config, systemPrompt: '', userPrompt: '')
          .map((chunk) {
        chunks.add(chunk);
        return chunk;
      }).drain<void>(),
      throwsA(isA<LlmNetworkError>()),
    );
    expect(chunks, ['部分回答']);
    expect(attempts, ['first.example:A', 'second.example:A']);
    expect(saved, isFalse);
  });

  test('取消时不请求下一供应商也不保存', () async {
    final attempts = <String>[];
    var active = true;
    var saved = false;
    final client = LlmClient(
      isActive: () => active,
      httpClient: MockClient((request) async {
        attempts.add(_attempt(request));
        active = false;
        return http.Response('', 503);
      }),
      onSelectionSucceeded: (_, __) async => saved = true,
    );
    addTearDown(client.close);
    await expectLater(
      client.explain(config: _config, systemPrompt: '', userPrompt: ''),
      throwsA(isA<LlmGenerationCancelled>()),
    );
    expect(attempts, ['first.example:A']);
    expect(saved, isFalse);
  });

  test('请求大小限制不尝试任何供应商', () async {
    var requests = 0;
    final client = LlmClient(
      httpClient: MockClient((_) async {
        requests++;
        return _completion('不应请求');
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.explain(
        config: _config,
        systemPrompt: 'x' * (1024 * 1024 + 1),
        userPrompt: '',
      ),
      throwsA(
        isA<LlmResponseFormatError>()
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
    expect(requests, 0);
  });

  test('跨供应商成功的保存失败不会丢失回答', () async {
    final client = LlmClient(
      httpClient: MockClient(
        (request) async => request.url.host == 'first.example'
            ? http.Response('', 401)
            : _completion('有效回答'),
      ),
      onSelectionSucceeded: (_, __) async => throw StateError('无法写入'),
    );
    addTearDown(client.close);
    expect(
      (await client.explain(
        config: _config,
        systemPrompt: '',
        userPrompt: '',
      ))
          .text,
      '有效回答',
    );
  });

  test('连接测试仍只测试指定供应商和指定模型', () async {
    final attempts = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        attempts.add(_attempt(request));
        return http.Response('', 503);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.testConnection(_config),
      throwsA(isA<LlmServerError>()),
    );
    expect(attempts, ['first.example:A']);
  });
}
