// test/features/profile/llm_scenario_settings_page_test.dart
//
// 使用场景设置页 widget 测试：四场景行展示与「跟随默认」摘要、
// 点行弹层点选厂商持久化、清除绑定、空配置引导。
// （供应商增删的联动回落由仓储层 providerIdForScenario 悬空回落保证，
// 仓储测试已覆盖；本页不再重复删除联动用例。）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/llm_scenario_settings_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> llmApiKeysByConfigId = {};

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
  Future<void> saveLlmApiKey(String apiKey) async {}

  @override
  Future<String?> readLlmApiKey() async => null;

  @override
  Future<void> deleteLlmApiKey() async {}
}

SettingsRepository _repoOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(LlmScenarioSettingsPage)),
  );
  return container.read(settingsRepositoryProvider);
}

/// 预置两条配置（p1 生效 + p2，p2 空名 → 展示兜底「配置 2」）。
/// Hive 写链须在 runAsync 真实异步区执行（本仓既有结论）。
Future<void> _seedTwo(_MemoryCredentialStore store) async {
  await Future<void>.delayed(Duration.zero);
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
}

Future<void> _pumpPage(
  WidgetTester tester, {
  _MemoryCredentialStore? credentialStore,
}) async {
  final store = credentialStore ?? _MemoryCredentialStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: LlmScenarioSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 场景选择弹层内的选项。
Finder _sheetTile(String title) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(RadioListTile<String>, title),
    );

/// 点场景行打开选择弹层。
/// 打开 tap 须在 runAsync 真实区：`await showModalBottomSheet` 的
/// 续体（点选后的 Hive 写链 + setState）注册在打开 tap 所在 zone，
/// 若在 FakeAsync 区打开，写链会落回 FakeAsync 区挂起。
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

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('空配置：显示引导卡片，无场景行', (tester) async {
    await _pumpPage(tester);

    expect(find.textContaining('还没有可用的厂商配置'), findsOneWidget);
    for (final scenario in LlmScenario.values) {
      expect(find.text(scenario.label), findsNothing);
    }
  });

  testWidgets('有配置时四行均显示「跟随默认（生效配置名）」', (tester) async {
    final store = _MemoryCredentialStore();
    await tester.runAsync(() => _seedTwo(store));
    await _pumpPage(tester, credentialStore: store);

    expect(find.text('AI 出题'), findsOneWidget);
    expect(find.text('诗词讲解'), findsOneWidget);
    expect(find.text('口算解析'), findsOneWidget);
    expect(find.text('AI 助手'), findsOneWidget);
    // 四场景默认未绑定 → 跟随 active（p1 = DeepSeek）。
    expect(find.text('跟随默认（DeepSeek）'), findsNWidgets(4));
  });

  testWidgets('点行弹层点选厂商：持久化、副标题更新、重进页面保持',
      (tester) async {
    final store = _MemoryCredentialStore();
    await tester.runAsync(() => _seedTwo(store));
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
    expect(repo.providerIdForScenario(LlmScenario.assistant), isNull);
    // 该行副标题切为厂商名，其余三行仍跟随默认。
    expect(
      find.descendant(
        of: find.widgetWithText(AppTile, '诗词讲解'),
        matching: find.text('配置 2'),
      ),
      findsOneWidget,
    );
    expect(find.text('跟随默认（DeepSeek）'), findsNWidgets(3));

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
    await tester.runAsync(() async {
      await _seedTwo(store);
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
    expect(find.text('跟随默认（DeepSeek）'), findsNWidgets(4));
  });
}
