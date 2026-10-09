// test/features/math/math_explain/math_explain_controller_test.dart
//
// 口算 AI 解析控制器测试：成功分段、答错分支错因标签、未配置引导、
// 错误分类映射、连点防重入、reset 代际令牌、场景厂商选择生效、
// prompt 负载边界（只含题面/答案/错因）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/math/math_explain/math_explain_controller.dart';
import 'package:poemath/features/math/math_explain/math_explain_models.dart';
import 'package:poemath/features/math/math_explain/math_explain_prompts.dart';
import 'package:poemath/math_engine/diagnostics/error_cause_labels.dart';
import 'package:poemath/math_engine/diagnostics/mistake_rule.dart';

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

  test('成功：分段清洗 markdown 残留并记录题面', () async {
    await seedProviders();
    final container = containerWith(
      MockClient(
        (_) async => _chatResponse(
          '1. 先算个位：**7 + 5 = 12**，写 2 进 1。\n'
          '\n'
          '- 再算十位：2 + 3 + 1 = 6。\n'
          '所以结果是 62。',
        ),
      ),
    );

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '27 + 35 = ?',
          correctAnswer: '62',
        );

    final state = container.read(mathExplainProvider);
    expect(state.status, MathExplainStatus.ready);
    expect(state.paragraphs, [
      '先算个位：7 + 5 = 12，写 2 进 1。',
      '再算十位：2 + 3 + 1 = 6。',
      '所以结果是 62。',
    ]);
    expect(state.problemText, '27 + 35 = ?');
  });

  test('答错分支：prompt 含孩子答案与错因中文标签', () async {
    await seedProviders();
    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _chatResponse('讲解内容。');
    }),);

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '27 + 35 = ?',
          correctAnswer: '62',
          userAnswer: '52',
          diagnosisCategory: 'carry_omission',
        );

    expect(container.read(mathExplainProvider).isReady, isTrue);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final userPrompt =
        (body['messages'] as List<dynamic>)[1]['content'] as String;
    expect(userPrompt, contains('题目：27 + 35 = ?'));
    expect(userPrompt, contains('正确答案：62'));
    expect(userPrompt, contains('孩子的答案：52'));
    expect(userPrompt, contains('错误原因：进位遗漏'));
    // 不传诊断 category 原始英文键。
    expect(userPrompt, isNot(contains('carry_omission')));
    expect(body['max_tokens'], kMathExplainMaxTokens);
  });

  test('答对分支：prompt 不含孩子答案与错因行', () async {
    await seedProviders();
    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _chatResponse('讲解内容。');
    }),);

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '27 + 35 = ?',
          correctAnswer: '62',
        );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final userPrompt =
        (body['messages'] as List<dynamic>)[1]['content'] as String;
    expect(userPrompt, isNot(contains('孩子的答案')));
    expect(userPrompt, isNot(contains('错误原因')));
  });

  test('未知错因 category 不入 prompt（标签映射缺失时静默忽略）', () async {
    await seedProviders();
    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _chatResponse('讲解内容。');
    }),);

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '27 + 35 = ?',
          correctAnswer: '62',
          userAnswer: '52',
          diagnosisCategory: 'unknown_cause',
        );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final userPrompt =
        (body['messages'] as List<dynamic>)[1]['content'] as String;
    expect(userPrompt, contains('孩子的答案：52'));
    expect(userPrompt, isNot(contains('错误原因')));
    expect(userPrompt, isNot(contains('unknown_cause')));
  });

  test('未配置：unconfigured 引导态且不发请求', () async {
    var requests = 0;
    final container = containerWith(MockClient((_) async {
      requests++;
      return _chatResponse('不该被调用');
    }),);

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '1 + 1 = ?',
          correctAnswer: '2',
        );

    final state = container.read(mathExplainProvider);
    expect(state.status, MathExplainStatus.unconfigured);
    expect(state.message, contains('还没有配置 AI 服务'));
    expect(requests, 0);
  });

  test('服务端 5xx：error 态且文案不含 API Key', () async {
    await seedProviders();
    final container = containerWith(
      MockClient((_) async => http.Response.bytes(const [], 503)),
    );

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '1 + 1 = ?',
          correctAnswer: '2',
        );

    final state = container.read(mathExplainProvider);
    expect(state.status, MathExplainStatus.error);
    expect(state.message, isNotNull);
    expect(state.message, isNot(contains('key-p1')));
  });

  test('连点防重入：loading 中再次 generate 不发第二次请求', () async {
    await seedProviders();
    var requests = 0;
    final completer = Completer<http.Response>();
    final container = containerWith(MockClient((_) async {
      requests++;
      return completer.future;
    }),);
    final notifier = container.read(mathExplainProvider.notifier);

    final first = notifier.generate(
      problemText: '1 + 1 = ?',
      correctAnswer: '2',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(mathExplainProvider).isLoading, isTrue);

    await notifier.generate(problemText: '1 + 1 = ?', correctAnswer: '2');
    expect(requests, 1);

    completer.complete(_chatResponse('解析内容。'));
    await first;
    expect(container.read(mathExplainProvider).isReady, isTrue);
    expect(requests, 1);
  });

  test('reset（关弹层）后晚到结果不覆盖状态', () async {
    await seedProviders();
    final completer = Completer<http.Response>();
    final container = containerWith(
      MockClient((_) async => completer.future),
    );
    final notifier = container.read(mathExplainProvider.notifier);

    final pending = notifier.generate(
      problemText: '1 + 1 = ?',
      correctAnswer: '2',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(mathExplainProvider).isLoading, isTrue);

    notifier.reset();
    expect(container.read(mathExplainProvider).isIdle, isTrue);

    completer.complete(_chatResponse('晚到的解析。'));
    await pending;
    expect(container.read(mathExplainProvider).isIdle, isTrue);
    expect(container.read(mathExplainProvider).paragraphs, isEmpty);
  });

  test('走口算场景绑定的厂商（非生效配置）', () async {
    await seedProviders();
    await SettingsRepository(credentialStore: store)
        .setProviderIdForScenario(LlmScenario.mathExplain, 'p2');

    late http.Request captured;
    final container = containerWith(MockClient((request) async {
      captured = request;
      return _chatResponse('解析内容。');
    }),);

    await container.read(mathExplainProvider.notifier).generate(
          problemText: '1 + 1 = ?',
          correctAnswer: '2',
        );

    expect(container.read(mathExplainProvider).isReady, isTrue);
    expect(
      captured.url.toString(),
      'https://dashscope.example.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer key-p2');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'qwen-plus');
  });

  test('错因标签表覆盖诊断器全部权威键', () {
    // 单一来源表：键集与诊断器规则 name 的一致性由
    // test/math_engine/diagnostics/error_cause_labels_test.dart 守卫，
    // 这里确认控制器消费的正是该表。
    expect(
      kErrorCauseLabels.keys,
      containsAll(MistakeDiagnoser.categoryNames),
    );
    expect(kErrorCauseLabels.length, MistakeDiagnoser.categoryNames.length);
  });

  test('system prompt 固定「正确答案以给出为准」铁律', () {
    expect(kMathExplainSystemPrompt, contains('正确答案以我给出的为准'));
    expect(kMathExplainSystemPrompt, contains('markdown'));
  });
}
