// test/features/profile/llm_settings_page_test.dart
//
// AI 出题设置页 widget 测试（多配置版）：配置列表与编辑区、空态引导、
// 新增保存、点行切换生效、编辑载入/Key 留空保留、删除确认与生效切换、
// 迁移场景、拉取模型弹层回填、拉取失败手填、拉取/连接防重入、
// 场景使用厂商区（隐藏/点选/清除/删除联动）。
//
// 测试环境无平台安全存储通道，凭据与 LLM 网络均注入内存/HTTP mock。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/llm_settings_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
/// 按 configId 存 Key（对齐真实存储键 `llm_api_key_{configId}`）；
/// 旧单键 llmApiKey 保留，供迁移用例预置。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> llmApiKeysByConfigId = {};
  String? llmApiKey;

  /// 可选读闸门：非 null 时 readLlmApiKeyFor 挂起直到其完成，用于构造
  /// 「点编辑（Key 读取 await 未返回）→ 点新增」竞态窗口（R2/AC2）。
  /// 默认 null 时行为等价立即返回，既有用例不受影响。
  Completer<void>? readGate;

  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {
    llmApiKeysByConfigId[configId] = apiKey;
  }

  @override
  Future<String?> readLlmApiKeyFor(String configId) async {
    final gate = readGate;
    if (gate != null) await gate.future;
    return llmApiKeysByConfigId[configId];
  }

  @override
  Future<void> deleteLlmApiKeyFor(String configId) async {
    llmApiKeysByConfigId.remove(configId);
  }

  @override
  Future<void> saveLlmApiKey(String apiKey) async {
    llmApiKey = apiKey;
  }

  @override
  Future<String?> readLlmApiKey() => Future.value(llmApiKey);

  @override
  Future<void> deleteLlmApiKey() async {
    llmApiKey = null;
  }
}

SettingsRepository _repoOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(LlmSettingsPage)),
  );
  return container.read(settingsRepositoryProvider);
}

