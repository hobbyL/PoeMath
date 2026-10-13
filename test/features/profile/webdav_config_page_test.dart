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

  testWidgets('密码默认密文，点「显示密码」后可切明文并再次隐藏', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: WebDavConfigPage()),
      ),
    );
    await tester.pump();

    // 密码是第 4 个字段（索引 3）。
    final passwordField = find.byType(TextFormField).at(3);
    EditableText editable() => tester.widget<EditableText>(
          find.descendant(
            of: passwordField,
            matching: find.byType(EditableText),
          ),
        );

    // 默认密文。
    expect(editable().obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    // 眼睛图标可能在视口外，先滚动到可见再点。
    await tester.ensureVisible(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    // 点眼睛 → 明文。
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(editable().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // 再点 → 回到密文。
    await tester.ensureVisible(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(editable().obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('编辑已有配置：回填安全存储的密码，且可切明文查看', (tester) async {
    final settings = _MockSettingsRepository();
    // 传入的 existing 凭据为空 → 触发 _loadCredentials 从安全存储取回。
    when(() => settings.loadWebDavConfigWithCredentials(any())).thenAnswer(
      (_) async => WebDavConfig(
        id: 'cfg-1',
        name: '家庭云盘',
        url: 'https://dav.example.com',
        username: 'alice',
        password: 'stored-secret',
        remotePath: '/poemath/',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          home: WebDavConfigPage(
            existing: WebDavConfig(
              id: 'cfg-1',
              name: '家庭云盘',
              url: 'https://dav.example.com',
              username: '',
              password: '',
              remotePath: '/poemath/',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 密码框（索引 3）已回填安全存储中的明文；账户同样回填。
    final fields = find.byType(TextFormField);
    expect(
      tester.widget<TextFormField>(fields.at(3)).controller?.text,
      'stored-secret',
    );
    expect(
      tester.widget<TextFormField>(fields.at(2)).controller?.text,
      'alice',
    );

    // 回填后默认仍是密文，点眼睛可显示（这是刻意保留的能力：
    // 已存密码允许明文核对）。
    final passwordField = fields.at(3);
    EditableText editable() => tester.widget<EditableText>(
          find.descendant(
            of: passwordField,
            matching: find.byType(EditableText),
          ),
        );
    expect(editable().obscureText, isTrue);

    await tester.ensureVisible(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(editable().obscureText, isFalse);

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
