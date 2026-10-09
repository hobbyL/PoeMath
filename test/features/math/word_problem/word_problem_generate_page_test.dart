// test/features/math/word_problem/word_problem_generate_page_test.dart
//
// 生成页 widget 测试：未配置 LLM 时显示引导态；
// 骨架生成失败（StateError）时展示中文提示而非英文堆栈。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/word_problem/word_problem_generate_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';

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

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
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
}
