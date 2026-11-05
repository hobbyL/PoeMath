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
import '../../../helpers/parent_access_test_helper.dart';

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
    await unlockParentForTesting();
  });

  tearDown(() async {
    lockParentForTesting();
    // 用例体末尾已用 `drainHiveWritesForTesting` 排空写链，此处用
    // widget 版 tearDown（见 helper 注释：fake 时钟下 close() 需要先解链）。
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('多选知识点共用总题数，后续修改选项不改变已发起的题组', (tester) async {
    final settings = _DelayedSettingsRepository();
    final skeletonCounts = <String, int>{};
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
        skeletonCounts.putIfAbsent(topic, () => count);
        return List.generate(
          count,
          (index) => ProblemSkeleton(
            operands: [12 + index, 4],
            operators: [
              topic == 'addition' ? Operator.add : Operator.subtract,
            ],
            answer: topic == 'addition' ? 16 + index : 8 + index,
            unitHint: '个',
            difficulty: 1,
          ),
        );
      },
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final prompt = body['messages'].last['content'] as String;
        final candidates =
            jsonDecode(prompt.substring(prompt.indexOf('['))) as List;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(
              {
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode([
                        for (final item in candidates)
                          {
                            'index': item['index'],
                            'sceneId': item['sceneCandidates'].first['sceneId'],
                            'variantId': 'standard',
                          },
                      ]),
                    },
                  },
                ],
              },
            ),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      onPreview: (data) => preview = data,
    );

    await tester.tap(find.widgetWithText(FilterChip, '减法'));
    await tester.pump();
    for (final label in ['加法', '减法']) {
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, label))
            .selected,
        isTrue,
      );
    }
    tester.widget<Slider>(find.byType(Slider)).onChanged!(7);
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('生成 7 题')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, '除法'));
    await tester.pump();
    settings.pending.complete(_config);
    for (var i = 0; i < 40 && preview == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(skeletonCounts, {'addition': 4, 'subtraction': 3});
    expect(preview, isNotNull);
    expect(
      preview!.topics,
      [WordProblemTopic.addition, WordProblemTopic.subtraction],
    );
    expect(preview!.items, hasLength(7));
    expect(preview!.items.map((item) => item.topic), [
      WordProblemTopic.addition,
      WordProblemTopic.subtraction,
      WordProblemTopic.addition,
      WordProblemTopic.subtraction,
      WordProblemTopic.addition,
      WordProblemTopic.subtraction,
      WordProblemTopic.addition,
    ]);
    expect(
      preview!.items.map((item) => preview!.validationFor(item).canSave),
      everyElement(isTrue),
    );
    expect(tester.takeException(), isNull);
    await drainHiveWritesForTesting(tester);
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

  testWidgets('配置等待时修改难度、提示词及选项，生成始终使用发起时设置快照', (tester) async {
    final settings = _DelayedSettingsRepository();
    await tester.runAsync(() => settings.setMathDifficulty('hard'));
    await tester.runAsync(
      () => settings.setWordProblemGenerationPrompt('发起时的自然观察偏好'),
    );
    http.Request? request;
    final skeletonCalls = <(int, String, String, int, DifficultyLevel)>[];
    WordProblemPreviewData? preview;
    await _pumpDelayedGenerator(
      tester,
      settings,
      skeletons:
          ({
            required int grade,
            required String semester,
            required String topic,
            required int count,
            DifficultyLevel difficulty = DifficultyLevel.medium,
          }) {
            skeletonCalls.add((grade, semester, topic, count, difficulty));
            // 首批骨架重复，确保触发单题去重重试；重试时提供不同的骨架。
            final left = 11 + skeletonCalls.length;
            return List.generate(
              count,
              (_) => ProblemSkeleton(
                operands: [left, 4],
                operators: const [Operator.add],
                answer: left + 4,
                unitHint: '个',
                difficulty: 3,
              ),
            );
          },
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(
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
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      onPreview: (data) => preview = data,
    );
    try {
      expect(find.textContaining('出题难度'), findsNothing);
      expect(find.widgetWithText(FilterChip, '混合运算'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '困难'), findsNothing);
      await tester.runAsync(() => tester.tap(find.text('生成 10 题')));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, '3 年级'));
      await tester.pump();
      await tester.tap(find.text('下学期'));
      await tester.pump();
      await tester.runAsync(() => settings.setMathDifficulty('easy'));
      await tester.runAsync(
        () => settings.setWordProblemGenerationPrompt('等待时改为购物偏好'),
      );
      await tester.tap(find.widgetWithText(FilterChip, '减法'));
      await tester.pump();
      final countSelector = tester.widget<Slider>(find.byType(Slider));
      countSelector.onChanged!(5);
      await tester.pump();
      expect(skeletonCalls, isEmpty);
      expect(request, isNull);
      settings.pending.complete(_config);
      // 交替推进真实 Hive IO 和页面帧，直到生成流程完成并进入预览。
      for (var i = 0; i < 100 && preview == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(preview, isNotNull);
      await tester.pumpAndSettle();
      expect(skeletonCalls.first, (
        2,
        '上',
        'addition',
        10,
        DifficultyLevel.hard,
      ));
      expect(skeletonCalls.skip(1), isNotEmpty);
      expect(
        skeletonCalls.skip(1),
        everyElement((2, '上', 'addition', 1, DifficultyLevel.hard)),
      );
      expect(request, isNotNull);
      final body = jsonDecode(request!.body) as Map<String, dynamic>;
      final systemPrompt =
          (body['messages'] as List).first['content'] as String;
      expect(systemPrompt, startsWith('发起时的自然观察偏好\n\n'));
      expect(systemPrompt, isNot(contains('等待时改为购物偏好')));
      final prompt = (body['messages'] as List).last['content'] as String;
      expect(prompt, contains('小学2年级'));
      expect(prompt, contains('上学期'));
      expect(prompt, contains('加法'));
      final candidates =
          jsonDecode(prompt.substring(prompt.indexOf('['))) as List;
      expect(candidates, hasLength(10));
      expect(preview!.grade, 2);
      expect(preview!.semester, '上');
      expect(preview!.topics, [WordProblemTopic.addition]);
      expect(preview!.items, hasLength(10));
      expect(tester.takeException(), isNull);
    } finally {
      // 断言失败也必须排空写链，避免 Hive.close() 随后再报 30s 超时。
      await drainHiveWritesForTesting(tester);
    }
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
    expect(find.text('知识点（可多选）'), findsNothing);
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

  testWidgets('知识点多选至少保留一项，切换学期保留已学项、移除未学项', (tester) async {
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

    FilterChip chip(String label) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

    // 默认二年级上学期：加/减/乘/除可见，混合运算隐藏。
    expect(find.text('知识点（可多选）'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '加法'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '减法'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '乘法'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '除法'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '混合运算'), findsNothing);
    expect(chip('加法').selected, isTrue);

    // 二年级上学期即可选中除法。
    await tester.tap(find.widgetWithText(FilterChip, '除法'));
    await tester.pumpAndSettle();
    expect(chip('除法').selected, isTrue);
    expect(chip('加法').selected, isTrue);
    await tester.tap(find.widgetWithText(FilterChip, '减法'));
    await tester.tap(find.widgetWithText(FilterChip, '加法'));
    await tester.pumpAndSettle();
    expect(chip('加法').selected, isFalse);
    expect(chip('减法').selected, isTrue);

    // 切到二年级下学期保留除法选中态，混合运算仍无。
    await tester.tap(find.text('下学期'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '除法'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '混合运算'), findsNothing);

    expect(chip('除法').selected, isTrue);

    // 切回二年级上学期仍保留除法选中态。
    await tester.tap(find.text('上学期'));
    await tester.pumpAndSettle();
    expect(chip('除法').selected, isTrue);

    // 一年级尚未开放除法，保留仍教授的减法而不重新选中加法。
    await tester.tap(find.widgetWithText(ChoiceChip, '1 年级'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '除法'), findsNothing);
    expect(chip('减法').selected, isTrue);
    expect(chip('加法').selected, isFalse);
    await tester.tap(find.widgetWithText(FilterChip, '减法'));
    await tester.pumpAndSettle();
    expect(chip('减法').selected, isTrue);

    // 仅选除法再切到一年级时，回退到首个可用项。
    await tester.tap(find.widgetWithText(ChoiceChip, '2 年级'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '除法'));
    await tester.tap(find.widgetWithText(FilterChip, '减法'));
    await tester.pumpAndSettle();
    expect(chip('除法').selected, isTrue);
    expect(chip('减法').selected, isFalse);
    await tester.tap(find.widgetWithText(ChoiceChip, '1 年级'));
    await tester.pumpAndSettle();
    expect(chip('加法').selected, isTrue);
  });
}
