// test/features/assistant/tools/assistant_tools_test.dart
//
// 三个助手工具（GenerateWordProblemsTool / OpenPracticeTool /
// ExplainMistakeTool）executor 测试：
//   - open_practice：kind 路由分发（假 router 记录 push 目标）；
//   - explain_mistake：临时 Hive 塞错题 → payload；空库兜底文案；
//     按 mistakeId 取指定错题；
//   - generate_word_problems：非法参数 → ToolResult.error（不发请求、
//     不 push）；出题场景未配置 → error；合法参数 → 走真实管线
//     （骨架 + 校验链）并 push 家长预览页（假 router 断言 extra），
//     绝不静默入库；
//   - Key 安全：工具结果文本不含 apiKey。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/assistant/tools/assistant_tools_provider.dart';
import 'package:poemath/features/assistant/tools/explain_mistake_tool.dart';
import 'package:poemath/features/assistant/tools/generate_word_problems_tool.dart';
import 'package:poemath/features/assistant/tools/open_practice_tool.dart';
import 'package:poemath/features/math/word_problem/word_problem_preview_page.dart';

import '../../../helpers/hive_test_helper.dart';

const _apiKey = 'key-p1';

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

/// 记录 push 目标与 extra 的假 router（不真正导航）。
/// GoRouter 的默认构造器是 factory（不可被子类 super 调用），routingConfig
/// 命名构造器是生成式构造器，包一层 ValueNotifier 即可。
class _RecordingRouter extends GoRouter {
  _RecordingRouter()
      : super.routingConfig(
          routingConfig: ValueNotifier<RoutingConfig>(
            RoutingConfig(
              routes: <RouteBase>[
                GoRoute(
                  path: '/',
                  builder: (c, s) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          initialLocation: '/',
        );

  final List<(String, Object?)> pushes = <(String, Object?)>[];

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    pushes.add((location, extra));
    return Future<T?>.value();
  }
}

/// 一批合法草稿响应：content 为单个 JSON 数组（index 1..count）。
http.Response _draftsResponse(int count) => http.Response.bytes(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'content': jsonEncode(
                  List<Map<String, Object?>>.generate(
                    count,
                    (i) => <String, Object?>{
                      'index': i + 1,
                      'sceneId': 'apples',
                      'variantId': 'standard',
                    },
                  ),
                ),
              },
            },
          ],
        }),
      ),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

MathMistake _mistake({
  required String id,
  bool resolved = false,
  String? errorType,
}) =>
    MathMistake(
      id: id,
      profileId: 'default',
      problemText: '25 + 38 = ?',
      correctAnswer: '63',
      userAnswer: '53',
      problemType: 'arithmetic',
      grade: 2,
      errorType: errorType,
      createdAt: DateTime(2026, 10, 1),
      isResolved: resolved,
    );

/// 把容器的 [Ref] 暴露给工具 execute（工具签名吃 Ref，不经 widget 层）。
/// 用一个自引用 Provider 读取自身 Ref：Provider 元素的 ref 即容器 ref。
final _containerRefProvider = Provider<Ref>((ref) => ref);

