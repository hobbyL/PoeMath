import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
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
}) =>
    client.chatComplete(
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
        bytes.sublist(
          offset,
          (offset + chunkSize).clamp(0, bytes.length),
        ),
    ]),
    200,
    headers: headers,
  );
}

void main() {
  for (final mode in ['complete', 'streamed complete', 'explain']) {
    test('HTTP 200 JSON error in $mode never exposes upstream secrets',
        () async {
      final client = LlmClient(
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer ${_config.apiKey}');
          return http.Response(
            jsonEncode({
              'error': {'message': '${_config.apiKey} provider-private-detail'},
            }),
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
              stream: mode == 'streamed complete',
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
    });
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
    expect(
      result.content,
      '{"title":"雨天互助🌧️","questions":["你看到了什么？"]}',
    );
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
        return _response(
          _delta('{"title":"第二家服务的完整题目"}') + _finish('stop'),
        );
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
            'error': {
              'message': 'synthetic-vision-key provider-private-detail',
            },
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
      ))
          .content,
      '{"title":"真实连接上的中文题目"}',
    );
    // 已在 response.close() 前取得完整结果，接收不依赖服务端关闭响应。
    await response.close();
    await disconnected;
  });
}
