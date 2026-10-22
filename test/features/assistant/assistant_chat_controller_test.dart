// test/features/assistant/assistant_chat_controller_test.dart
//
// AI 助手对话控制器测试：
// - 令牌护栏（stop 固化部分回答后晚到分片不污染；切新会话丢弃在途流）
// - unconfigured 引导态（保留 user 气泡、不发请求）
// - 错误映射（5xx → error，文案不泄露 API Key）
// - regenerate（截掉末尾 assistant，用最后一条 user 重跑）
// 以及请求契约（system 首条 + 多轮历史 + stream:true + max_tokens 档）、
// 自定义 prompt 覆盖、在途防重入、空白输入忽略。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/prompts/assistant_prompt_defaults.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> keys = {};

  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {
    keys[configId] = apiKey;
  }

  @override
  Future<String?> readLlmApiKeyFor(String configId) =>
      Future.value(keys[configId]);

  @override
  Future<void> deleteLlmApiKeyFor(String configId) async {
    keys.remove(configId);
  }

  @override
  Future<String?> readLlmApiKey() => Future.value(null);
}

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

/// 把整段回答包装成「单片 + [DONE]」的 OpenAI 兼容 SSE 响应。
http.Response _sseResponse(String content) => http.Response.bytes(
      utf8.encode('${_sseData(content)}data: [DONE]\n\n'),
      200,
      headers: const {'content-type': 'text/event-stream; charset=utf-8'},
    );

/// 判定请求体是否为流式（chatStream 发 stream:true；chatComplete 不发）。
/// 控制器现为两跳：先非流式 chatComplete 判定工具，再流式 chatStream 收尾，
/// 假 client 据此分别回放 JSON 补全 / SSE。
bool _isStream(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map && decoded['stream'] == true;
  } catch (_) {
    return false;
  }
}

/// 一个 OpenAI `tool_calls[i]` wire 结构。
Map<String, Object?> _toolCallWire(
  String id,
  String name, [
  String args = '{}',
]) =>
    <String, Object?>{
      'id': id,
      'type': 'function',
      'function': <String, Object?>{'name': name, 'arguments': args},
    };

/// 非流式 chatComplete JSON 响应：无 tool_calls（content 占位，判定为纯聊天）
/// 或携带 tool_calls（content 置空，驱动工具循环）。
http.Response _completionResponse({
  String? content = '占位',
  List<Map<String, Object?>> toolCalls = const [],
}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'content': toolCalls.isEmpty ? content : null,
                if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
              },
            },
          ],
        }),
      ),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// [_completionResponse] 的 StreamedResponse 版本（MockClient.streaming 用）：
/// chatComplete 走 post 读满有限流，不会卡在手工喂片的 StreamController 上。
http.StreamedResponse _completionStreamed() {
  final res = _completionResponse();
  return http.StreamedResponse(
    Stream<List<int>>.value(res.bodyBytes),
    200,
    headers: res.headers,
  );
}

