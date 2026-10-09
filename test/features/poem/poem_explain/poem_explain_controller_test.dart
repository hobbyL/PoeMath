// test/features/poem/poem_explain/poem_explain_controller_test.dart
//
// 诗词 AI 讲解控制器测试：成功分段、未配置引导、错误分类映射、
// 连点防重入、reset 废弃在途结果、场景厂商选择生效、prompt 负载边界。
//
// 测试环境无平台安全存储通道与真实网络，凭据与 http 均注入内存/mock。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_controller.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_models.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_prompts.dart';

import '../../../helpers/hive_test_helper.dart';

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

Poem _poem() => Poem(
      id: 'poem-1',
      title: '静夜思',
      author: '李白',
      dynasty: '唐',
      content: '床前明月光，疑是地上霜。\n举头望明月，低头思故乡。',
      pinyin: 'chuáng qián míng yuè guāng',
      layer: 'core',
      translation: '译文不应进入 prompt',
      appreciation: '赏析不应进入 prompt',
      background: '背景不应进入 prompt',
      famousLines: const ['举头望明月'],
      tags: const ['思乡'],
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

void main() {
  late _MemoryCredentialStore store;

  setUp(() async {
    await setUpHiveForTesting();
    store = _MemoryCredentialStore();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  /// 预置两条厂商配置（p1 生效 + p2）。
  Future<void> seedProviders() async {
    final repo = SettingsRepository(credentialStore: store);
    await repo.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
      apiKey: 'key-p1',
    );
    await repo.saveLlmProviderConfig(
      id: 'p2',
      name: '通义千问',
      baseUrl: 'https://dashscope.example.com',
      model: 'qwen-plus',
      apiKey: 'key-p2',
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

  test('成功：按行分段、剥离 markdown 残留、记录 poemId', () async {
    await seedProviders();
    final container = containerWith(
      MockClient(
        (_) async => _chatResponse(
          '```\n'
          '## 这首诗在说什么\n'
          '- **夜里**睡不着的李白看见了月光。\n'
          '\n'
          '1. 他以为地上结了霜。\n'
          '```',
        ),
      ),
    );

    await container.read(poemExplainProvider.notifier).generate(_poem());

    final state = container.read(poemExplainProvider);
    expect(state.status, PoemExplainStatus.ready);
    expect(state.isReady, isTrue);
    expect(state.paragraphs, [
      '这首诗在说什么',
      '夜里睡不着的李白看见了月光。',
      '他以为地上结了霜。',
    ]);
    expect(state.poemId, 'poem-1');
    expect(state.message, isNull);
    expect(state.fullText, contains('夜里睡不着'));
  });

  test('未配置：unconfigured 引导态且不发请求', () async {
    var requests = 0;
    final container = containerWith(MockClient((_) async {
      requests++;
      return _chatResponse('不该被调用');
    }),);

    await container.read(poemExplainProvider.notifier).generate(_poem());

    final state = container.read(poemExplainProvider);
    expect(state.status, PoemExplainStatus.unconfigured);
    expect(state.message, contains('还没有配置 AI 服务'));
    expect(requests, 0);
  });

  test('鉴权失败：error 态且文案不含 API Key', () async {
    await seedProviders();
    final container = containerWith(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'error': {'message': 'invalid key'}})),
          401,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await container.read(poemExplainProvider.notifier).generate(_poem());

    final state = container.read(poemExplainProvider);
    expect(state.status, PoemExplainStatus.error);
    expect(state.message, isNotNull);
    expect(state.message, isNot(contains('key-p1')));
    expect(state.paragraphs, isEmpty);
  });

  test('模型输出空白：error 态提示重新生成', () async {
    await seedProviders();
    final container = containerWith(
      MockClient((_) async => _chatResponse('   \n  ')),
    );

    await container.read(poemExplainProvider.notifier).generate(_poem());

    final state = container.read(poemExplainProvider);
    expect(state.status, PoemExplainStatus.error);
    expect(state.message, isNotNull);
  });

  test('连点防重入：loading 中再次 generate 不发第二次请求', () async {
    await seedProviders();
    var requests = 0;
    final completer = Completer<http.Response>();
    final container = containerWith(MockClient((_) async {
      requests++;
      return completer.future;
    }),);
    final notifier = container.read(poemExplainProvider.notifier);

    final first = notifier.generate(_poem());
    // 让第一次请求推进到 loading 态（Hive + 安全存储读取是异步的）。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(poemExplainProvider).isLoading, isTrue);

    await notifier.generate(_poem()); // 被守卫拦截，立即返回。
    expect(requests, 1);

    completer.complete(_chatResponse('讲解内容。'));
    await first;
    expect(container.read(poemExplainProvider).status, PoemExplainStatus.ready);
    expect(requests, 1);
  });

  test('reset 后晚到的结果不覆盖状态（代际令牌）', () async {
    await seedProviders();
    final completer = Completer<http.Response>();
    final container = containerWith(
      MockClient((_) async => completer.future),
    );
    final notifier = container.read(poemExplainProvider.notifier);

    final pending = notifier.generate(_poem());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(poemExplainProvider).isLoading, isTrue);

    // 切诗 / 退页：复位并废弃在途请求。
    notifier.reset();
    expect(container.read(poemExplainProvider).isIdle, isTrue);

    completer.complete(_chatResponse('晚到的讲解。'));
    await pending;
    // 晚到结果被丢弃，仍为 idle。
    expect(container.read(poemExplainProvider).isIdle, isTrue);
    expect(container.read(poemExplainProvider).paragraphs, isEmpty);
  });

  test('走诗词场景绑定的厂商（非生效配置）', () async {
    await seedProviders();
    await SettingsRepository(credentialStore: store)
        .setProviderIdForScenario(LlmScenario.poemExplain, 'p2');

    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _chatResponse('讲解内容。');
    }),);

    await container.read(poemExplainProvider.notifier).generate(_poem());

    expect(container.read(poemExplainProvider).isReady, isTrue);
    expect(
      captured.url.toString(),
      'https://dashscope.example.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer key-p2');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'qwen-plus');
    expect(body['max_tokens'], kPoemExplainMaxTokens);
  });

  test('未绑定场景时跟随生效配置', () async {
    await seedProviders();
    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _chatResponse('讲解内容。');
    }),);

    await container.read(poemExplainProvider.notifier).generate(_poem());

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-chat');
    expect(captured.headers['authorization'], 'Bearer key-p1');
  });

  group('buildPoemExplainUserPrompt', () {
    test('负载只含标题/作者/朝代/正文，不含译文赏析背景等其他数据', () {
      final prompt = buildPoemExplainUserPrompt(_poem());

      expect(prompt, contains('静夜思'));
      expect(prompt, contains('李白'));
      expect(prompt, contains('唐'));
      expect(prompt, contains('床前明月光'));
      expect(prompt, contains('低头思故乡'));
      // 隐私边界：其余字段一律不出现。
      expect(prompt, isNot(contains('译文不应进入 prompt')));
      expect(prompt, isNot(contains('赏析不应进入 prompt')));
      expect(prompt, isNot(contains('背景不应进入 prompt')));
      expect(prompt, isNot(contains('思乡')));
      expect(prompt, isNot(contains('poem-1')));
      expect(prompt, isNot(contains('core')));
    });

    test('system prompt 固定要求纯文本与不虚构', () {
      expect(kPoemExplainSystemPrompt, contains('纯文本'));
      expect(kPoemExplainSystemPrompt, isNot(contains('静夜思')));
    });
  });
}
