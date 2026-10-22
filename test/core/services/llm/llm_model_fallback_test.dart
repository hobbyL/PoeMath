import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';

const _config = LlmConfig(
  baseUrl: 'https://example.com/v1',
  apiKey: 'private-key',
  model: 'A',
  models: ['A', 'B', 'C', 'B'],
);

http.Response _completion(String content) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content},
            },
          ],
        }),
      ),
      200,
    );

List<int> _delta(String content) => utf8.encode('data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': content},
            },
          ],
        })}\n\n');

String _model(String body) =>
    (jsonDecode(body) as Map<String, dynamic>)['model'] as String;

void main() {
  test('403及404后按已选顺序切换，同端点同凭据，只有有效结果上报成功', () async {
    final models = <String>[];
    final promoted = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://example.com/v1/chat/completions',
        );
        expect(request.headers['authorization'], 'Bearer private-key');
        expect(request.body, isNot(contains('private-key')));
        final model = _model(request.body);
        models.add(model);
        return switch (model) {
          'A' => http.Response('', 403),
          'B' => http.Response('', 404),
          _ => _completion('有效讲解'),
        };
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(client.close);
    final result = await client.explain(
      config: _config,
      systemPrompt: '讲解',
      userPrompt: '题目',
    );
    expect(result.text, '有效讲解');
    expect(models, ['A', 'B', 'C']);
    expect(promoted, ['C']);
  });

  test('空响应和无效JSON切换下一模型', () async {
    final models = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        final model = _model(request.body);
        models.add(model);
        return switch (model) {
          'A' => _completion('   '),
          'B' => http.Response('not JSON', 200),
          _ => _completion('答案'),
        };
      }),
    );
    addTearDown(client.close);
    expect(
      (await client.explain(
        config: _config,
        systemPrompt: '',
        userPrompt: '',
      ))
          .text,
      '答案',
    );
    expect(models, ['A', 'B', 'C']);
  });

  test('401立即停止，不尝试其他模型也不提升默认', () async {
    final models = <String>[];
    final promoted = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        models.add(_model(request.body));
        return http.Response('', 401);
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(client.close);
    await expectLater(
      client.explain(config: _config, systemPrompt: '', userPrompt: ''),
      throwsA(isA<LlmAuthError>()),
    );
    expect(models, ['A']);
    expect(promoted, isEmpty);
  });

  test('全部失败每个候选一次，保持最后错误且不提升默认', () async {
    final models = <String>[];
    final promoted = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        models.add(_model(request.body));
        return http.Response('', 503);
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(client.close);
    await expectLater(
      client.explain(config: _config, systemPrompt: '', userPrompt: ''),
      throwsA(
        isA<LlmServerError>()
            .having((e) => e.message, 'message', contains('503')),
      ),
    );
    expect(models, ['A', 'B', 'C']);
    expect(promoted, isEmpty);
  });

  test('流首段前空白和网络错误可切换，丢弃前模型空白', () async {
    final models = <String>[];
    final promoted = <String>[];
    final client = LlmClient(
      httpClient: MockClient.streaming((request, body) async {
        final model = _model(await body.bytesToString());
        models.add(model);
        return http.StreamedResponse(
          () async* {
            if (model == 'A') {
              yield _delta('  \n');
              throw http.ClientException('断开');
            }
            yield _delta('完整回答');
            yield utf8.encode('data: [DONE]\n\n');
          }(),
          200,
        );
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(client.close);
    final chunks = await client
        .explainStream(config: _config, systemPrompt: '', userPrompt: '')
        .toList();
    expect(chunks, ['完整回答']);
    expect(models, ['A', 'B']);
    expect(promoted, ['B']);
  });

  test('流输出正文后断开不换模型，不上报成功', () async {
    final models = <String>[];
    final promoted = <String>[];
    final client = LlmClient(
      httpClient: MockClient.streaming((request, body) async {
        models.add(_model(await body.bytesToString()));
        return http.StreamedResponse(
          () async* {
            yield _delta('已经生成的内容');
            throw http.ClientException('中断');
          }(),
          200,
        );
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(client.close);
    await expectLater(
      client.chatStream(config: _config, systemPrompt: '', messages: const []),
      emitsInOrder(
        ['已经生成的内容', emitsError(isA<LlmNetworkError>()), emitsDone],
      ),
    );
    expect(models, ['A']);
    expect(promoted, isEmpty);
  });

  for (final status in [200, 500]) {
    test('会话在HTTP $status返回前失效，不重试也不保存', () async {
      var active = true;
      final models = <String>[];
      final promoted = <String>[];
      final client = LlmClient(
        isActive: () => active,
        httpClient: MockClient((request) async {
          models.add(_model(request.body));
          active = false;
          return status == 200
              ? _completion('晚到的结果')
              : http.Response('', status);
        }),
        onModelSucceeded: (_, model) async => promoted.add(model),
      );
      addTearDown(client.close);
      await expectLater(
        client.explain(config: _config, systemPrompt: '', userPrompt: ''),
        throwsA(isA<LlmGenerationCancelled>()),
      );
      expect(models, ['A']);
      expect(promoted, isEmpty);
    });
  }

  test('工具探测切换只记住本轮模型，最终流成功才上报', () async {
    final requests = <String>[];
    final promoted = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        final stream = body['stream'] == true;
        requests.add('$model:$stream');
        if (model == 'A') return http.Response('', 500);
        if (!stream) return _completion('探测结果');
        return http.Response.bytes(
          [..._delta('最终回答'), ...utf8.encode('data: [DONE]\n\n')],
          200,
        );
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(client.close);
    await client
        .chatComplete(config: _config, systemPrompt: '', messages: const []);
    expect(promoted, isEmpty);
    final text = await client.chatStream(
      config: _config,
      systemPrompt: '',
      messages: const [],
    ).join();
    expect(text, '最终回答');
    expect(requests, ['A:false', 'B:false', 'B:true']);
    expect(promoted, ['B']);
  });

  test('自动保存失败不丢弃有效回答', () async {
    final client = LlmClient(
      httpClient: MockClient(
        (request) async => _model(request.body) == 'A'
            ? http.Response('', 500)
            : _completion('有效结果'),
      ),
      onModelSucceeded: (_, __) async => throw StateError('保存不可用'),
    );
    addTearDown(client.close);
    expect(
      (await client.explain(
        config: _config,
        systemPrompt: '',
        userPrompt: '',
      ))
          .text,
      '有效结果',
    );
  });

  test('连接测试仍只测试指定模型，不自动切换或提升', () async {
    final models = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        models.add(_model(request.body));
        return http.Response('', 503);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.testConnection(_config),
      throwsA(isA<LlmServerError>()),
    );
    expect(models, ['A']);
  });
}