/// 预置两条配置（p1 生效 + p2），便于编辑/切换/删除用例。
/// Hive 写链须在 runAsync 真实异步区执行（本仓既有结论）。
Future<void> _seedTwo(WidgetTester tester, _MemoryCredentialStore store) async {
  await tester.runAsync(() async {
    final repo = SettingsRepository(credentialStore: store);
    await repo.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      apiKey: 'key-p1',
    );
    await repo.saveLlmProviderConfig(
      id: 'p2',
      name: '',
      baseUrl: 'https://second.example.com',
      model: 'qwen-plus',
      apiKey: '',
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  _MemoryCredentialStore? credentialStore,
  http.Client? httpClient,
}) async {
  // 放大逻辑视口：页面列表区内容在默认 800x600 下会把表单字段与
  // 操作按钮行顶出 ListView 缓存区（懒挂载），tap 也会因中心越界落空。
  // TestFlutterView 每个测试结束自动复位。
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  final store = credentialStore ?? _MemoryCredentialStore();
  final client =
      httpClient ?? MockClient((_) async => http.Response('{}', 200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(store),
        llmSettingsHttpClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(home: LlmSettingsPage()),
    ),
  );
  // unawaited bootstrap（迁移场景含 Hive 写链）需要真实事件循环时间。
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

/// Hive 写链 tap：在 runAsync 真实异步区内触发 tap 并留足真实时间
///（本仓既有结论：FakeAsync 区 Hive 写入会挂起）。
Future<void> _tapReal(
  WidgetTester tester,
  Finder finder, {
  Duration delay = const Duration(milliseconds: 150),
}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(delay);
  });
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets(
      '字段顺序：供应商名称 → 服务地址 → API Key → 模型；'
      '模型框右侧有拉取按钮；两操作按钮同行', (tester) async {
    await _pumpPage(tester);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    // TextFormField 不暴露 decoration 公开 getter，从子树 TextField 读取。
    String? labelOf(int i) => tester
        .widget<TextField>(
          find.descendant(of: fields.at(i), matching: find.byType(TextField)),
        )
        .decoration
        ?.labelText;
    expect(labelOf(0), '供应商名称（可选）');
    expect(labelOf(1), '服务地址（Base URL）');
    expect(labelOf(2), 'API Key（可选）');
    expect(labelOf(3), '模型');

    // 模型输入框右侧拉取按钮存在。
    expect(find.byTooltip('从服务拉取模型列表'), findsOneWidget);

    // 测试连接与保存配置同一行：两按钮共同父级为 Row，
    // 且行内左侧为测试连接、右侧为保存配置。
    final testBtn = find.widgetWithText(OutlinedButton, '测试连接');
    final saveBtn = find.widgetWithText(FilledButton, '保存配置');
    expect(testBtn, findsOneWidget);
    expect(saveBtn, findsOneWidget);
    final testRow =
        find.ancestor(of: testBtn, matching: find.byType(Row)).evaluate().first;
    final saveRow =
        find.ancestor(of: saveBtn, matching: find.byType(Row)).evaluate().first;
    expect(testRow, same(saveRow));
    // 左右位置：测试连接 x 小于保存配置 x。
    final testCenter = tester.getCenter(testBtn);
    final saveCenter = tester.getCenter(saveBtn);
    expect(testCenter.dx, lessThan(saveCenter.dx));
  });

  testWidgets('空态：显示引导卡片与「新增配置」编辑区标题', (tester) async {
    await _pumpPage(tester);

    expect(find.text('我的配置'), findsOneWidget);
    expect(find.textContaining('还没有 LLM 配置'), findsOneWidget);
    expect(find.text('新增配置'), findsAtLeastNWidgets(1));
    // 新增按钮存在。
    expect(find.widgetWithText(OutlinedButton, '新增配置'), findsOneWidget);
    // 无配置时无删除按钮。
    expect(find.text('删除此配置'), findsNothing);
  });

  testWidgets('未填服务地址点拉取：SnackBar 提示、不发网络请求', (tester) async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response('{}', 200);
    });
    await _pumpPage(tester, httpClient: client);

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pump();

    expect(find.text('请先填写服务地址'), findsOneWidget);
    expect(requested, isFalse);
  });

  testWidgets('拉取成功弹出底部模型列表，点选回填输入框', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/models'));
      return http.Response(
        '{"data": [{"id": "qwen2.5:7b"}, {"id": "gpt-4o-mini"}]}',
        200,
      );
    });
    await _pumpPage(tester, httpClient: client);
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pumpAndSettle();

    // 底部弹层显示两个模型，点选一个。
    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('qwen2.5:7b'), findsOneWidget);
    await tester.tap(find.text('gpt-4o-mini'));
    await tester.pumpAndSettle();

    // 回填模型输入框，弹层关闭。
    expect(find.text('选择模型'), findsNothing);
    final modelField = find.widgetWithText(
      TextFormField,
      '模型',
    );
    expect(
      (tester.widget<TextFormField>(modelField).controller)?.text,
      'gpt-4o-mini',
    );
  });

  testWidgets('拉取失败 SnackBar 提示，手填值不破坏', (tester) async {
    final client = MockClient((_) async => http.Response('nope', 500));
    await _pumpPage(tester, httpClient: client);
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '模型'),
      'my-model',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pumpAndSettle();

    expect(find.textContaining('拉取模型失败'), findsOneWidget);
    final modelField = find.widgetWithText(TextFormField, '模型');
    expect(
      (tester.widget<TextFormField>(modelField).controller)?.text,
      'my-model',
    );
  });

  testWidgets('拉取中按钮显示加载态且防重入（重复点击不发第二次请求）', (tester) async {
    var requests = 0;
    final completer = Completer<http.Response>();
    final client = MockClient((_) async {
      requests++;
      return completer.future;
    });
    await _pumpPage(tester, httpClient: client);
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pump();
    expect(requests, 1);

    // 加载态：IconButton 消失，出现 CircularProgressIndicator。
    expect(find.byTooltip('从服务拉取模型列表'), findsNothing);
    // 重复点击无效果（按钮已不在树上）。
    await tester
        .tapAt(tester.getCenter(find.byType(CircularProgressIndicator)));
    await tester.pump();
    expect(requests, 1);

    completer.complete(http.Response('{"data": [{"id": "m"}]}', 200));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });

  testWidgets(
      '新增保存：列表出现该配置（空名兜底「配置 1」）并自动生效；'
      'Key 入安全存储、Hive 不含 Key 明文、Key 不回显', (tester) async {
    final store = _MemoryCredentialStore();
    await _pumpPage(tester, credentialStore: store);

    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '模型'),
      'deepseek-chat',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key（可选）'),
      'secret-key',
    );
    await tester.pump();

    await _tapReal(tester, find.text('保存配置'));

    // 列表出现该配置；空名兜底「配置 1」。
    expect(find.text('配置 1'), findsOneWidget);
    expect(find.text('api.example.com'), findsOneWidget);
    final repo = _repoOf(tester);
    expect(repo.llmProviders.length, 1);
    expect(repo.llmProviders[0].model, 'deepseek-chat');
    expect(repo.llmActiveProviderId, repo.llmProviders[0].id);
    expect(store.llmApiKeysByConfigId[repo.llmProviders[0].id], 'secret-key');
    // Hive 任何值不得包含 Key 明文。
    for (final value in HiveBoxes.settings.values) {
      expect('$value', isNot(contains('secret-key')));
    }
    expect(find.text('LLM 服务配置已保存'), findsOneWidget);

    // Key 不回显：保存后 Key 输入框清空、占位提示切换。
    expect(
      (tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'API Key（可选）'),
              )
              .controller)
          ?.text,
      '',
    );
    expect(find.text('已设置，留空保持不变'), findsOneWidget);
  });

  testWidgets('点列表行切换生效并持久化（重 pump 后保持）', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    var repo = _repoOf(tester);
    final p1 = repo.llmProviders[0].id;
    final p2 = repo.llmProviders[1].id;
    expect(repo.llmActiveProviderId, p1);

    // 点第二条行（Radio 区域）切换生效。
    // RadioListTile 的 InkWell 落在 Radio 区域，点行首与行文字均可；
    // 副标题为宿主名 second.example.com。
    // setLlmActiveProvider 是 Hive 写链：tap 须在 runAsync 真实区。
    await _tapReal(tester, find.text('second.example.com'));

    repo = _repoOf(tester);
    expect(repo.llmActiveProviderId, p2);

    // 重 pump（重进页面）后保持。
    await _pumpPage(tester, credentialStore: store);
    final repo2 = _repoOf(tester);
    expect(repo2.llmActiveProviderId, p2);
  });

  testWidgets(
      '编辑已有配置：点编辑按钮载入表单；保存更新字段；'
      'Key 留空保留旧 Key', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    // bootstrap 后默认编辑生效配置 p1。
    expect(find.text('编辑：DeepSeek'), findsOneWidget);
    expect(
      (tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, '服务地址（Base URL）'),
              )
              .controller)
          ?.text,
      'https://api.deepseek.com/v1',
    );
    // Key 不回显，但占位提示为「已设置」。
    expect(
      (tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'API Key（可选）'),
              )
              .controller)
          ?.text,
      '',
    );
    expect(find.text('已设置，留空保持不变'), findsOneWidget);

    // 修改模型名，Key 留空保存。
    await tester.enterText(
      find.widgetWithText(TextFormField, '模型'),
      'deepseek-reasoner',
    );
    await tester.pump();
    await _tapReal(tester, find.text('保存配置'));

    final repo = _repoOf(tester);
    expect(repo.llmProviders.length, 2); // 更新不追加。
    expect(repo.llmProviders[0].model, 'deepseek-reasoner');
    // Key 留空保留旧 Key。
    expect(store.llmApiKeysByConfigId['p1'], 'key-p1');
    expect(find.text('LLM 服务配置已保存'), findsOneWidget);
  });

  testWidgets('编辑已存配置拉取模型：Key 留空回退已存 Key（Authorization 头）', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    String? authHeader;
    final client = MockClient((request) async {
      authHeader = request.headers['authorization'];
      return http.Response('{"data": [{"id": "m"}]}', 200);
    });
    await _pumpPage(tester, credentialStore: store, httpClient: client);

    // bootstrap 默认编辑生效配置 p1（已存 key-p1）。
    expect(find.text('编辑：DeepSeek'), findsOneWidget);

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pumpAndSettle();

    expect(authHeader, 'Bearer key-p1');
    expect(find.text('选择模型'), findsOneWidget);
  });

  testWidgets('测试连接：Key 留空且已存 Key 时用已存 Key 请求 chat 接口', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    String? authHeader;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/chat/completions')) {
        authHeader = request.headers['authorization'];
        return http.Response(
          '{"choices": [{"message": {"content": "hi"}}]}',
          200,
        );
      }
      return http.Response('{}', 200);
    });
    await _pumpPage(tester, credentialStore: store, httpClient: client);

    // bootstrap 默认编辑 p1；表单载入 baseUrl + model，直接点测试连接。
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(authHeader, 'Bearer key-p1');
    expect(find.text('连接成功，模型可用'), findsOneWidget);
  });

  testWidgets('删除配置：确认弹窗后清除配置与 Key；删除生效配置切到剩余第一条', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    // 默认编辑生效配置 p1；删除按钮出现（编辑态）。
    final deleteBtnFinder = find.widgetWithText(TextButton, '删除此配置');
    expect(deleteBtnFinder, findsOneWidget);
    await tester.ensureVisible(deleteBtnFinder);
    await tester.pump(const Duration(milliseconds: 300));
    final deleteBtn = deleteBtnFinder.hitTestable();
    expect(deleteBtn, findsOneWidget);

    // 打开确认弹窗的 tap 在 runAsync 真实异步区内触发。
    await tester.runAsync(() async {
      await tester.tap(deleteBtn);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 确认弹窗内容与按钮。
    expect(find.text('删除此配置'), findsAtLeastNWidgets(1));
    expect(find.textContaining('已保存的 API Key'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final repo = _repoOf(tester);
    expect(repo.llmProviders.length, 1);
    expect(repo.llmProviders[0].id, 'p2');
    // 删除生效配置后 active 切到剩余第一条。
    expect(repo.llmActiveProviderId, 'p2');
    expect(store.llmApiKeysByConfigId['p1'], isNull);
    expect(find.text('LLM 服务配置已删除'), findsOneWidget);
    // 删除后表单重置为新增态。
    expect(find.text('新增配置'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(TextButton, '删除此配置'), findsNothing);
  });

  testWidgets('旧单配置迁移：bootstrap 后列表出现迁移配置并默认编辑', (tester) async {
    final store = _MemoryCredentialStore()..llmApiKey = 'legacy-key';
    // 预置旧版单配置落盘状态（Hive 写链须在 runAsync 真实异步区）。
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_base_url', 'https://old.example.com');
      await HiveBoxes.settings.put('llm_model', 'old-model');
      await HiveBoxes.settings.put('llm_provider_name', '旧厂商');
    });

    // 页面 bootstrap 的迁移本身是 Hive 写链，在 FakeAsync 区发起会永久
    // 挂起（本仓既有结论），因此首帧装载放进 runAsync 真实异步区完成。
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    final client = MockClient(
      (_) async => http.Response('{}', 200),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureCredentialStoreProvider.overrideWithValue(store),
            llmSettingsHttpClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(home: LlmSettingsPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    // 迁移完成：列表出现旧配置，编辑区默认编辑它。
    expect(find.text('旧厂商'), findsAtLeastNWidgets(1));
    expect(find.text('编辑：旧厂商'), findsOneWidget);
    final repo = _repoOf(tester);
    expect(repo.llmProviders.length, 1);
    expect(repo.llmProviders[0].baseUrl, 'https://old.example.com');
    expect(repo.llmProviders[0].model, 'old-model');
    expect(HiveBoxes.settings.get('llm_base_url'), isNull);
    // 旧 Key 已复制到新键位，旧单 Key 清除。
    final newId = repo.llmProviders[0].id;
    expect(store.llmApiKeysByConfigId[newId], 'legacy-key');
    expect(store.llmApiKey, isNull);
  });

  testWidgets('「新增配置」按钮重置编辑区为空表单（不触碰 active）', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    expect(find.text('编辑：DeepSeek'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pump();

    // 编辑区标题切到新增态，表单清空。
    expect(find.text('编辑：DeepSeek'), findsNothing);
    expect(find.text('新增配置'), findsAtLeastNWidgets(1));
    expect(
      (tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, '服务地址（Base URL）'),
              )
              .controller)
          ?.text,
      '',
    );
    expect(find.text('无鉴权服务可留空'), findsOneWidget);
    // active 不受影响。
    final repo = _repoOf(tester);
    expect(repo.llmActiveProviderId, 'p1');
  });

  group('场景使用厂商区', () {
    testWidgets('空配置时整区隐藏', (tester) async {
      await _pumpPage(tester);

      expect(find.text('场景使用厂商'), findsNothing);
      for (final scenario in LlmScenario.values) {
        expect(find.text(scenario.label), findsNothing);
      }
    });

    testWidgets('有配置时三行均显示「跟随默认（生效配置名）」', (tester) async {
      final store = _MemoryCredentialStore();
      await _seedTwo(tester, store);
      await _pumpPage(tester, credentialStore: store);

      expect(find.text('场景使用厂商'), findsOneWidget);
      expect(find.text('AI 出题'), findsOneWidget);
      expect(find.text('诗词讲解'), findsOneWidget);
      expect(find.text('口算解析'), findsOneWidget);
      // 三场景默认未绑定 → 跟随 active（p1 = DeepSeek）。
      expect(find.text('跟随默认（DeepSeek）'), findsNWidgets(3));
    });

    testWidgets('点行弹层点选厂商：持久化、副标题更新、重进页面保持', (tester) async {
      final store = _MemoryCredentialStore();
      await _seedTwo(tester, store);
      await _pumpPage(tester, credentialStore: store);

      await _openScenarioSheet(tester, '诗词讲解');

      // 弹层标题与选项（「跟随默认」+ 两条配置，p2 空名兜底「配置 2」）。
      expect(find.text('诗词讲解使用厂商'), findsOneWidget);
      expect(_sheetTile('跟随默认'), findsOneWidget);
      expect(_sheetTile('DeepSeek'), findsOneWidget);
      expect(_sheetTile('配置 2'), findsOneWidget);

      // 点选即持久化并关闭。弹层打开已在 _openScenarioSheet 的真实区
      // 完成，点选 tap 同样包 runAsync：pop → sheet future → Hive 写链
      // → setState 整链留在真实区；pump 回 FakeAsync 区推帧拿最终 UI
      //（本仓既有结论：FakeAsync 区 Hive 写入会挂起）。
      await tester.runAsync(() async {
        await tester.tap(_sheetTile('配置 2'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('诗词讲解使用厂商'), findsNothing);
      var repo = _repoOf(tester);
      expect(repo.providerIdForScenario(LlmScenario.poemExplain), 'p2');
      // 其他场景不受影响。
      expect(repo.providerIdForScenario(LlmScenario.mathExplain), isNull);
      expect(repo.providerIdForScenario(LlmScenario.wordProblem), isNull);
      // 该行副标题切为厂商名，其余两行仍跟随默认。
      expect(
        find.descendant(
          of: find.widgetWithText(AppTile, '诗词讲解'),
          matching: find.text('配置 2'),
        ),
        findsOneWidget,
      );
      expect(find.text('跟随默认（DeepSeek）'), findsNWidgets(2));

      // 重进页面保持。
      await _pumpPage(tester, credentialStore: store);
      repo = _repoOf(tester);
      expect(repo.providerIdForScenario(LlmScenario.poemExplain), 'p2');
      expect(
        find.descendant(
          of: find.widgetWithText(AppTile, '诗词讲解'),
          matching: find.text('配置 2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('已绑定行选「跟随默认」清除绑定', (tester) async {
      final store = _MemoryCredentialStore();
      await _seedTwo(tester, store);
      await tester.runAsync(() async {
        await SettingsRepository(credentialStore: store)
            .setProviderIdForScenario(LlmScenario.mathExplain, 'p2');
      });
      await _pumpPage(tester, credentialStore: store);

      expect(
        find.descendant(
          of: find.widgetWithText(AppTile, '口算解析'),
          matching: find.text('配置 2'),
        ),
        findsOneWidget,
      );

      await _openScenarioSheet(tester, '口算解析');
      await tester.runAsync(() async {
        await tester.tap(_sheetTile('跟随默认'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final repo = _repoOf(tester);
      expect(repo.providerIdForScenario(LlmScenario.mathExplain), isNull);
      expect(HiveBoxes.settings.get('llm_provider_math_explain'), isNull);
      expect(find.text('跟随默认（DeepSeek）'), findsNWidgets(3));
    });

    testWidgets('删除配置后指向它的场景绑定回落跟随默认', (tester) async {
      final store = _MemoryCredentialStore();
      await _seedTwo(tester, store);
      await tester.runAsync(() async {
        await SettingsRepository(credentialStore: store)
            .setProviderIdForScenario(LlmScenario.poemExplain, 'p1');
      });
      await _pumpPage(tester, credentialStore: store);

      expect(
        find.descendant(
          of: find.widgetWithText(AppTile, '诗词讲解'),
          matching: find.text('DeepSeek'),
        ),
        findsOneWidget,
      );

      // 删除 p1（默认编辑生效配置 p1）。
      final deleteBtnFinder = find.widgetWithText(TextButton, '删除此配置');
      await tester.ensureVisible(deleteBtnFinder);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await tester.tap(deleteBtnFinder.hitTestable());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '删除'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final repo = _repoOf(tester);
      expect(repo.providerIdForScenario(LlmScenario.poemExplain), isNull);
      expect(HiveBoxes.settings.get('llm_provider_poem_explain'), isNull);
      // 回落到剩余 active（p2 空名 → 配置 1）。
      expect(find.text('跟随默认（配置 1）'), findsNWidgets(3));
    });
  });

  testWidgets(
      'R2 竞态：编辑 Key 读取未返回时点「新增配置」→ 表单保持空，'
      '保存产生新配置而非静默覆盖旧配置', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    // bootstrap 默认编辑生效配置 p1（readGate 未装，立即返回）。
    expect(find.text('编辑：DeepSeek'), findsOneWidget);

    // 装读闸门：下一次 _startEdit 的 Key 读取挂起，制造在途窗口。
    store.readGate = Completer<void>();

    // 点 p1 行编辑按钮 → _startEdit 进入在途（seq=2，挂在闸门上）。
    final editP1 = find.byTooltip('编辑此配置').first;
    await tester.ensureVisible(editP1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(editP1);
    await tester.pump();

    // await 未返回时点「新增配置」→ _startCreate 清空表单、editingId=null、
    // _editSeq 递增（seq=3）使在途编辑续体失效。
    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pump();
    expect(find.text('编辑：DeepSeek'), findsNothing);
    // 放行闸门：在途 _startEdit 续体恢复，但 seq 2≠3 → 提前返回，
    // 不得把已清空的表单覆盖回 p1。
    store.readGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('编辑：DeepSeek'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, '服务地址（Base URL）'),
          )
          .controller
          ?.text,
      '',
    );

    // 填新表单保存 → 第三条配置，p1 原值与 Key 不受污染。
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.new.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '模型'),
      'new-model',
    );
    await tester.pump();
    await _tapReal(tester, find.text('保存配置'));

    final repo = _repoOf(tester);
    expect(repo.llmProviders.length, 3);
    expect(repo.llmProviders[0].id, 'p1');
    expect(repo.llmProviders[0].model, 'deepseek-chat');
    expect(store.llmApiKeysByConfigId['p1'], 'key-p1');
    expect(repo.llmProviders[2].model, 'new-model');
  });
  testWidgets(
      'R7 清除 Key：编辑有存 Key 配置显示清除入口；确认后删除 Key、'
      '占位提示回退、配置本身保留', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    // bootstrap 编辑 p1（已存 key-p1）→ 清除入口与「已设置」占位出现。
    expect(find.text('编辑：DeepSeek'), findsOneWidget);
    final clearBtn = find.widgetWithText(TextButton, '清除已保存的 Key');
    expect(clearBtn, findsOneWidget);
    expect(find.text('已设置，留空保持不变'), findsOneWidget);

    // 打开确认弹层（弹层打开 tap 入 runAsync 真实区——对齐删除确认范式）。
    await tester.ensureVisible(clearBtn);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await tester.tap(clearBtn.hitTestable());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('不带 Key 请求'), findsOneWidget);

    // 确认清除（确认 tap 入 runAsync 真实区）。
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '清除'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Key 删除、占位回退、入口消失；配置与 active 保留。
    expect(store.llmApiKeysByConfigId['p1'], isNull);
    expect(find.text('无鉴权服务可留空'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清除已保存的 Key'), findsNothing);
    final repo = _repoOf(tester);
    expect(repo.llmProviders.length, 2);
    expect(repo.llmActiveProviderId, 'p1');
    expect(find.text('已清除保存的 API Key'), findsOneWidget);
  });
}

/// 场景选择弹层内的选项（页面配置列表同样用 RadioListTile，须限定弹层内）。
Finder _sheetTile(String title) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(RadioListTile<String>, title),
    );

/// 点场景行打开选择弹层。
/// 打开 tap 也须在 runAsync 真实区：`await showModalBottomSheet` 的
/// 续体（点选后的 Hive 写链 + setState）注册在打开 tap 所在 zone，
/// 若在 FakeAsync 区打开，写链会落回 FakeAsync 区挂起（对齐删除
/// 确认弹窗的既有范式：弹层的打开与确认 tap 各包一个 runAsync）。
Future<void> _openScenarioSheet(WidgetTester tester, String label) async {
  final row = find.text(label);
  await tester.ensureVisible(row);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    await tester.tap(row);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
  await tester.pumpAndSettle();
}
