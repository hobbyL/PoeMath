// test/features/profile/ai_settings_assistant_toggle_test.dart
//
// AI 设置页「AI 助手」开关 widget 测试：
//   - 默认关闭：Switch 为 off，副标题「悬浮入口已关闭」；
//   - 点击开关：翻转为 on，副标题变「悬浮入口已开启」。
// Hive 写链 tap 在 runAsync 真实异步区执行（本仓既有结论）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/profile/ai_settings_page.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现（页面经
/// settingsRepositoryProvider 间接依赖它，须可构造）。
final class _MemoryCredentialStore extends SecureCredentialStore {
  @override
  Future<String?> readLlmApiKey() => Future.value(null);
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureCredentialStoreProvider
            .overrideWithValue(_MemoryCredentialStore()),
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

  testWidgets('默认关闭：Switch off，副标题为已关闭', (tester) async {
    await _pumpPage(tester);

    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('悬浮入口已关闭'), findsOneWidget);

    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isFalse);
  });

  testWidgets('点击开关：翻转为开启并更新副标题', (tester) async {
    await _pumpPage(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch));
    });
    await tester.pumpAndSettle();

    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isTrue);
    expect(find.text('悬浮入口已开启'), findsOneWidget);
  });
}
