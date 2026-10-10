// test/features/profile/ai_settings_page_test.dart
//
// AI 设置枢纽页 widget 测试：三个入口 AppTile 展示、供应商数量副标题、
// 各入口可点击打开子页。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/ai_settings_page.dart';
import 'package:poemath/features/profile/llm_provider_settings_page.dart';
import 'package:poemath/features/profile/llm_scenario_settings_page.dart';
import 'package:poemath/features/profile/prompt_settings_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
final class _MemoryCredentialStore extends SecureCredentialStore {
  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {}

  @override
  Future<String?> readLlmApiKeyFor(String configId) async => null;

  @override
  Future<void> deleteLlmApiKeyFor(String configId) async {}

  @override
  Future<void> saveLlmApiKey(String apiKey) async {}

  @override
  Future<String?> readLlmApiKey() async => null;

  @override
  Future<void> deleteLlmApiKey() async {}
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(
          _MemoryCredentialStore(),
        ),
      ],
      child: const MaterialApp(home: AiSettingsPage()),
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

  testWidgets('枢纽页展示三个入口与「未配置」副标题', (tester) async {
    await _pumpPage(tester);

    expect(find.text('AI 设置'), findsOneWidget);
    expect(find.widgetWithText(AppTile, '供应商设置'), findsOneWidget);
    expect(find.widgetWithText(AppTile, '使用场景设置'), findsOneWidget);
    expect(find.widgetWithText(AppTile, '提示词设置'), findsOneWidget);
    // 无配置：供应商行显示「未配置」，场景行引导先配置。
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('请先配置供应商'), findsOneWidget);
  });

  testWidgets('有配置时供应商副标题显示数量', (tester) async {
    final store = _MemoryCredentialStore();
    await tester.runAsync(() async {
      final repo = SettingsRepository(credentialStore: store);
      await repo.saveLlmProviderConfig(
        id: 'p1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
        apiKey: 'k',
      );
      await repo.saveLlmProviderConfig(
        id: 'p2',
        name: 'Qwen',
        baseUrl: 'https://dashscope.example.com/compatible-mode/v1',
        model: 'qwen-plus',
        apiKey: '',
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureCredentialStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: AiSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已配置 2 个服务'), findsOneWidget);
    expect(find.text('为各功能指定厂商'), findsOneWidget);
  });

  testWidgets('点供应商设置打开子页', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('供应商设置'));
    await tester.pumpAndSettle();
    expect(find.byType(LlmProviderSettingsPage), findsOneWidget);
  });

  testWidgets('点使用场景设置打开子页', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('使用场景设置'));
    await tester.pumpAndSettle();
    expect(find.byType(LlmScenarioSettingsPage), findsOneWidget);
  });

  testWidgets('点提示词设置打开子页', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('提示词设置'));
    await tester.pumpAndSettle();
    expect(find.byType(PromptSettingsPage), findsOneWidget);
  });
}
