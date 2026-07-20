import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/webdav_config_page.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _FakeWebDavConfig extends Fake implements WebDavConfig {}

Future<void> _fillForm(WidgetTester tester, {required String url}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), '测试配置');
  await tester.enterText(fields.at(1), url);
  await tester.enterText(fields.at(2), 'alice');
  await tester.enterText(fields.at(3), 'secret');
  await tester.enterText(fields.at(4), '/poemath/');
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeWebDavConfig());
  });

  testWidgets('HTTP 地址在表单层被拒绝', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WebDavConfigPage()),
      ),
    );
    await tester.pump();
    await _fillForm(tester, url: 'http://dav.example.com');

    await tester.tap(find.text('测试链接'));
    await tester.pump();

    expect(find.text('服务器地址必须使用 HTTPS，不支持明文 HTTP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('保存失败后按钮恢复可操作并显示错误', (tester) async {
    final settings = _MockSettingsRepository();
    when(() => settings.saveWebDavConfig(any())).thenAnswer(
      (_) async => throw StateError('settings unavailable'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: const MaterialApp(home: WebDavConfigPage()),
      ),
    );
    await tester.pump();
    await _fillForm(tester, url: 'https://dav.example.com');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败: Bad state: settings unavailable'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
