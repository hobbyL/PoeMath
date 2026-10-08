// test/features/profile/llm_settings_page_test.dart
//
// AI 出题设置页 widget 测试：字段顺序与拉取按钮、模型拉取成功底部弹层
// 选择回填、拉取失败退化手填、Key 留空回退已存 Key 拉取、两按钮同行、
// 供应商名称保存与删除清理。
//
// 测试环境无平台安全存储通道，凭据与 LLM 网络均注入内存/HTTP mock。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/llm_settings_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
final class _MemoryCredentialStore extends SecureCredentialStore {
  String? llmApiKey;

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

Future<void> _pumpPage(
  WidgetTester tester, {
  _MemoryCredentialStore? credentialStore,
  http.Client? httpClient,
}) async {
  final store = credentialStore ?? _MemoryCredentialStore();
  final client = httpClient ??
      MockClient((_) async => http.Response('{}', 200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(store),
        llmSettingsHttpClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(home: LlmSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('字段顺序：供应商名称 → 服务地址 → API Key → 模型；'
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
    final testRow = find
        .ancestor(of: testBtn, matching: find.byType(Row))
        .evaluate()
        .first;
    final saveRow = find
        .ancestor(of: saveBtn, matching: find.byType(Row))
        .evaluate()
        .first;
    expect(testRow, same(saveRow));
    // 左右位置：测试连接 x 小于保存配置 x。
    final testCenter = tester.getCenter(testBtn);
    final saveCenter = tester.getCenter(saveBtn);
    expect(testCenter.dx, lessThan(saveCenter.dx));
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
    await tester.enterText(find.widgetWithText(TextFormField, '模型'),
        'my-model',);
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

  testWidgets('Key 留空但已存 Key：拉取用已存 Key（Authorization 头）',
      (tester) async {
    final store = _MemoryCredentialStore()..llmApiKey = 'stored-key';
    String? authHeader;
    final client = MockClient((request) async {
      authHeader = request.headers['authorization'];
      return http.Response('{"data": [{"id": "m"}]}', 200);
    });
    await _pumpPage(tester, credentialStore: store, httpClient: client);
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('从服务拉取模型列表'));
    await tester.pumpAndSettle();

    expect(authHeader, 'Bearer stored-key');
    expect(find.text('选择模型'), findsOneWidget);
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
    await tester.tapAt(tester.getCenter(find.byType(CircularProgressIndicator)));
    await tester.pump();
    expect(requests, 1);

    completer.complete(http.Response('{"data": [{"id": "m"}]}', 200));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });

  testWidgets('保存配置：供应商名称/地址/模型入 Hive，Key 入安全存储；'
      '保存后回读回填', (tester) async {
    final store = _MemoryCredentialStore();
    await _pumpPage(tester, credentialStore: store);

    await tester.enterText(
      find.widgetWithText(TextFormField, '供应商名称（可选）'),
      'DeepSeek',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '模型'),
        'deepseek-chat',);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key（可选）'),
      'secret-key',
    );
    await tester.pump();

    // Hive 写入在 testWidgets 的 FakeAsync 区无法落盘（本仓既有结论），
    // tap 须在 runAsync 的真实异步区内触发，保存链路才能完成落盘
    //（settings_page_test / word_problem_practice_page_test 先例）。
    await tester.runAsync(() async {
      await tester.tap(find.text('保存配置'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.llmApiKey, 'secret-key');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LlmSettingsPage)),
    );
    final repo = container.read(settingsRepositoryProvider);
    expect(repo.llmProviderName, 'DeepSeek');
    expect(repo.llmBaseUrl, 'https://api.example.com');
    expect(repo.llmModel, 'deepseek-chat');
    expect(find.text('LLM 服务配置已保存'), findsOneWidget);

    // Key 不回显：保存后 Key 输入框清空、占位提示切换。
    expect(
      (tester.widget<TextFormField>(
              find.widgetWithText(TextFormField, 'API Key（可选）'),)
          .controller)
          ?.text,
      '',
    );
    expect(find.text('已设置，留空保持不变'), findsOneWidget);
  });

  testWidgets('删除配置：供应商名称/地址/模型/Key 全部清除', (tester) async {
    final store = _MemoryCredentialStore()..llmApiKey = 'stored-key';
    await _pumpPage(tester, credentialStore: store);
    // 先保存一份完整配置。
    await tester.enterText(
      find.widgetWithText(TextFormField, '供应商名称（可选）'),
      'DeepSeek',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '模型'),
        'deepseek-chat',);
    await tester.pump();
    // 同上：tap 在 runAsync 真实异步区内触发，Hive 写入才能完成。
    await tester.runAsync(() async {
      await tester.tap(find.text('保存配置'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 等保存成功的 SnackBar 退出（它悬浮在页面底部，会盖住删除配置按钮）。
    await tester.pump(const Duration(seconds: 5));

    // 删除配置按钮出现（configured）；在 ListView 内先滚动到可视区，
    // 再用 hitTestable 确保命中按钮本体（TextBlock 中心可能仍被
    // 悬浮层/裁剪遮挡，对 TextButton 本体取点更稳）。
    final deleteBtnFinder = find.widgetWithText(TextButton, '删除配置');
    expect(deleteBtnFinder, findsOneWidget);
    await tester.ensureVisible(deleteBtnFinder);
    await tester.pump(const Duration(milliseconds: 300));
    final deleteBtn = deleteBtnFinder.hitTestable();
    expect(deleteBtn, findsOneWidget);
    // 打开确认弹窗的 tap 也在 runAsync 真实异步区内触发：_delete 的
    // await showDialog 挂起在真实 zone，确认删除后续写链才不会
    // 回落到 FakeAsync 区（Hive 删除会挂起）。
    await tester.runAsync(() async {
      await tester.tap(deleteBtn);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // 确认弹窗的删除同样在 runAsync 真实异步区内触发，
    // 留足真实时间后再回 FakeAsync 泵完退场动画与状态刷新。
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final container2 = ProviderScope.containerOf(
      tester.element(find.byType(LlmSettingsPage)),
    );
    final repo = container2.read(settingsRepositoryProvider);
    expect(repo.llmProviderName, '');
    expect(repo.llmBaseUrl, '');
    expect(repo.llmModel, '');
    expect(store.llmApiKey, isNull);
    expect(find.text('LLM 服务配置已删除'), findsOneWidget);
  });

  testWidgets('测试连接：Key 留空且已存 Key 时用已存 Key 请求 chat 接口',
      (tester) async {
    final store = _MemoryCredentialStore()..llmApiKey = 'stored-key';
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
    await tester.enterText(
      find.widgetWithText(TextFormField, '服务地址（Base URL）'),
      'https://api.example.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '模型'), 'm');
    await tester.pump();

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(authHeader, 'Bearer stored-key');
    expect(find.text('连接成功，模型可用'), findsOneWidget);
  });
}
