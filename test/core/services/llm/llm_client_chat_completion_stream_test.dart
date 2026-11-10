import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';
import 'package:poemath/core/services/llm/chat_completion.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';

const _config = LlmConfig(
  baseUrl: 'https://vision.example.com/v1',
  apiKey: 'synthetic-vision-key',
  model: 'gpt-4o-mini',
);
const _messages = [ChatMessage(role: ChatRole.user, content: '请编写看图说话题目')];

class _LocalHttp extends HttpOverrides {}

Future<ChatCompletion> _complete(
  LlmClient client, {
  LlmConfig config = _config,
  List<ChatMessage> messages = _messages,
  bool requiresVision = false,
}) => client.chatComplete(
  config: config,
  systemPrompt: '只输出完整题目的 JSON',
  messages: messages,
  maxTokens: 3000,
  requiresVision: requiresVision,
  stream: true,
);

String _event(Object data) => 'data: ${jsonEncode(data)}\n\n';

String _delta(String content) => _event({
  'choices': [
    {
      'index': 0,
      'delta': {'content': content},
      'finish_reason': null,
    },
  ],
});

String _finish(String reason) => _event({
  'choices': [
    {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': reason},
  ],
});

http.StreamedResponse _response(
  String body, {
  Map<String, String> headers = const {
    'content-type': 'text/event-stream; charset=utf-8',
  },
  int chunkSize = 7,
}) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable([
      for (var offset = 0; offset < bytes.length; offset += chunkSize)
        bytes.sublist(offset, (offset + chunkSize).clamp(0, bytes.length)),
    ]),
    200,
    headers: headers,
  );
}