void main() {
  late _MemoryCredentialStore store;

  setUp(() async {
    await setUpHiveForTesting();
    store = _MemoryCredentialStore();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  /// 预置两条厂商配置（p1 自动成为生效配置）。
  Future<void> seedProviders() async {
    final repo = SettingsRepository(credentialStore: store);
    await repo.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
      apiKey: 'key-p1',
    );
  }

  ProviderContainer containerWith(http.Client client) {
    final container = ProviderContainer(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(store),
        llmExplainHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('仅重试失败单跳，工具不重放，最终回答成功才提升默认并刷新选择', () async {
    final repo = SettingsRepository(credentialStore: store);
    await repo.saveLlmProviderConfig(
      id: 'p1',
      name: 'Provider',
      baseUrl: 'https://example.com',
      model: 'A',
      models: ['A', 'B', 'C'],
      apiKey: 'key',
    );
    await repo.setScenarioSelection(
      LlmScenario.assistant,
      providerId: 'p1',
      model: 'A',
    );
    final requests = <String>[];
    final container = containerWith(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        final stream = body['stream'] == true;
        requests.add('$model:$stream');
        // 探测/工具执行/下一跳探测都不写默认，直到最终流完成。
        expect(repo.llmProviders.single.model, 'A');
        if (model == 'A' || (model == 'B' && stream)) {
          return http.Response('', 503);
        }
        final hasTool = (body['messages'] as List)
            .any((message) => message['role'] == 'tool');
        if (hasTool) {
          expect(
            (body['messages'] as List)
                .where((message) => message['role'] == 'tool'),
            hasLength(1),
          );
          return stream ? _sseResponse('完整回答') : _completionResponse();
        }
        return _completionResponse(
          toolCalls: [_toolCallWire('only-once', 'explain_mistake')],
        );
      }),
    );
    final settingsInstance = container.read(settingsRepositoryProvider);
    await container.read(assistantChatControllerProvider.notifier).send('讲讲错题');
    final state = container.read(assistantChatControllerProvider);
    expect(state.isReady, isTrue);
    expect(
      state.messages.where((message) => message.role == ChatRole.tool),
      hasLength(1),
    );
    expect(state.messages.last.content, '完整回答');
    expect(requests, ['A:false', 'B:false', 'B:false', 'B:true', 'C:true']);
    expect(repo.llmProviders.single.model, 'C');
    expect(repo.modelForScenario(LlmScenario.assistant), 'C');
    expect(container.read(llmSelectionVersionProvider), 1);
    expect(
      identical(container.read(settingsRepositoryProvider), settingsInstance),
      isTrue,
    );
  });

  test('已经有正文后中断保留部分回答，不重试或提升', () async {
    final repo = SettingsRepository(credentialStore: store);
    await repo.saveLlmProviderConfig(
      id: 'p1',
      name: '',
      baseUrl: 'https://example.com',
      model: 'A',
      models: ['A', 'B'],
      apiKey: '',
    );
    final requests = <String>[];
    final container = containerWith(
      MockClient.streaming((request, bodyStream) async {
        final wire = await bodyStream.bytesToString();
        final body = jsonDecode(wire) as Map;
        requests.add(body['model'] as String);
        if (!_isStream(wire)) return _completionStreamed();
        return http.StreamedResponse(
          () async* {
            yield utf8.encode(_sseData('已经生成'));
            throw http.ClientException('断开');
          }(),
          200,
        );
      }),
    );
    await container.read(assistantChatControllerProvider.notifier).send('提问');
    final state = container.read(assistantChatControllerProvider);
    expect(state.isError, isTrue);
    expect(state.streamingText, '已经生成');
    expect(requests, ['A', 'A']);
    expect(repo.llmProviders.single.model, 'A');
  });

  for (final cancel in ['停止', '销毁']) {
    test('$cancel后失败响应晚到，不切换备用模型或回写默认', () async {
      final repo = SettingsRepository(credentialStore: store);
      await repo.saveLlmProviderConfig(
        id: 'p1',
        name: '',
        baseUrl: 'https://example.com',
        model: 'A',
        models: ['A', 'B'],
        apiKey: '',
      );
      final started = Completer<void>();
      final response = Completer<http.Response>();
      var calls = 0;
      final container = containerWith(
        MockClient((_) {
          calls++;
          started.complete();
          return response.future;
        }),
      );
      final notifier = container.read(assistantChatControllerProvider.notifier);
      final pending = notifier.send('提问');
      await started.future;
      if (cancel == '停止') {
        notifier.stop();
      } else {
        container.invalidate(assistantChatControllerProvider);
      }
      response.complete(http.Response('', 503));
      await pending;
      expect(calls, 1);
      expect(repo.llmProviders.single.model, 'A');
      expect(container.read(llmSelectionVersionProvider), 0);
    });
  }

  test('send 成功：追加 user+assistant；契约 system 首条 / stream / 1024 / 发往 p1',
      () async {
    await seedProviders();
    late http.Request captured;
    final container = containerWith(
      MockClient((request) async {
        // chatComplete（非流式）先判定无工具；最终回答走 chatStream。
        if (!_isStream(request.body)) return _completionResponse();
        captured = request;
        return _sseResponse('你好呀，小朋友！');
      }),
    );

    await container.read(assistantChatControllerProvider.notifier).send('你好');

    final state = container.read(assistantChatControllerProvider);
    expect(state.isReady, isTrue);
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, ChatRole.user);
    expect(state.messages[0].content, '你好');
    expect(state.messages[1].role, ChatRole.assistant);
    expect(state.messages[1].content, '你好呀，小朋友！');
    expect(state.streamingText, isEmpty);

    expect(
      captured.url.toString(),
      'https://api.deepseek.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer key-p1');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['stream'], true);
    expect(body['model'], 'deepseek-chat');
    expect(body['max_tokens'], kAssistantMaxTokens);
    final messages = body['messages'] as List<dynamic>;
    expect(messages[0]['role'], 'system');
    expect(messages[0]['content'], kAssistantSystemPrompt);
    expect(messages[1]['role'], 'user');
    expect(messages[1]['content'], '你好');
    // key 绝不进请求体。
    expect(captured.body, isNot(contains('key-p1')));
  });

  test('多轮续问：请求体携带历史轮次（system + user + assistant + user）', () async {
    await seedProviders();
    late http.Request captured;
    var streamCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        captured = request;
        streamCall++;
        return _sseResponse(streamCall == 1 ? '第一答' : '第二答');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    await notifier.send('第一问');
    await notifier.send('第二问');

    final messages = (jsonDecode(captured.body)
        as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(messages, hasLength(4));
    expect(messages[0]['role'], 'system');
    expect(messages[1]['content'], '第一问');
    expect(messages[2]['role'], 'assistant');
    expect(messages[2]['content'], '第一答');
    expect(messages[3]['content'], '第二问');
  });

  test('清除上下文：清后下一轮只带 system + 新问（不含旧记录），消息记录仍保留', () async {
    await seedProviders();
    late http.Request captured;
    var streamCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        captured = request;
        streamCall++;
        return _sseResponse(streamCall == 1 ? '第一答' : '第二答');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    await notifier.send('第一问');
    final cleared = notifier.clearContext();
    expect(cleared, isTrue);
    await notifier.send('第二问');

    // 第二轮请求体只含 system + 第二问，旧记录（第一问/第一答）不入上下文。
    final messages = (jsonDecode(captured.body)
        as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(messages, hasLength(2));
    expect(messages[0]['role'], 'system');
    expect(messages[1]['content'], '第二问');

    // 记录仍保留：state.messages 完整 4 条，contextBaseIndex 停在清除点。
    final state = container.read(assistantChatControllerProvider);
    expect(state.messages, hasLength(4));
    expect(state.messages[0].content, '第一问');
    expect(state.messages[3].content, '第二答');
    expect(state.contextBaseIndex, 2);
  });

  test('清除上下文：空会话 / 已在末尾时返回 false，不动状态', () async {
    await seedProviders();
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        return _sseResponse('答');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    // 空会话：无可清。
    expect(notifier.clearContext(), isFalse);

    await notifier.send('问');
    expect(notifier.clearContext(), isTrue); // 首次清除生效
    expect(notifier.clearContext(), isFalse); // 已在末尾，再清为 no-op
  });

  test('未配置：unconfigured 态，保留 user 气泡且不发请求', () async {
    var requests = 0;
    final container = containerWith(
      MockClient((_) async {
        requests++;
        return _sseResponse('不该被调用');
      }),
    );

    await container.read(assistantChatControllerProvider.notifier).send('你好');

    final state = container.read(assistantChatControllerProvider);
    expect(state.isUnconfigured, isTrue);
    expect(state.message, contains('还没有配置 AI 服务'));
    expect(state.messages, hasLength(1)); // user 气泡保留
    expect(state.messages.single.content, '你好');
    expect(requests, 0);
  });

  test('服务端 5xx：error 态且文案不含 API Key；user 气泡保留', () async {
    await seedProviders();
    final container = containerWith(
      MockClient((_) async => http.Response.bytes(const [], 503)),
    );

    await container.read(assistantChatControllerProvider.notifier).send('你好');

    final state = container.read(assistantChatControllerProvider);
    expect(state.isError, isTrue);
    expect(state.message, isNotNull);
    expect(state.message, isNot(contains('key-p1')));
    expect(state.messages.single.content, '你好');
  });

  test('家长自定义 prompt 覆盖进入 system 首条', () async {
    await seedProviders();
    await SettingsRepository(credentialStore: store)
        .setAssistantPrompt('我的自定义助手人设');
    late http.Request captured;
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        captured = request;
        return _sseResponse('好的');
      }),
    );

    await container.read(assistantChatControllerProvider.notifier).send('你好');

    final messages = (jsonDecode(captured.body)
        as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(messages[0]['content'], '我的自定义助手人设');
  });

  test('regenerate：截掉末尾 assistant，用最后一条 user 重跑', () async {
    await seedProviders();
    var streamCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        streamCall++;
        return _sseResponse(streamCall == 1 ? '第一次回答' : '第二次回答');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    await notifier.send('出一道题');
    expect(
      container
          .read(assistantChatControllerProvider)
          .messages
          .map((m) => m.content)
          .toList(),
      ['出一道题', '第一次回答'],
    );

    await notifier.regenerate();
    final state = container.read(assistantChatControllerProvider);
    expect(state.isReady, isTrue);
    // 旧 assistant 被替换，user 不重复。
    expect(
      state.messages.map((m) => m.content).toList(),
      ['出一道题', '第二次回答'],
    );
    expect(streamCall, 2);
  });

  test('stop：固化已到增量为 assistant 消息，晚到分片不再改写（令牌护栏）', () async {
    await seedProviders();
    final sse = StreamController<List<int>>();
    final container = containerWith(
      MockClient.streaming((request, bodyStream) async {
        // chatComplete 先行（有限响应、无工具）；chatStream 消费手工喂的 sse。
        final body = utf8.decode(await bodyStream.toBytes());
        if (!_isStream(body)) return _completionStreamed();
        return http.StreamedResponse(sse.stream, 200);
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    final done = notifier.send('在吗');
    sse.add(utf8.encode(_sseData('在的')));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(assistantChatControllerProvider).isStreaming,
      isTrue,
    );
    expect(
      container.read(assistantChatControllerProvider).streamingText,
      '在的',
    );

    notifier.stop();
    final afterStop = container.read(assistantChatControllerProvider);
    expect(afterStop.isReady, isTrue);
    expect(afterStop.messages.last.role, ChatRole.assistant);
    expect(afterStop.messages.last.content, '在的');

    // 晚到分片：令牌已失配，await for 顶部校验直接 return，不改状态。
    sse.add(utf8.encode(_sseData('——晚到')));
    sse.add(utf8.encode('data: [DONE]\n\n'));
    await sse.close();
    await done;

    final finalState = container.read(assistantChatControllerProvider);
    expect(finalState.messages, hasLength(2)); // user + 固化的 assistant
    expect(finalState.messages.last.content, '在的'); // 未被晚到分片污染
  });

  test('切新会话后在途分片不写回旧状态（令牌护栏）', () async {
    await seedProviders();
    final sse = StreamController<List<int>>();
    final container = containerWith(
      MockClient.streaming((request, bodyStream) async {
        // chatComplete 先行（有限响应、无工具）；chatStream 消费手工喂的 sse。
        final body = utf8.decode(await bodyStream.toBytes());
        if (!_isStream(body)) return _completionStreamed();
        return http.StreamedResponse(sse.stream, 200);
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    final done = notifier.send('旧会话问题');
    sse.add(utf8.encode(_sseData('旧回答片段')));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(assistantChatControllerProvider).isStreaming,
      isTrue,
    );

    notifier.startNewConversation();
    expect(container.read(assistantChatControllerProvider).isIdle, isTrue);

    sse.add(utf8.encode(_sseData('更多旧片段')));
    sse.add(utf8.encode('data: [DONE]\n\n'));
    await sse.close();
    await done;

    final state = container.read(assistantChatControllerProvider);
    expect(state.isIdle, isTrue);
    expect(state.messages, isEmpty);
    expect(state.streamingText, isEmpty);
  });

  test('在途防重入：loading 中再次 send 不发第二次请求、不入历史', () async {
    await seedProviders();
    var requests = 0;
    final completer = Completer<http.Response>();
    final container = containerWith(
      MockClient((request) async {
        requests++;
        if (_isStream(request.body)) return _sseResponse('回答');
        return completer.future;
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    final first = notifier.send('第一问');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(assistantChatControllerProvider).isLoading, isTrue);

    await notifier.send('插队问');
    expect(requests, 1);
    expect(
      container.read(assistantChatControllerProvider).messages,
      hasLength(1),
    );

    completer.complete(_completionResponse());
    await first;
    expect(container.read(assistantChatControllerProvider).isReady, isTrue);
    // 单次 send 现为两跳：chatComplete 判定（无工具）+ chatStream 收尾。
    expect(requests, 2);
  });

  test('空白输入被忽略：不改状态、不发请求', () async {
    await seedProviders();
    var requests = 0;
    final container = containerWith(
      MockClient((_) async {
        requests++;
        return _sseResponse('x');
      }),
    );

    await container.read(assistantChatControllerProvider.notifier).send('   ');

    expect(container.read(assistantChatControllerProvider).isIdle, isTrue);
    expect(requests, 0);
  });

  test('resendFrom：截掉该提问之后的全部消息并重跑，上下文只含该提问', () async {
    await seedProviders();
    late http.Request captured;
    var streamCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        captured = request;
        streamCall++;
        return _sseResponse('第$streamCall答');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    await notifier.send('第一问');
    await notifier.send('第二问');
    expect(
      container
          .read(assistantChatControllerProvider)
          .messages
          .map((m) => m.content)
          .toList(),
      ['第一问', '第1答', '第二问', '第2答'],
    );

    // 重发第一问（index 0）：其后 3 条（第1答/第二问/第2答）被截掉。
    await notifier.resendFrom(0);

    final state = container.read(assistantChatControllerProvider);
    expect(state.isReady, isTrue);
    expect(
      state.messages.map((m) => m.content).toList(),
      ['第一问', '第3答'],
    );
    // 请求上下文只剩 system + 第一问。
    final messages = (jsonDecode(captured.body)
        as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(messages, hasLength(2));
    expect(messages[0]['role'], 'system');
    expect(messages[1]['content'], '第一问');
  });

  test('resendFrom：越界 / 非 user 轮次 / 在途时忽略', () async {
    await seedProviders();
    var streamCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        streamCall++;
        return _sseResponse('答$streamCall');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    await notifier.send('问');
    final before = container.read(assistantChatControllerProvider).messages;

    await notifier.resendFrom(-1); // 越界
    await notifier.resendFrom(99); // 越界
    await notifier.resendFrom(1); // messages[1] 是 assistant，非 user

    expect(container.read(assistantChatControllerProvider).messages, before);
    expect(streamCall, 1); // 未重跑
  });

  test('resendFrom：清除点在重发点之后时被收紧到重发点（contextBaseIndex 不越界）', () async {
    await seedProviders();
    final container = containerWith(
      MockClient((request) async {
        if (!_isStream(request.body)) return _completionResponse();
        return _sseResponse('答');
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    await notifier.send('第一问');
    await notifier.send('第二问');
    notifier.clearContext(); // base = 4（末尾）
    expect(container.read(assistantChatControllerProvider).contextBaseIndex, 4);

    await notifier.resendFrom(0); // 消息截到 1 条 → base 须收紧到 ≤1
    final state = container.read(assistantChatControllerProvider);
    // 弱断言回归：原先是 lessThanOrEqualTo(state.messages.length)（=2），
    // 比本行注释声称的「≤1」还松 —— base=2 也能通过，而那意味着上下文
    // 起点落在新回答之后，刚重发出来的这轮对话会被整段排除出请求历史。
    // 实现是 `clamp(0, index + 1)`（assistant_chat_controller.dart:106），
    // resendFrom(0) 的精确结果就是 1，直接锁死。
    expect(state.contextBaseIndex, 1);
    expect(state.messages, hasLength(2)); // 第一问 + 新答
  });

  test('页面销毁在 streaming：discardPending 收敛状态（固化增量），不卡 busy', () async {
    await seedProviders();
    final sse = StreamController<List<int>>();
    final container = containerWith(
      MockClient.streaming((request, bodyStream) async {
        final body = utf8.decode(await bodyStream.toBytes());
        if (!_isStream(body)) return _completionStreamed();
        return http.StreamedResponse(sse.stream, 200);
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    final done = notifier.send('在吗');
    sse.add(utf8.encode(_sseData('在的')));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(assistantChatControllerProvider).isStreaming,
      isTrue,
    );

    // 页面退出：废弃在途流。若不收敛，重进页面（ensureOpen 对仍在的
    // 会话不重置聊天状态）后 isBusy 永远为 true，清除上下文按钮恒灰。
    notifier.discardPending();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(assistantChatControllerProvider);
    expect(state.isBusy, isFalse);
    expect(state.isReady, isTrue);
    // 已累积增量固化为 assistant（与 stop 同语义），记录不丢。
    expect(state.messages.last.role, ChatRole.assistant);
    expect(state.messages.last.content, '在的');
    expect(state.streamingText, isEmpty);

    // 晚到分片不改写已收敛的状态（令牌护栏仍生效）。
    sse.add(utf8.encode(_sseData('——晚到')));
    sse.add(utf8.encode('data: [DONE]\n\n'));
    await sse.close();
    await done;
    expect(
      container.read(assistantChatControllerProvider).messages.last.content,
      '在的',
    );
  });

  test('页面销毁在 loading（判定中无增量）：discardPending 收敛回 ready，不新增消息', () async {
    await seedProviders();
    final completer = Completer<http.Response>();
    final container = containerWith(
      MockClient((request) async {
        if (_isStream(request.body)) return _sseResponse('不该到这');
        return completer.future; // 挂住 chatComplete 工具判定阶段。
      }),
    );
    final notifier = container.read(assistantChatControllerProvider.notifier);

    final done = notifier.send('在吗');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(assistantChatControllerProvider).isLoading, isTrue);

    notifier.discardPending();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(assistantChatControllerProvider);
    expect(state.isBusy, isFalse);
    expect(state.isReady, isTrue); // user 气泡保留
    expect(state.messages, hasLength(1));

    // 被废弃的判定响应晚到：不写状态。
    completer.complete(_completionResponse());
    await done;
    final finalState = container.read(assistantChatControllerProvider);
    expect(finalState.isReady, isTrue);
    expect(finalState.messages, hasLength(1));
  });

  test('工具一轮：chatComplete 回 tool_calls → 执行 → 回灌 role:tool → 流式收尾', () async {
    await seedProviders();
    final completeBodies = <String>[];
    var completeCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (_isStream(request.body)) return _sseResponse('这道题一步步来看～');
        completeBodies.add(request.body);
        completeCall++;
        // 第 1 轮请求讲解错题工具；第 2 轮不再要工具 → 跳出循环走流式。
        if (completeCall == 1) {
          return _completionResponse(
            toolCalls: [_toolCallWire('call_1', 'explain_mistake')],
          );
        }
        return _completionResponse();
      }),
    );

    await container
        .read(assistantChatControllerProvider.notifier)
        .send('讲讲我的错题');

    final state = container.read(assistantChatControllerProvider);
    expect(state.isReady, isTrue);
    // user + assistant(tool_calls) + tool(回灌) + assistant(最终回答)。
    expect(state.messages, hasLength(4));
    expect(state.messages[1].role, ChatRole.assistant);
    expect(state.messages[1].toolCalls!.single.name, 'explain_mistake');
    expect(state.messages[2].role, ChatRole.tool);
    expect(state.messages[2].toolCallId, 'call_1');
    expect(state.messages[2].name, 'explain_mistake');
    // 错题本为空 → 工具回灌友好兜底文案（而非崩溃）。
    expect(state.messages[2].content, contains('没有找到可讲解的错题'));
    expect(state.messages[3].role, ChatRole.assistant);
    expect(state.messages[3].content, '这道题一步步来看～');
    expect(completeCall, 2);
    // 第 2 轮请求体必须回灌了 role:tool，且绝不携带 apiKey。
    final round2 = jsonDecode(completeBodies[1]) as Map<String, dynamic>;
    final msgs = round2['messages'] as List<dynamic>;
    expect(msgs.any((m) => m['role'] == 'tool'), isTrue);
    expect(completeBodies[1], isNot(contains('key-p1')));
  });

  test('工具循环 4 轮硬上限：始终回 tool_calls → 到顶强制流式收尾', () async {
    await seedProviders();
    var completeCall = 0;
    final container = containerWith(
      MockClient((request) async {
        if (_isStream(request.body)) return _sseResponse('我们先练一练吧！');
        completeCall++;
        // 恒回 tool_calls：验证循环到上限后强制走流式收尾，不无限循环。
        return _completionResponse(
          toolCalls: [_toolCallWire('call_$completeCall', 'explain_mistake')],
        );
      }),
    );

    await container
        .read(assistantChatControllerProvider.notifier)
        .send('一直要工具');

    final state = container.read(assistantChatControllerProvider);
    expect(state.isReady, isTrue);
    // chatComplete 恰好 4 次（kAssistantMaxToolRounds），到顶即止。
    expect(completeCall, kAssistantMaxToolRounds);
    // 每轮 assistant(tool_calls)+tool 两条，4 轮 = 8，加 user 与最终回答 = 10。
    expect(state.messages, hasLength(10));
    expect(
      state.messages.where((m) => m.role == ChatRole.tool).length,
      kAssistantMaxToolRounds,
    );
    expect(state.messages.last.role, ChatRole.assistant);
    expect(state.messages.last.content, '我们先练一练吧！');
  });
}