Future<void> _seedWordProblemProvider(SecureCredentialStore store) async {
  await SettingsRepository(
    credentialStore: store,
  ).saveLlmProviderConfig(
    id: 'p1',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
    apiKey: _apiKey,
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

  /// 构造测试容器：内存凭据 + 假 router + （可选）假 http。
  ProviderContainer containerWith({
    _RecordingRouter? router,
    http.Client? httpClient,
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        secureCredentialStoreProvider.overrideWithValue(store),
        if (router != null) appRouterProvider.overrideWithValue(router),
        if (httpClient != null)
          llmExplainHttpClientProvider.overrideWithValue(httpClient),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('open_practice', () {
    test('kind=arithmetic（缺省）→ push 口算练习路由', () async {
      final router = _RecordingRouter();
      final container = containerWith(router: router);
      final tools = container.read(assistantToolsProvider);
      final open = tools.whereType<OpenPracticeTool>().single;

      final result =
          await open.execute(container.read(_containerRefProvider), {});

      expect(result.isError, isFalse);
      expect(result.content, contains('口算练习'));
      expect(router.pushes.single.$1, AppRoutes.mathPractice);
      expect(router.pushes.single.$2, isNull);
    });

    test('kind=word_problem → push 应用题题库路由', () async {
      final router = _RecordingRouter();
      final container = containerWith(router: router);
      final open = container
          .read(assistantToolsProvider)
          .whereType<OpenPracticeTool>()
          .single;

      final result = await open.execute(container.read(_containerRefProvider), {
        'kind': 'word_problem',
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('应用题题库'));
      expect(router.pushes.single.$1, AppRoutes.wordProblemLibrary);
    });
  });

  group('explain_mistake', () {
    test('空错题本 → 友好兜底文案，不 push', () async {
      final router = _RecordingRouter();
      final container = containerWith(router: router);
      final explain = container
          .read(assistantToolsProvider)
          .whereType<ExplainMistakeTool>()
          .single;

      final result =
          await explain.execute(container.read(_containerRefProvider), {});

      expect(result.isError, isFalse);
      expect(result.content, contains('没有找到可讲解的错题'));
      expect(router.pushes, isEmpty);
    });

    test('默认取最近一道未订正错题 → payload 含题面/答案/错因', () async {
      final container = containerWith();
      await container
          .read(mathMistakeRepositoryProvider)
          .add(_mistake(id: 'm1', errorType: 'carry'));
      // 已订正的更晚错题：缺省取题必须跳过它。
      await container
          .read(mathMistakeRepositoryProvider)
          .add(_mistake(id: 'm2', resolved: true));
      final explain = container
          .read(assistantToolsProvider)
          .whereType<ExplainMistakeTool>()
          .single;

      final result =
          await explain.execute(container.read(_containerRefProvider), {});

      expect(result.isError, isFalse);
      expect(result.content, contains('25 + 38 = ?'));
      expect(result.content, contains('53'));
      expect(result.content, contains('63'));
      expect(result.content, contains('carry'));
      expect(result.content, contains('鼓励'));
    });

    test('指定 mistakeId 取对应错题；不存在 → 兜底文案', () async {
      final container = containerWith();
      await container
          .read(mathMistakeRepositoryProvider)
          .add(_mistake(id: 'm1', errorType: 'borrow'));
      final explain = container
          .read(assistantToolsProvider)
          .whereType<ExplainMistakeTool>()
          .single;
      final ref = container.read(_containerRefProvider);

      final hit = await explain.execute(ref, {'mistakeId': 'm1'});
      expect(hit.content, contains('borrow'));

      final miss = await explain.execute(ref, {'mistakeId': 'nope'});
      expect(miss.content, contains('没有找到可讲解的错题'));
    });

    test('无 errorType 的错题 payload 不含「错误类型」行', () async {
      final container = containerWith();
      await container
          .read(mathMistakeRepositoryProvider)
          .add(_mistake(id: 'm1'));
      final explain = container
          .read(assistantToolsProvider)
          .whereType<ExplainMistakeTool>()
          .single;

      final result =
          await explain.execute(container.read(_containerRefProvider), {});

      expect(result.content, isNot(contains('错误类型')));
    });
  });

  group('generate_word_problems', () {
    test(
        '非法参数（grade 越界 / topic 非法 / count 越界 / semester 非法）'
        ' → ToolResult.error 且不发请求、不 push', () async {
      var requests = 0;
      final router = _RecordingRouter();
      final container = containerWith(
        router: router,
        httpClient: MockClient((_) async {
          requests++;
          return _draftsResponse(1);
        }),
      );
      await _seedWordProblemProvider(store);
      final tool = container
          .read(assistantToolsProvider)
          .whereType<GenerateWordProblemsTool>()
          .single;
      final ref = container.read(_containerRefProvider);

      final badGrade = await tool.execute(ref, {
        'grade': 9,
        'semester': '上',
        'topic': 'addition',
        'count': 3,
      });
      expect(badGrade.isError, isTrue);
      expect(badGrade.content, contains('年级无效'));

      final badSemester = await tool.execute(ref, {
        'grade': 2,
        'semester': '秋',
        'topic': 'addition',
        'count': 3,
      });
      expect(badSemester.isError, isTrue);
      expect(badSemester.content, contains('学期无效'));

      final badTopic = await tool.execute(ref, {
        'grade': 2,
        'semester': '上',
        'topic': 'algebra',
        'count': 3,
      });
      expect(badTopic.isError, isTrue);
      expect(badTopic.content, contains('知识点无效'));

      final badCount = await tool.execute(ref, {
        'grade': 2,
        'semester': '上',
        'topic': 'addition',
        'count': 50,
      });
      expect(badCount.isError, isTrue);
      expect(badCount.content, contains('数量无效'));

      // 参数宽松解析：grade/count 用字符串数字也接受（先验证 4 组均失败后
      // 确认没有任何请求 / 导航发生）。
      expect(requests, 0);
      expect(router.pushes, isEmpty);
    });

    test('出题场景未配置 → 友好错误，不 push', () async {
      final router = _RecordingRouter();
      final container = containerWith(
        router: router,
        httpClient: MockClient((_) async => _draftsResponse(1)),
      );
      final tool = container
          .read(assistantToolsProvider)
          .whereType<GenerateWordProblemsTool>()
          .single;

      final result = await tool.execute(container.read(_containerRefProvider), {
        'grade': 2,
        'semester': '上',
        'topic': 'addition',
        'count': 3,
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('还没有配置 AI 出题服务'));
      expect(router.pushes, isEmpty);
    });

    test(
        '合法参数 → push 家长预览页（extra 含年级/学期/知识点/题项），'
        '结果摘要不含 API Key', () async {
      late http.Request captured;
      final router = _RecordingRouter();
      final container = containerWith(
        router: router,
        httpClient: MockClient((request) async {
          captured = request;
          return _draftsResponse(3);
        }),
      );
      await _seedWordProblemProvider(store);
      final tool = container
          .read(assistantToolsProvider)
          .whereType<GenerateWordProblemsTool>()
          .single;

      final result = await tool.execute(container.read(_containerRefProvider), {
        'grade': 2,
        'semester': '上',
        'topic': 'addition',
        'count': 3,
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('已生成'));
      expect(result.content, contains('家长预览页'));
      // Key 安全：结果文本绝不携带 apiKey。
      expect(result.content, isNot(contains(_apiKey)));
      // 出题请求发往出题场景配置（p1），key 仅在头。
      expect(captured.headers['authorization'], 'Bearer $_apiKey');
      expect(captured.body, isNot(contains(_apiKey)));

      expect(router.pushes, hasLength(1));
      final (location, extra) = router.pushes.single;
      expect(location, AppRoutes.wordProblemPreview);
      final data = extra as WordProblemPreviewData;
      expect(data.grade, 2);
      expect(data.semester, '上');
      expect(data.topicName, 'addition');
      expect(data.items, hasLength(3));
      expect(data.items.every((item) => item.accepted), isTrue);
      expect(data.items.every((item) => item.generationMetadataJson.isNotEmpty), isTrue);
    });

    test('出题网络等待期间取消，晚到草稿不能打开预览页', () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final router = _RecordingRouter();
      final container = containerWith(
        router: router,
        httpClient: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      await _seedWordProblemProvider(store);
      final tool = container
          .read(assistantToolsProvider)
          .whereType<GenerateWordProblemsTool>()
          .single;
      var active = true;
      final pending = tool.executeCancellable(
        container.read(_containerRefProvider),
        {'grade': 2, 'semester': '上', 'topic': 'addition', 'count': 3},
        isActive: () => active,
      );
      await requested.future;
      active = false;
      response.complete(_draftsResponse(3));
      final result = await pending;
      expect(result.isError, isTrue);
      expect(result.content, '操作已取消');
      expect(router.pushes, isEmpty);
    });

    test('LLM 服务 5xx → ToolResult.error 友好文本，不 push', () async {
      final router = _RecordingRouter();
      final container = containerWith(
        router: router,
        httpClient: MockClient(
          (_) async => http.Response.bytes(const [], 500),
        ),
      );
      await _seedWordProblemProvider(store);
      final tool = container
          .read(assistantToolsProvider)
          .whereType<GenerateWordProblemsTool>()
          .single;

      final result = await tool.execute(container.read(_containerRefProvider), {
        'grade': 2,
        'semester': '上',
        'topic': 'addition',
        'count': 3,
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('生成题目失败'));
      expect(result.content, isNot(contains(_apiKey)));
      expect(router.pushes, isEmpty);
    });
  });
}
