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
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/providers/repository_providers.dart';
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

  test('send 成功：追加 user+assistant；契约 system 首条 / stream / 1024 / 发往 p1',
      () async {
    await seedProviders();
    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _sseResponse('你好呀，小朋友！');
    }),);

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

  test('多轮续问：请求体携带历史轮次（system + user + assistant + user）',
      () async {
    await seedProviders();
    late http.Request captured;
    var call = 0;
    final container = containerWith(MockClient((request) async {
      captured = request;
      call++;
      return _sseResponse(call == 1 ? '第一答' : '第二答');
    }),);
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

  test('未配置：unconfigured 态，保留 user 气泡且不发请求', () async {
    var requests = 0;
    final container = containerWith(MockClient((_) async {
      requests++;
      return _sseResponse('不该被调用');
    }),);

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
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _sseResponse('好的');
    }),);

    await container.read(assistantChatControllerProvider.notifier).send('你好');

    final messages = (jsonDecode(captured.body)
        as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(messages[0]['content'], '我的自定义助手人设');
  });

  test('regenerate：截掉末尾 assistant，用最后一条 user 重跑', () async {
    await seedProviders();
    var call = 0;
    final container = containerWith(MockClient((_) async {
      call++;
      return _sseResponse(call == 1 ? '第一次回答' : '第二次回答');
    }),);
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
    expect(call, 2);
  });

  test('stop：固化已到增量为 assistant 消息，晚到分片不再改写（令牌护栏）',
      () async {
    await seedProviders();
    final sse = StreamController<List<int>>();
    final container = containerWith(
      MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(sse.stream, 200),
      ),
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
      MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(sse.stream, 200),
      ),
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
    final container = containerWith(MockClient((_) async {
      requests++;
      return completer.future;
    }),);
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

    completer.complete(_sseResponse('回答'));
    await first;
    expect(container.read(assistantChatControllerProvider).isReady, isTrue);
    expect(requests, 1);
  });

  test('空白输入被忽略：不改状态、不发请求', () async {
    await seedProviders();
    var requests = 0;
    final container = containerWith(MockClient((_) async {
      requests++;
      return _sseResponse('x');
    }),);

    await container
        .read(assistantChatControllerProvider.notifier)
        .send('   ');

    expect(container.read(assistantChatControllerProvider).isIdle, isTrue);
    expect(requests, 0);
  });


}

