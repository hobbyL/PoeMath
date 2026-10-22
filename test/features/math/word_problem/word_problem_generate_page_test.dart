// test/features/math/word_problem/word_problem_generate_page_test.dart
//
// 生成页 widget 测试：未配置 LLM 时显示引导态；
// 骨架生成失败（StateError）时展示中文提示而非英文堆栈。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/math/word_problem/word_problem_generate_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_preview_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
/// 多配置版按 configId 读 Key（readLlmConfig 走 readLlmApiKeyFor）。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> _keysByConfigId = {};

  @override
  Future<String?> readLlmApiKey() => Future.value(null);

  @override
  Future<String?> readLlmApiKeyFor(String configId) =>
      Future.value(_keysByConfigId[configId]);
}

const _config =
    LlmConfig(baseUrl: 'https://llm.example.com', apiKey: '', model: 'test');

class _DelayedSettingsRepository extends SettingsRepository {
  final pending = Completer<LlmConfig?>();
  var calls = 0;

  @override
  Future<LlmConfig?> readLlmConfig() {
    calls++;
    return pending.future;
  }
}

Future<void> _pumpDelayedGenerator(
  WidgetTester tester,
  SettingsRepository settings, {
  WordProblemSkeletonGeneratorFn? skeletons,
  http.Client? client,
  void Function(WordProblemPreviewData)? onPreview,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const WordProblemGeneratePage()),
      GoRoute(
        path: AppRoutes.wordProblemPreview,
        builder: (_, state) {
          onPreview?.call(state.extra! as WordProblemPreviewData);
          return const Scaffold(body: Text('预览验证'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        llmConfigProvider.overrideWith((ref) async => _config),
        if (skeletons != null)
          wordProblemSkeletonProvider.overrideWithValue(skeletons),
        if (client != null)
          llmExplainHttpClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    // 用例体末尾已用 `drainHiveWritesForTesting` 排空写链，此处用
    // widget 版 tearDown（见 helper 注释：fake 时钟下 close() 需要先解链）。
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('生成页失败后切换同服务商候选，保存默认且只进入一次预览', (tester) async {
    final settings = (await tester.runAsync(() async {
      final repo =
          SettingsRepository(credentialStore: _MemoryCredentialStore());
      await repo.saveLlmProviderConfig(
        id: 'p1',
        name: '',
        baseUrl: 'https://example.com',
        model: 'A',
        models: ['A', 'B'],
        apiKey: '',
      );
      return repo;
    }))!;
    final models = <String>[];
    WordProblemPreviewData? preview;
    await _pumpDelayedGenerator(
      tester,
      settings,
      skeletons: ({
        required int grade,
        required String semester,
        required String topic,
        required int count,
        DifficultyLevel difficulty = DifficultyLevel.medium,
      }) =>
          List.filled(
        count,
        const ProblemSkeleton(
          operands: [12, 4],
          operators: [Operator.add],
          answer: 16,
          unitHint: '支',
          difficulty: 1,
        ),
      ),
      client: MockClient((request) async {
        final model = (jsonDecode(request.body) as Map)['model'] as String;
        models.add(model);
        if (model == 'A') return http.Response('', 503);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      List.generate(
                        10,
                        (i) => {
                          'index': i + 1,
                          'sceneId': 'pencils',
                          'variantId': 'standard',
                        },
                      ),
                    ),
                  },
                }
              ],
            }),
          ),
          200,
        );
      }),
      onPreview: (data) => preview = data,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('生成 10 题'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 100 && preview == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(preview!.items, hasLength(10));
    expect(models, ['A', 'B']);
    expect(settings.llmProviders.single.model, 'B');
    expect(tester.takeException(), isNull);
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('配置读取期间同步连点只读取一次，读取失败后允许重试', (tester) async {
    final settings = _DelayedSettingsRepository();
    await _pumpDelayedGenerator(tester, settings);
    final generate = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '生成 10 题'))
        .onPressed!;
    generate();
    generate();
    expect(settings.calls, 1);
    settings.pending.completeError(Exception('配置读取测试失败'));
    await tester.pumpAndSettle();
    expect(find.textContaining('配置读取测试失败'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '生成 10 题'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('配置读取期间离页，晚到配置不生成骨架、不更新已销毁页面', (tester) async {
    final settings = _DelayedSettingsRepository();
    var skeletonCalls = 0;
    var previewCalls = 0;
    await _pumpDelayedGenerator(
      tester,
      settings,
      skeletons: ({
        required int grade,
        required String semester,
        required String topic,
        required int count,
        DifficultyLevel difficulty = DifficultyLevel.medium,
      }) {
        skeletonCalls++;
        return [];
      },
      onPreview: (_) => previewCalls++,
    );
    await tester.tap(find.text('生成 10 题'));
    await tester.pump();
    expect(settings.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.pending.complete(_config);
    await tester.pump();
    expect(skeletonCalls, 0);
    expect(previewCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整批AI素材经本地渲染与讲解后通过校验并进入预览', (tester) async {
    // 在真实 zone 创建已完成配置 Future，让完整请求（含静态用量写链）
    // 都能在真实 zone 收尾，不把本用例的 FakeAsync 留给后续用例。
    final settings = (await tester.runAsync(() async {
      final repository = _DelayedSettingsRepository();
      repository.pending.complete(_config);
      return repository;
    }))!;
    WordProblemPreviewData? preview;
    await _pumpDelayedGenerator(
      tester,
      settings,
      skeletons: ({
        required int grade,
        required String semester,
        required String topic,
        required int count,
        DifficultyLevel difficulty = DifficultyLevel.medium,
      }) =>
          List.filled(
        count,
        const ProblemSkeleton(
          operands: [12, 4],
          operators: [Operator.add],
          answer: 16,
          unitHint: '支',
          difficulty: 1,
        ),
      ),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode(
                      List.generate(
                        10,
                        (i) => {
                          'index': i + 1,
                          'sceneId': 'pencils',
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
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      onPreview: (data) => preview = data,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('生成 10 题'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    // 用量预留经过 Hive 写链，交替推进真实 IO 和 fake 微任务直到跳转。
    for (var i = 0; i < 100 && preview == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(preview, isNotNull);
    expect(preview!.items, hasLength(10));
    expect(
      preview!.items.map((item) => item.rejectReason),
      everyElement(isNull),
    );
    expect(preview!.items.map((item) => item.accepted), everyElement(isTrue));
    expect(
      preview!.items.map((item) => item.draft!.explanation),
      everyElement(contains('12 + 4 = 16')),
    );
    expect(tester.takeException(), isNull);
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('配置等待时修改练习难度及选项，生成始终使用发起时设置快照', (tester) async {
    final settings = _DelayedSettingsRepository();
    await tester.runAsync(() => settings.setMathDifficulty('hard'));
    final response = Completer<http.Response>();
    http.Request? request;
    (int, String, String, int, DifficultyLevel)? capturedSkeleton;
    WordProblemPreviewData? preview;
    await _pumpDelayedGenerator(
      tester,
      settings,
      skeletons: ({
        required int grade,
        required String semester,
        required String topic,
        required int count,
        DifficultyLevel difficulty = DifficultyLevel.medium,
      }) {
        capturedSkeleton = (grade, semester, topic, count, difficulty);
        return WordProblemSkeletonGenerator.generate(
          grade: grade,
          semester: semester,
          topic: topic,
          count: count,
          difficulty: difficulty,
        );
      },
      client: MockClient((incoming) {
        request = incoming;
        return response.future;
      }),
      onPreview: (data) => preview = data,
    );
    expect(find.textContaining('出题难度'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '混合运算'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '困难'), findsNothing);
    await tester.tap(find.text('生成 10 题'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '3 年级'));
    await tester.pump();
    await tester.tap(find.text('下学期'));
    await tester.pump();
    await tester.runAsync(() => settings.setMathDifficulty('easy'));
    settings.pending.complete(_config);
    // 放行配置读取后，`_generate` 才真正开跑，它将经过
    // `CloudUsageService.reserve` —— 其中 `HiveBoxes.meta.put` 的完成
    // 回调挂在 Hive 写链上。fake 时钟只推得动帧、排不动写链，`await`
    // 后面的 `_httpClient.post` 要到约 1 秒后才排到（`pumpAndSettle`
    // 在这里也只能空等到 30s 超时）。
    //
    // 所以每一轮都在**真实异步区**里等一段真实时长，回到 fake 区再
    // `pump()` 把写完排下的帧推出去，直到请求真正到达 MockClient。
    for (var i = 0; i < 40 && request == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(capturedSkeleton, (2, '上', 'addition', 10, DifficultyLevel.hard));
    expect(request, isNotNull);
    await tester.tap(find.widgetWithText(ChoiceChip, '减法'));
    await tester.pump();
    final countSelector = tester.widget<Slider>(find.byType(Slider));
    countSelector.onChanged!(5);
    await tester.pump();
    response.complete(
      http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode(
                  List.generate(
                    10,
                    (i) => {
                      'index': i + 1,
                      'sceneId': 'apples',
                      'variantId': 'standard',
                    },
                  ),
                ),
              },
            }
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    final body = jsonDecode(request!.body) as Map<String, dynamic>;
    final prompt = (body['messages'] as List).last['content'] as String;
    expect(prompt, contains('小学2年级'));
    expect(prompt, contains('上学期'));
    expect(prompt, contains('加法'));
    expect(preview, isNotNull);
    expect(preview!.grade, 2);
    expect(preview!.semester, '上');
    expect(preview!.topicName, 'addition');
    expect(preview!.items, hasLength(10));
    expect(tester.takeException(), isNull);

    // 本用例经 `CloudUsageService.reserve` 写过 `HiveBoxes.meta`
    // （用量计数）。写帧挂在 Hive 的写链上，tearDown 的 `Hive.close()`
    // 排在链尾——fake 时钟下写任务的完成回调排不到，close() 会空等到
    // 30s 超时。回到真实异步区把链推一下即可解开（helper 内有详述）。
    await drainHiveWritesForTesting(tester);
  });

  testWidgets('未配置 LLM 时显示引导态而非生成表单', (tester) async {
    // Hive settings 中无 llmBaseUrl/llmModel → readLlmConfig 返回 null。
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WordProblemGeneratePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未配置 AI 出题服务'), findsOneWidget);
    expect(find.text('去配置'), findsOneWidget);
    // 不显示生成表单
    expect(find.text('知识点'), findsNothing);
    expect(find.text('生成 5 题'), findsNothing);
  });

  testWidgets('骨架生成失败（StateError）展示中文提示，不出现英文堆栈', (tester) async {
    // 播种 LLM 配置（Hive 写入在 testWidgets 的 FakeAsync 区无法落盘，
    // 按 spec 先例放入 runAsync 在真实异步区完成）。
    // 多配置版：llmConfigProvider 经 readLlmConfig → 迁移旧 key →
    // llm_providers + active 组装，两条路径的 Hive 写链都在此完成。
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_base_url', 'http://localhost:11434');
      await HiveBoxes.settings.put('llm_model', 'qwen2.5:7b');
      await HiveBoxes.settings.put(
        'llm_providers',
        jsonEncode([
          <String, dynamic>{
            'id': 'seed-p1',
            'name': 'Ollama',
            'baseUrl': 'http://localhost:11434',
            'model': 'qwen2.5:7b',
          },
        ]),
      );
      await HiveBoxes.settings.put('llm_active_provider_id', 'seed-p1');
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 安全存储无平台通道，注入内存实现（Key 可为空，对应 Ollama）。
          secureCredentialStoreProvider.overrideWithValue(
            _MemoryCredentialStore(),
          ),
          // 注入骨架生成失败（重试耗尽的 StateError 防御路径）。
          wordProblemSkeletonProvider.overrideWithValue(
            ({
              required int grade,
              required String semester,
              required String topic,
              required int count,
              DifficultyLevel difficulty = DifficultyLevel.medium,
            }) =>
                throw StateError('无法生成目标运算符的加减法骨架'),
          ),
        ],
        child: const MaterialApp(home: WordProblemGeneratePage()),
      ),
    );
    await tester.pumpAndSettle();

    // 表单已显示，点击生成
    expect(find.text('生成 10 题'), findsOneWidget);
    await tester.tap(find.text('生成 10 题'));
    await tester.pumpAndSettle();

    // 中文提示可见，且不出现 StateError 的英文堆栈文案。
    expect(find.text('题目结构生成失败，请重试或更换年级/知识点'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('二年级上下学期均可选除法，切换一年级自动回退选中', (tester) async {
    // 配置就绪才会渲染生成表单（含知识点选择器），按先例在 runAsync 播种。
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_base_url', 'http://localhost:11434');
      await HiveBoxes.settings.put('llm_model', 'qwen2.5:7b');
      await HiveBoxes.settings.put(
        'llm_providers',
        jsonEncode([
          <String, dynamic>{
            'id': 'seed-p1',
            'name': 'Ollama',
            'baseUrl': 'http://localhost:11434',
            'model': 'qwen2.5:7b',
          },
        ]),
      );
      await HiveBoxes.settings.put('llm_active_provider_id', 'seed-p1');
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureCredentialStoreProvider.overrideWithValue(
            _MemoryCredentialStore(),
          ),
        ],
        child: const MaterialApp(home: WordProblemGeneratePage()),
      ),
    );
    await tester.pumpAndSettle();

    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    // 默认二年级上学期：加/减/乘/除可见，混合运算隐藏。
    expect(find.text('知识点'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '加法'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '减法'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '乘法'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '除法'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '混合运算'), findsNothing);
    expect(chip('加法').selected, isTrue);

    // 二年级上学期即可选中除法。
    await tester.tap(find.widgetWithText(ChoiceChip, '除法'));
    await tester.pumpAndSettle();
    expect(chip('除法').selected, isTrue);

    // 切到二年级下学期保留除法选中态，混合运算仍无。
    await tester.tap(find.text('下学期'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '除法'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '混合运算'), findsNothing);

    expect(chip('除法').selected, isTrue);

    // 切回二年级上学期仍保留除法选中态。
    await tester.tap(find.text('上学期'));
    await tester.pumpAndSettle();
    expect(chip('除法').selected, isTrue);

    // 一年级尚未开放除法，选中态自动回退为加法。
    await tester.tap(find.widgetWithText(ChoiceChip, '1 年级'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '除法'), findsNothing);
    expect(chip('加法').selected, isTrue);
  });
}