void main() {
  for (final failure in ['error', 'eof']) {
    test('完整文本 SSE $failure 后普通响应恢复，同批记住传输方式且不拼接片段', () async {
      final bodies = <Map<String, dynamic>>[];
      final attempts = <int>[];
      var accepted = 0;
      final client = LlmClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          expect(request.headers['Authorization'], 'Bearer ${_config.apiKey}');
          return http.Response(
            body['stream'] == true
                ? _delta('不应保留的片段') +
                      (failure == 'error'
                          ? _event({
                              'error': {'type': 'server_error'},
                            })
                          : '')
                : jsonEncode({
                    'choices': [
                      {
                        'message': {'content': '{"title":"完整题目"}'},
                        'finish_reason': 'stop',
                      },
                    ],
                  }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        onCompletionAccepted: (_, _, {onSelectionSaved}) async => accepted++,
      );
      addTearDown(client.close);
      Future<ChatCompletion> complete() => client.chatComplete(
        config: _config,
        systemPrompt: '测试',
        messages: _messages,
        stream: true,
        retryWithoutStreaming: true,
        onAttempt: attempts.add,
        validate: (response) {
          expect(jsonDecode(response.content!), {'title': '完整题目'});
        },
      );
      final first = await complete();
      expect(accepted, 0);
      await client.acceptCompletion(first);
      expect(accepted, 1);
      final second = await complete();
      expect(second.content, first.content);
      expect(bodies.map((body) => body['stream']), [true, null, null]);
      expect({...bodies.first}..remove('stream'), bodies[1]);
      expect(bodies[1], bodies[2]);
      expect(attempts, [1, 2, 1]);
      await expectLater(
        client.chatComplete(
          config: _config,
          systemPrompt: '测试',
          messages: _messages,
          stream: true,
          retryWithoutStreaming: true,
          tools: const [
            {'type': 'function'},
          ],
        ),
        throwsArgumentError,
      );
      expect(bodies, hasLength(3));
    });
  }

  test('流式和普通响应均失败后继续其他厂商，成功后才回写', () async {
    const config = LlmConfig(
      baseUrl: 'https://first.example.com/v1',
      apiKey: 'first-key',
      model: 'gpt-4o-mini',
      fallbacks: [_config],
    );
    final calls = <String>[];
    final accepted = <String>[];
    final client = LlmClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final streaming = body['stream'] == true;
        calls.add('${request.url.host}:$streaming');
        if (request.url.host == 'first.example.com') {
          expect(request.headers['Authorization'], 'Bearer first-key');
          return http.Response(
            _event({
              'error': {'type': 'server_error'},
            }),
            streaming ? 200 : 503,
          );
        }
        expect(request.headers['Authorization'], 'Bearer ${_config.apiKey}');
        return http.Response(
          _delta('完整回答') + _finish('stop'),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }),
      onSelectionSucceeded: (_, successful) async {
        accepted.add(successful.baseUrl);
      },
    );
    addTearDown(client.close);
    final attempts = <int>[];
    final result = await client.chatComplete(
      config: config,
      systemPrompt: '测试',
      messages: _messages,
      stream: true,
      retryWithoutStreaming: true,
      onAttempt: attempts.add,
    );
    expect(result.content, '完整回答');
    expect(calls, [
      'first.example.com:true',
      'first.example.com:false',
      'vision.example.com:true',
    ]);
    expect(attempts, [1, 2, 3]);
    expect(accepted, isEmpty);
    await client.acceptCompletion(result);
    expect(accepted, [_config.baseUrl]);
  });

  test('兼容重试开始前取消，不发送第二次请求', () async {
    var calls = 0;
    final client = LlmClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(
          _event({
            'error': {'type': 'server_error'},
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.chatComplete(
        config: _config,
        systemPrompt: '测试',
        messages: _messages,
        stream: true,
        retryWithoutStreaming: true,
        onAttempt: (attempt) {
          if (attempt == 2) client.close();
        },
      ),
      throwsA(isA<LlmGenerationCancelled>()),
    );
    expect(calls, 1);
  });

  for (final reason in ['length', 'content_filter']) {
    for (final streaming in [true, false]) {
      test('明确未完整结束不触发兼容重试或接受部分回答：$reason/$streaming', () async {
        var calls = 0;
        final client = LlmClient(
          httpClient: MockClient((_) async {
            calls++;
            return http.Response(
              streaming
                  ? _delta('{"title":"部分回答"}') + _finish(reason)
                  : jsonEncode({
                      'choices': [
                        {
                          'message': {'content': '{"title":"部分回答"}'},
                          'finish_reason': reason,
                        },
                      ],
                    }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(client.close);
        await expectLater(
          client.chatComplete(
            config: _config,
            systemPrompt: '测试',
            messages: _messages,
            stream: streaming,
            retryWithoutStreaming: true,
          ),
          throwsA(isA<LlmResponseFormatError>()),
        );
        expect(calls, 1);
      });
    }
  }

  for (final streaming in [false, true]) {
    test('DNS 失败跳过同厂商其他模型，备用成功后才回写：$streaming', () async {
      const config = LlmConfig(
        baseUrl: 'https://unreachable.example.com/v1',
        apiKey: 'synthetic-vision-key',
        model: 'gpt-4o',
        models: ['gpt-4o', 'gpt-4.1'],
        fallbacks: [
          LlmConfig(
            baseUrl: 'https://backup.example.com/v1',
            apiKey: 'backup-key',
            model: 'gpt-4o-mini',
          ),
        ],
      );
      DiagnosticBuffer.instance.clear();
      final calls = <String>[];
      final accepted = <String>[];
      final client = LlmClient(
        httpClient: MockClient((request) async {
          calls.add((jsonDecode(request.body) as Map)['model'] as String);
          if (request.url.host == 'unreachable.example.com') {
            throw const SocketException("Failed host lookup: 'private-host'");
          }
          return http.Response(
            streaming
                ? _delta('有效回答') + _finish('stop')
                : jsonEncode({
                    'choices': [
                      {
                        'message': {'content': '有效回答'},
                      },
                    ],
                  }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        onSelectionSucceeded: (_, successful) async {
          accepted.add(successful.baseUrl);
        },
      );
      addTearDown(client.close);
      final result = await client.chatComplete(
        config: config,
        systemPrompt: '测试',
        messages: _messages,
        stream: streaming,
      );
      expect(result.content, '有效回答');
      expect(calls, ['gpt-4o', 'gpt-4o-mini']);
      expect(accepted, isEmpty);
      await client.acceptCompletion(result);
      expect(accepted, ['https://backup.example.com/v1']);
      final diagnostics = DiagnosticBuffer.instance.exportAsText();
      expect(diagnostics, contains('无法解析模型服务地址'));
      expect(diagnostics, isNot(contains('private-host')));
      expect(diagnostics, isNot(contains(config.apiKey)));
    });

    test('全部 DNS 失败保留明确且安全的错误类型：$streaming', () async {
      final client = LlmClient(
        httpClient: MockClient((_) async {
          throw const SocketException("Failed host lookup: 'private-host'");
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.chatComplete(
          config: _config,
          systemPrompt: '测试',
          messages: _messages,
          stream: streaming,
        ),
        throwsA(
          isA<LlmHostLookupError>().having(
            (error) => error.message,
            'message',
            '无法解析模型服务地址，请检查网络或 DNS 后重试',
          ),
        ),
      );
    });
  }

  for (final mode in [
    'complete',
    'streamed complete',
    'SSE complete',
    'explain',
  ]) {
    test(
      'HTTP 200 JSON error in $mode never exposes upstream secrets',
      () async {
        DiagnosticBuffer.instance.clear();
        final client = LlmClient(
          httpClient: MockClient((request) async {
            expect(
              request.headers['Authorization'],
              'Bearer ${_config.apiKey}',
            );
            final error = {
              'error': {'message': '${_config.apiKey} provider-private-detail'},
            };
            return http.Response(
              mode == 'SSE complete' ? _event(error) : jsonEncode(error),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.close);
        final Future<Object> response = mode == 'explain'
            ? client.explain(
                config: _config,
                systemPrompt: '测试',
                userPrompt: '测试',
              )
            : client.chatComplete(
                config: _config,
                systemPrompt: '测试',
                messages: _messages,
                stream: mode != 'complete',
              );
        await expectLater(
          response,
          throwsA(
            isA<LlmResponseFormatError>().having(
              (error) => error.message,
              'message',
              '模型服务返回错误，请稍后重试或请家长检查配置',
            ),
          ),
        );
        final diagnostics = DiagnosticBuffer.instance.exportAsText();
        expect(diagnostics, contains('模型服务返回错误'));
        expect(diagnostics, isNot(contains(_config.apiKey)));
        expect(diagnostics, isNot(contains('provider-private-detail')));
      },
    );
  }

  test('汇总 SSE 后返回完整 JSON；中文跨字节、多行事件、空帧和统计帧均兼容', () async {
    late Map<String, dynamic> requestBody;
    late Map<String, String> headers;
    final client = LlmClient(
      httpClient: MockClient.streaming((request, body) async {
        requestBody =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        headers = request.headers;
        return _response(
          '\uFEFF: keep-alive\r\n\r\n'
          'event: message\r\nid: 1\r\n'
          'data: {"choices":[\r\n'
          'data: {"delta":{"role":"assistant","content":""}}]}\r\n\r\n'
          '${_delta('{"title":"雨天互助🌧️",')}'
          '${_delta('"questions":["你看到了什么？"]}')}'
          '${_event({
            'choices': <Object?>[],
            'usage': {'total_tokens': 40},
          })}'
          'data:\n\n'
          'data: [DONE]',
          // 格式按实际 body 识别，也兼容服务误标 Content-Type。
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);
    final result = await _complete(client);
    expect(result.content, '{"title":"雨天互助🌧️","questions":["你看到了什么？"]}');
    expect(jsonDecode(result.content!), {
      'title': '雨天互助🌧️',
      'questions': ['你看到了什么？'],
    });
    expect(result.toolCalls, isEmpty);
    expect(requestBody['stream'], isTrue);
    expect(requestBody['max_tokens'], 3000);
    expect((requestBody['messages'] as List).last, _messages.single.toJson());
    expect(headers['authorization'], 'Bearer ${_config.apiKey}');
    expect(jsonEncode(requestBody), isNot(contains(_config.apiKey)));
  });

  for (final streaming in [false, true]) {
    test('HTTP 200 限额通知按失败回退，只有通过业务校验的模型可接受：$streaming', () async {
      const config = LlmConfig(
        baseUrl: 'https://vision.example.com/v1',
        apiKey: 'synthetic-vision-key',
        model: 'gpt-4o-mini',
        models: ['gpt-4o-mini', 'gpt-4o'],
      );
      final attempts = <String>[];
      final accepted = <String>[];
      final client = LlmClient(
        httpClient: MockClient.streaming((request, body) async {
          final model =
              (jsonDecode(await body.bytesToString()) as Map)['model'];
          attempts.add(model as String);
          final content = attempts.length == 1
              ? "You've used your daily chat limit. Please try again later."
              : '{"questions":["你看到了什么？"]}';
          return _response(
            streaming
                ? _delta(content) + _finish('stop')
                : jsonEncode({
                    'choices': [
                      {
                        'message': {'content': content},
                        'finish_reason': 'stop',
                      },
                    ],
                  }),
          );
        }),
        onModelSucceeded: (_, model) async => accepted.add(model),
      );
      addTearDown(client.close);
      var validations = 0;
      final result = await client.chatComplete(
        config: config,
        systemPrompt: '只输出 JSON',
        messages: _messages,
        stream: streaming,
        validate: (reply) {
          validations++;
          expect(jsonDecode(reply.content!)['questions'], isNotEmpty);
        },
      );
      expect(attempts, ['gpt-4o-mini', 'gpt-4o']);
      expect(validations, 1);
      expect(accepted, isEmpty);
      await client.acceptCompletion(result);
      expect(accepted, ['gpt-4o']);
    });
  }

  for (final status in [200, 429]) {
    test('无备用模型时限额错误有明确提示，不泄漏服务响应：HTTP $status', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                status == 200
                    ? _delta(
                            "You've used your daily chat limit. Please try again later.",
                          ) +
                          _finish('stop')
                    : 'synthetic-vision-key private-provider-detail',
              ),
            ),
            status,
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        _complete(client),
        throwsA(
          isA<LlmRateLimitError>().having(
            (error) => error.message,
            'message',
            '模型服务额度已用尽或请求受限，请切换模型或稍后重试',
          ),
        ),
      );
    });
  }

  test('有效 JSON 中引用限额文字不被当作上游限额通知', () async {
    final content = jsonEncode({
      'quote': "You've used your daily chat limit. Please try again later.",
    });
    final client = LlmClient(
      httpClient: MockClient.streaming(
        (_, __) async => _response(_delta(content) + _finish('stop')),
      ),
    );
    addTearDown(client.close);
    expect((await _complete(client)).content, content);
  });

  test('业务格式校验失败会用相同视觉请求回退，坏内容不会被记为成功', () async {
    const config = LlmConfig(
      baseUrl: 'https://vision.example.com/v1',
      apiKey: 'synthetic-vision-key',
      model: 'gpt-4o-mini',
      models: ['gpt-4o-mini', 'gpt-4o'],
    );
    final attempts = <String>[];
    final client = LlmClient(
      httpClient: MockClient.streaming((_, body) async {
        final request = jsonDecode(await body.bytesToString()) as Map;
        attempts.add(request['model'] as String);
        expect(request['messages'].last, _messages.single.toJson());
        return _response(
          _delta(
                attempts.length == 1
                    ? 'synthetic-vision-key invalid JSON'
                    : '{"questions":["你看到了什么？"]}',
              ) +
              _finish('stop'),
        );
      }),
    );
    addTearDown(client.close);
    final result = await client.chatComplete(
      config: config,
      systemPrompt: '只输出 JSON',
      messages: _messages,
      requiresVision: true,
      stream: true,
      validate: (reply) => jsonDecode(reply.content!),
    );
    expect(attempts, ['gpt-4o-mini', 'gpt-4o']);
    expect(jsonDecode(result.content!)['questions'], isNotEmpty);
  });

  for (final (name, terminal) in [
    ('DONE', 'data: [DONE]\n\n'),
    ('stop', _finish('stop')),
  ]) {
    test('收到 $name 即可完成并释放尚未关闭的 HTTP 流', () async {
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () => cancelled.complete(),
      );
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (_, __) async => http.StreamedResponse(body.stream, 200),
        ),
      );
      addTearDown(client.close);
      final result = _complete(client);
      body.add(utf8.encode(_delta('{"title":"完成"}') + terminal));
      expect(
        (await result.timeout(const Duration(seconds: 2))).content,
        '{"title":"完成"}',
      );
      await cancelled.future.timeout(const Duration(seconds: 2));
      await body.close();
    });
  }

  test('省略 delta 的 stop 结束帧可以完成文本', () async {
    final client = LlmClient(
      httpClient: MockClient.streaming(
        (_, __) async => _response(
          '${_delta('{"title":"完成"}')}'
          '${_event({
            'choices': [
              {'index': 0, 'finish_reason': 'stop'},
            ],
          })}',
        ),
      ),
    );
    addTearDown(client.close);
    expect((await _complete(client)).content, '{"title":"完成"}');
  });

  for (final headers in [
    const <String, String>{},
    const {'content-type': 'application/json; charset=utf-8'},
  ]) {
    test('请求流式时仍可接受普通 JSON 响应，完整长文本不会按 SSE 行截断：$headers', () async {
      final content = '图' * (70 * 1024);
      final client = LlmClient(
        httpClient: MockClient.streaming(
          (_, __) async => _response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': content},
                },
              ],
            }),
            headers: headers,
            chunkSize: 4096,
          ),
        ),
      );
      addTearDown(client.close);
      expect((await _complete(client)).content, content);
    });
  }

  test('大图完整进入视觉请求；失败模型片段丢弃，按视觉候选与供应商独立回退', () async {
    final imageUrl =
        'data:image/png;base64,${base64Encode(List<int>.filled(512 * 1024, 7))}';
    final messages = [
      ChatMessage(
        role: ChatRole.user,
        content: '观察实际图片',
        contentParts: [
          {'type': 'text', 'text': '观察实际图片'},
          {
            'type': 'image_url',
            'image_url': {'url': imageUrl},
          },
        ],
      ),
    ];
    const config = LlmConfig(
      baseUrl: 'https://first.example/v1',
      apiKey: 'first-private-key',
      model: 'text-only',
      models: ['text-only', 'gpt-4o-mini', 'gpt-4o'],
      fallbacks: [
        LlmConfig(
          baseUrl: 'https://second.example/v1',
          apiKey: 'second-private-key',
          model: 'text-only',
          models: ['text-only', 'gpt-4o-mini'],
        ),
      ],
    );
    final attempts = <String>[];
    var promoted = false;
    final client = LlmClient(
      httpClient: MockClient.streaming((request, body) async {
        final raw = await body.bytesToString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        attempts.add('${request.url.host}:${data['model']}');
        expect(data['stream'], isTrue);
        expect((data['messages'] as List).last, messages.single.toJson());
        expect(raw, isNot(contains('first-private-key')));
        expect(raw, isNot(contains('second-private-key')));
        expect(
          request.headers['authorization'],
          request.url.host == 'first.example'
              ? 'Bearer first-private-key'
              : 'Bearer second-private-key',
        );
        if (attempts.length == 1) {
          // 第一模型给出的 JSON 甚至已闭合，缺少结束信号仍不可返回。
          return _response(_delta('{"title":"失败模型的片段"}'));
        }
        if (request.url.host == 'first.example') {
          return http.StreamedResponse(const Stream.empty(), 401);
        }
        return _response(_delta('{"title":"第二家服务的完整题目"}') + _finish('stop'));
      }),
      onSelectionSucceeded: (_, __) async => promoted = true,
    );
    addTearDown(client.close);
    final result = await _complete(
      client,
      config: config,
      messages: messages,
      requiresVision: true,
    );
    expect(result.content, '{"title":"第二家服务的完整题目"}');
    expect(attempts, [
      'first.example:gpt-4o-mini',
      'first.example:gpt-4o',
      'second.example:gpt-4o-mini',
    ]);
    expect(promoted, isFalse);
  });

  test('业务确认只保存本客户端对应响应的实际成功模型，重复确认只保存一次', () async {
    const config = LlmConfig(
      baseUrl: 'https://first.example/v1',
      apiKey: '',
      model: 'gpt-4o-mini',
      fallbacks: [
        LlmConfig(
          baseUrl: 'https://second.example/v1',
          apiKey: '',
          model: 'gpt-4o-mini',
        ),
      ],
    );
    const laterConfig = LlmConfig(
      baseUrl: 'https://third.example/v1',
      apiKey: '',
      model: 'gpt-4o-mini',
    );
    final saved = <(LlmConfig, String, String)>[];
    var legacyNotifications = 0;
    final client = LlmClient(
      httpClient: MockClient.streaming((request, _) async {
        if (request.url.host == 'first.example') {
          return http.StreamedResponse(const Stream.empty(), 503);
        }
        return _response(_delta('{"title":"完整题目"}') + _finish('stop'));
      }),
      onSelectionSucceeded: (_, _) async => legacyNotifications++,
      onCompletionAccepted: (request, successful, {onSelectionSaved}) async {
        saved.add((request, successful.baseUrl, successful.model));
        onSelectionSaved?.call('saved-selection');
      },
    );
    final otherClient = LlmClient();
    addTearDown(client.close);
    addTearDown(otherClient.close);
    final first = await _complete(client, config: config);
    final later = await _complete(client, config: laterConfig);
    expect(saved, isEmpty);
    await client.acceptCompletion(ChatCompletion(content: first.content));
    await otherClient.acceptCompletion(first);
    expect(saved, isEmpty);
    String? signature;
    await client.acceptCompletion(
      first,
      onSelectionSaved: (value) => signature = value,
    );
    await client.acceptCompletion(first);
    expect(saved.length, 1);
    expect(saved.single.$1, same(config));
    expect(saved.single.$2, 'https://second.example/v1');
    expect(saved.single.$3, 'gpt-4o-mini');
    expect(signature, 'saved-selection');
    await client.acceptCompletion(later);
    expect(saved.length, 2);
    expect(saved.last.$1, same(laterConfig));
    expect(saved.last.$2, 'https://third.example/v1');
    expect(legacyNotifications, 0);
  });

  test('切换模型提示期间取消，不发送下一次请求或保存默认模型', () async {
    var active = true;
    var requests = 0;
    var promotions = 0;
    final attempts = <int>[];
    final client = LlmClient(
      isActive: () => active,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 503);
      }),
      onSelectionSucceeded: (_, _) async => promotions++,
    );
    addTearDown(client.close);
    await expectLater(
      client.chatComplete(
        config: const LlmConfig(
          baseUrl: 'https://vision.example.com/v1',
          apiKey: '',
          model: 'gpt-4o-mini',
          models: ['gpt-4o-mini', 'gpt-4o'],
        ),
        systemPrompt: '',
        messages: _messages,
        onAttempt: (attempt) {
          attempts.add(attempt);
          if (attempt == 2) active = false;
        },
      ),
      throwsA(isA<LlmGenerationCancelled>()),
    );
    expect(attempts, [1, 2]);
    expect(requests, 1);
    expect(promotions, 0);
  });

  for (final (name, body) in [
    ('空输出', 'data: [DONE]\n\n'),
    ('缺少结束信号', _delta('{"title":"没有结束信号"}')),
    ('长度截断', _delta('{"title":"达到长度上限"}') + _finish('length')),
    ('内容过滤', _delta('{"title":"被截断的内容"}') + _finish('content_filter')),
    (
      '错误事件',
      '${_delta('{"title":"服务随后报错"}')}'
          '${_event({
            'error': {'message': 'synthetic-vision-key provider-private-detail'},
          })}'
          'data: [DONE]\n\n',
    ),
    (
      '损坏数据帧',
      '${_delta('{"title":"坏帧不能忽略"}')}data: malformed-json\n\n'
          'data: [DONE]\n\n',
    ),
  ]) {
    test('SSE $name 不返回题目，也不泄漏服务响应', () async {
      final client = LlmClient(
        httpClient: MockClient.streaming((_, __) async => _response(body)),
      );
      addTearDown(client.close);
      await expectLater(
        _complete(client),
        throwsA(
          isA<LlmResponseFormatError>()
              .having(
                (error) => error.message,
                'message',
                isNot(contains(_config.apiKey)),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('provider-private-detail')),
              ),
        ),
      );
    });
  }

  test('接收中关闭客户端会取消传输，不能返回片段或请求下一个模型', () async {
    final entered = Completer<void>();
    final cancelled = Completer<void>();
    final body = StreamController<List<int>>(
      onCancel: () => cancelled.complete(),
    );
    var requests = 0;
    final client = LlmClient(
      httpClient: MockClient.streaming((_, __) async {
        requests++;
        entered.complete();
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    addTearDown(client.close);
    final pending = expectLater(
      _complete(
        client,
        config: LlmConfig(
          baseUrl: _config.baseUrl,
          apiKey: _config.apiKey,
          model: _config.model,
          models: [_config.model, 'gpt-4o'],
        ),
      ),
      throwsA(isA<LlmGenerationCancelled>()),
    );
    await entered.future;
    body.add(utf8.encode(_delta('{"title":"尚未完成"}')));
    await Future<void>.delayed(Duration.zero);
    client.close();
    await pending;
    await cancelled.future.timeout(const Duration(seconds: 2));
    expect(requests, 1);
    await body.close();
  });

  test('持续心跳仍受整个请求的超时限制', () async {
    final client = LlmClient(
      chatTimeout: const Duration(milliseconds: 50),
      httpClient: MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          Stream<List<int>>.periodic(
            const Duration(milliseconds: 5),
            (_) => utf8.encode(': keep-alive\n\n'),
          ),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    await expectLater(_complete(client), throwsA(isA<LlmNetworkError>()));
  });

  test('超过响应预算立即停止，不耗费下一个模型的请求', () async {
    var requests = 0;
    final client = LlmClient(
      httpClient: MockClient.streaming((_, __) async {
        requests++;
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(': ignored\n\n')),
          200,
          contentLength: 2 * 1024 * 1024 + 1,
        );
      }),
    );
    addTearDown(client.close);
    await expectLater(
      _complete(
        client,
        config: const LlmConfig(
          baseUrl: 'https://vision.example.com',
          apiKey: '',
          model: 'gpt-4o-mini',
          models: ['gpt-4o-mini', 'gpt-4o'],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(requests, 1);
  });

  test('流式完整文本接口不会把工具调用参数交给流式解析器', () async {
    var requests = 0;
    final client = LlmClient(
      httpClient: MockClient.streaming((_, __) async {
        requests++;
        return _response(_delta('无效调用') + _finish('stop'));
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.chatComplete(
        config: _config,
        systemPrompt: '',
        messages: _messages,
        tools: const [
          {'type': 'function'},
        ],
        stream: true,
      ),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  test('真实 HTTP 响应保持开放时，收到 DONE 就返回完整题目', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final entered = Completer<HttpRequest>();
    final subscription = server.listen(entered.complete);
    final transport = HttpOverrides.runWithHttpOverrides(
      IOClient.new,
      _LocalHttp(),
    );
    final client = LlmClient(httpClient: transport);
    addTearDown(() async {
      client.close();
      transport.close();
      await subscription.cancel();
      await server.close(force: true);
    });
    final pending = _complete(
      client,
      config: LlmConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: '',
        model: _config.model,
      ),
    );
    final request = await entered.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('真实 HTTP 请求未到达'),
    );
    expect(request.method, 'POST');
    expect(request.uri.path, '/v1/chat/completions');
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    expect(body['stream'], isTrue);
    expect((body['messages'] as List).last, _messages.single.toJson());
    final response = request.response;
    // Dart HttpResponse 的小分片会先缓冲；SSE 需即时发往真实连接。
    response.bufferOutput = false;
    // 服务保持响应开放，客户端读到 DONE 后取消会使服务端收到断开通知。
    final disconnected = response.done.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.add(utf8.encode(_delta('{"title":"真实连接上的中文题目"}')));
    await response.flush();
    response.add(utf8.encode('data: [DONE]\n\n'));
    await response.flush();
    expect(
      (await pending.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('SSE DONE 后客户端未完成'),
      )).content,
      '{"title":"真实连接上的中文题目"}',
    );
    // 已在 response.close() 前取得完整结果，接收不依赖服务端关闭响应。
    await response.close();
    await disconnected;
  });
}
