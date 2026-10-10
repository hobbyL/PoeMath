// test/features/profile/llm_provider_settings_page_test.dart
//
// 供应商设置页 widget 测试（拆分版）：配置列表与空态引导、点行切换生效、
// 新增/编辑全屏弹窗（保存更新、Key 留空保留、删除确认与生效切换、
// 拉取模型弹层回填、拉取失败手填、拉取/连接防重入、清除 Key）、
// 旧单配置迁移。场景绑定测试见 llm_scenario_settings_page_test.dart。
//
// 测试环境无平台安全存储通道，凭据与 LLM 网络均注入内存/HTTP mock。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/llm_provider_settings_page.dart';
import 'package:poemath/features/profile/widgets/llm_provider_edit_dialog.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
/// 按 configId 存 Key（对齐真实存储键 `llm_api_key_{configId}`）；
/// 旧单键 llmApiKey 保留，供迁移用例预置。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> llmApiKeysByConfigId = {};
  String? llmApiKey;

  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {
    llmApiKeysByConfigId[configId] = apiKey;
  }

  @override
  Future<String?> readLlmApiKeyFor(String configId) async {
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
    tester.element(find.byType(LlmProviderSettingsPage)),
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
  final store = credentialStore ?? _MemoryCredentialStore();
  final client =
      httpClient ?? MockClient((_) async => http.Response('{}', 200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(store),
        llmSettingsHttpClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(home: LlmProviderSettingsPage()),
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

  testWidgets('空态：显示引导卡片与「新增配置」按钮，无编辑表单', (tester) async {
    await _pumpPage(tester);

    expect(find.text('我的配置'), findsOneWidget);
    expect(find.textContaining('还没有 LLM 配置'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '新增配置'), findsOneWidget);
    // 列表页不再内联编辑表单：字段在新增/编辑弹窗内。
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('删除此配置'), findsNothing);
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
      '新增配置：点「新增配置」打开全屏弹窗；保存后列表出现该配置（空名兜底'
      '「配置 1」）并自动生效；Key 入安全存储、Hive 不含 Key 明文', (tester) async {
    final store = _MemoryCredentialStore();
    await _pumpPage(tester, credentialStore: store);

    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pumpAndSettle();

    // 全屏弹窗：标题 + 四个字段。
    expect(find.text('新增配置'), findsAtLeastNWidgets(1));
    expect(find.byType(TextFormField), findsNWidgets(4));

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

    // 弹窗关闭，列表出现该配置；空名兜底「配置 1」。
    expect(find.text('新增配置'), findsOneWidget);
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
  });

  testWidgets(
    '编辑已有配置：载入字段并回显 Key（默认密文，眼睛切明文）；'
    '保存更新；Key 原样保留',
    (tester) async {
      final store = _MemoryCredentialStore();
      await _seedTwo(tester, store);
      await _pumpPage(tester, credentialStore: store);

      // 点 p1 行编辑按钮打开全屏弹窗。
      final editBtn = find.byTooltip('编辑此配置').first;
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

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
      // Key 回显为已存值；默认密文，点眼睛切明文、再点回密文。
      final keyField = find.widgetWithText(TextFormField, 'API Key（可选）');
      expect(
        (tester.widget<TextFormField>(keyField).controller)?.text,
        'key-p1',
      );
      EditableText keyEditable() => tester.widget<EditableText>(
            find.descendant(
              of: keyField,
              matching: find.byType(EditableText),
            ),
          );
      expect(keyEditable().obscureText, isTrue);
      await tester.tap(find.byTooltip('显示 API Key'));
      await tester.pump();
      expect(keyEditable().obscureText, isFalse);
      await tester.tap(find.byTooltip('隐藏 API Key'));
      await tester.pump();
      expect(keyEditable().obscureText, isTrue);

      // 修改模型名，Key 原样（回显值）保存。
      await tester.enterText(
        find.widgetWithText(TextFormField, '模型'),
        'deepseek-reasoner',
      );
      await tester.pump();
      await _tapReal(tester, find.text('保存配置'));

      final repo = _repoOf(tester);
      expect(repo.llmProviders.length, 2); // 更新不追加。
      expect(repo.llmProviders[0].model, 'deepseek-reasoner');
      // Key 原样回显并保存，仍为旧值。
      expect(store.llmApiKeysByConfigId['p1'], 'key-p1');
      expect(find.text('LLM 服务配置已保存'), findsOneWidget);
    },
  );

  testWidgets('编辑已存配置拉取模型：用回显的已存 Key（Authorization 头）',
      (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    String? authHeader;
    final client = MockClient((request) async {
      authHeader = request.headers['authorization'];
      return http.Response('{"data": [{"id": "m"}]}', 200);
    });
    await _pumpPage(tester, credentialStore: store, httpClient: client);

    // 打开 p1 编辑弹窗（已存 key-p1）。
    await tester.tap(find.byTooltip('编辑此配置').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑：DeepSeek'), findsOneWidget);

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pumpAndSettle();

    expect(authHeader, 'Bearer key-p1');
    expect(find.text('选择模型'), findsOneWidget);
  });

  testWidgets('测试连接：用回显的已存 Key 请求 chat 接口',
      (tester) async {
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

    // 打开 p1 编辑弹窗（表单载入 baseUrl + model），直接点测试连接。
    await tester.tap(find.byTooltip('编辑此配置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(authHeader, 'Bearer key-p1');
    expect(find.text('连接成功，模型可用'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pumpAndSettle();
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

  testWidgets('未填服务地址点拉取：SnackBar 提示、不发网络请求', (tester) async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response('{}', 200);
    });
    await _pumpPage(tester, httpClient: client);

    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pump();

    expect(find.text('请先填写服务地址'), findsOneWidget);
    expect(requested, isFalse);
  });

  testWidgets('拉取失败 SnackBar 提示，手填值不破坏', (tester) async {
    final client = MockClient((_) async => http.Response('nope', 500));
    await _pumpPage(tester, httpClient: client);

    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pumpAndSettle();
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

  testWidgets('拉取中按钮显示加载态且防重入（重复点击不发第二次请求）',
      (tester) async {
    var requests = 0;
    final completer = Completer<http.Response>();
    final client = MockClient((_) async {
      requests++;
      return completer.future;
    });
    await _pumpPage(tester, httpClient: client);

    await tester.tap(find.widgetWithText(OutlinedButton, '新增配置'));
    await tester.pumpAndSettle();
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
      '删除配置：编辑弹窗内确认后清除配置与 Key；删除生效配置切到剩余第一条',
      (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    // 打开 p1（生效配置）编辑弹窗；删除按钮出现（编辑态）。
    await tester.tap(find.byTooltip('编辑此配置').first);
    await tester.pumpAndSettle();
    final deleteBtnFinder = find.widgetWithText(TextButton, '删除此配置');
    expect(deleteBtnFinder, findsOneWidget);

    // 打开确认弹窗的 tap 在 runAsync 真实异步区内触发。
    await tester.runAsync(() async {
      await tester.tap(deleteBtnFinder);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 确认弹窗内容与按钮。
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
    // 弹窗关闭，列表回到无弹窗态。
    expect(find.text('删除此配置'), findsNothing);
  });

  testWidgets('旧单配置迁移：bootstrap 后列表出现迁移配置', (tester) async {
    final store = _MemoryCredentialStore()..llmApiKey = 'legacy-key';
    // 预置旧版单配置落盘状态（Hive 写链须在 runAsync 真实异步区）。
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('llm_base_url', 'https://old.example.com');
      await HiveBoxes.settings.put('llm_model', 'old-model');
      await HiveBoxes.settings.put('llm_provider_name', '旧厂商');
    });

    // 页面 bootstrap 的迁移本身是 Hive 写链，在 FakeAsync 区发起会永久
    // 挂起（本仓既有结论），因此首帧装载放进 runAsync 真实异步区完成。
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
          child: const MaterialApp(home: LlmProviderSettingsPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    // 迁移完成：列表出现旧配置。
    expect(find.text('旧厂商'), findsAtLeastNWidgets(1));
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

  testWidgets(
    'R7 清除 Key：编辑有存 Key 配置显示清除入口；确认后删除 Key、'
    '占位提示回退、配置本身保留',
    (tester) async {
      final store = _MemoryCredentialStore();
      await _seedTwo(tester, store);
      await _pumpPage(tester, credentialStore: store);

      // 打开 p1 编辑弹窗（已存 key-p1）→ 清除入口出现、Key 回显。
      await tester.tap(find.byTooltip('编辑此配置').first);
      await tester.pumpAndSettle();
      expect(find.text('编辑：DeepSeek'), findsOneWidget);
      final clearBtn = find.widgetWithText(TextButton, '清除已保存的 Key');
      expect(clearBtn, findsOneWidget);
      expect(
        (tester
                .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'API Key（可选）'),
                )
                .controller)
            ?.text,
        'key-p1',
      );

      // 打开确认弹层（弹层打开 tap 入 runAsync 真实区——对齐删除确认范式）。
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

      // Key 删除、输入框回显清空、占位回退、入口消失；配置与 active 保留。
      expect(store.llmApiKeysByConfigId['p1'], isNull);
      expect(
        (tester
                .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'API Key（可选）'),
                )
                .controller)
            ?.text,
        '',
      );
      expect(find.text('无鉴权服务可留空'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '清除已保存的 Key'), findsNothing);
      final repo = _repoOf(tester);
      expect(repo.llmProviders.length, 2);
      expect(repo.llmActiveProviderId, 'p1');
      expect(find.text('已清除保存的 API Key'), findsOneWidget);
    },
  );

  testWidgets('多配置之间以分割线隔开（2 条配置 → 1 条分割线）', (tester) async {
    final store = _MemoryCredentialStore();
    await _seedTwo(tester, store);
    await _pumpPage(tester, credentialStore: store);

    // 两条配置之间恰有一条分割线（首项前不插）。
    expect(find.byType(Divider), findsOneWidget);
  });
}
