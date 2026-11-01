import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/image_generation_settings_page.dart';
import 'package:poemath/features/profile/widgets/llm_provider_edit_dialog.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _Store extends SecureCredentialStore {
  final keys = <String, String>{};
  @override
  Future<String?> readImageGenerationApiKeyFor(String id) async => keys[id];
  @override
  Future<void> saveImageGenerationApiKeyFor(String id, String key) async {
    keys[id] = key;
  }

  @override
  Future<void> deleteImageGenerationApiKeyFor(String id) async {
    keys.remove(id);
  }
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

Future<void> _settle(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  }
  expect(condition(), isTrue);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

void main() {
  late _Store store;
  late SettingsRepository settings;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    store = _Store();
    settings = SettingsRepository(credentialStore: store);
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForWidgetTesting();
  });

  Future<void> mount(
    WidgetTester tester, {
    http.Client? client,
    Size size = const Size(420, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureCredentialStoreProvider.overrideWithValue(store),
          llmSettingsHttpClientProvider.overrideWithValue(
            client ?? MockClient((_) async => http.Response('{}', 200)),
          ),
        ],
        child: MaterialApp(
          home: const ImageGenerationSettingsPage(),
          builder: (context, child) => PageAnimationScope(
            enabled: false,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await _settle(tester, () => find.text('新增配置').evaluate().isNotEmpty);
  }

  Future<void> seed() async {
    await settings.saveImageGenerationProviderConfig(
      id: 'a',
      name: '生图 A',
      baseUrl: 'https://image.example.com/v1',
      model: 'image-a',
      apiKey: 'image-key-a',
    );
    await settings.saveImageGenerationProviderConfig(
      id: 'b',
      name: '',
      baseUrl: 'https://other.example.com/v1',
      model: 'image-b',
      apiKey: 'image-key-b',
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  }

  testWidgets('生图采用供应商列表与同一新增弹窗，保存配置不会自动生图', (tester) async {
    var requests = 0;
    await mount(
      tester,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    expect(find.text('我的配置'), findsOneWidget);
    expect(find.textContaining('还没有生图配置'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await _tap(tester, find.text('新增配置'));
    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(_field('供应商名称（可选）'), '新的生图服务');
    await tester.enterText(
      _field('服务地址（Base URL）'),
      'https://new.example.com/v1',
    );
    await tester.enterText(_field('API Key（可选）'), 'new-private-key');
    await tester.enterText(_field('默认模型'), 'new-image');
    await _tap(tester, find.text('保存配置'));
    await _settle(tester, () => settings.imageGenerationProviders.length == 1);
    expect(settings.imageGenerationProviders.single.name, '新的生图服务');
    expect(store.keys.values, ['new-private-key']);
    expect(settings.llmProviders, isEmpty);
    expect(requests, 0);
    expect(CloudUsageService().used(CloudUsageKind.imageGeneration), 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('模型拉取多选、候选设默认及留空保留密钥与普通供应商一致', (tester) async {
    await tester.runAsync(seed);
    final requests = <http.Request>[];
    await mount(
      tester,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'image-a'},
              {'id': 'image-c'},
            ],
          }),
          200,
        );
      }),
    );
    await _tap(tester, find.byTooltip('编辑此配置').first);
    await _settle(
      tester,
      () => tester
          .widget<TextField>(_field('API Key（可选）'))
          .controller!
          .text
          .isNotEmpty,
    );
    await tester.enterText(_field('API Key（可选）'), '');
    await tester.enterText(
      _field('服务地址（Base URL）'),
      'https://image.example.com/v1/images/generations',
    );
    await _tap(tester, find.byTooltip('从服务拉取模型列表（可多选）'));
    await _settle(tester, () => find.text('选择模型（可多选）').evaluate().isNotEmpty);
    await _tap(tester, find.text('image-c'));
    await _tap(tester, find.text('加入 2 个模型'));
    await _tap(tester, find.widgetWithText(InputChip, 'image-c'));
    await _tap(tester, find.text('保存配置'));
    await _settle(
      tester,
      () => settings.imageGenerationProviders.first.model == 'image-c',
    );
    expect(
      settings.imageGenerationProviders.first.models,
      ['image-c', 'image-a'],
    );
    expect(store.keys['a'], 'image-key-a');
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/v1/models');
    expect(requests.single.headers['Authorization'], 'Bearer image-key-a');
    expect(CloudUsageService().used(CloudUsageKind.imageGeneration), 0);
    expect(CloudUsageService().used(CloudUsageKind.llm), 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('点行切换生图配置，编辑删除当前配置后回落且只清理其密钥', (tester) async {
    await tester.runAsync(seed);
    await mount(tester);
    await _tap(tester, find.text('配置 2'));
    await _settle(
      tester,
      () => settings.imageGenerationActiveProviderId == 'b',
    );
    await _tap(tester, find.byTooltip('编辑此配置').last);
    await _tap(tester, find.text('删除此配置'));
    await _tap(tester, find.text('删除'));
    await _settle(tester, () => settings.imageGenerationProviders.length == 1);
    expect(settings.imageGenerationActiveProviderId, 'a');
    expect(store.keys, {'a': 'image-key-a'});
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('连接测试验证真实生图端点和可解码图片，展示预览且不写题库', (tester) async {
    await tester.runAsync(seed);
    final png = (await tester.runAsync(() => pictureStoryPng()))!;
    final requests = <http.Request>[];
    await mount(
      tester,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(png)},
            ],
          }),
          200,
        );
      }),
    );
    await _tap(tester, find.byTooltip('编辑此配置').first);
    await _settle(
      tester,
      () => tester
          .widget<TextField>(_field('API Key（可选）'))
          .controller!
          .text
          .isNotEmpty,
    );
    expect(tester.widget<TextField>(_field('API Key（可选）')).obscureText, isTrue);
    await _tap(tester, find.byTooltip('显示 API Key'));
    expect(
      tester.widget<TextField>(_field('API Key（可选）')).obscureText,
      isFalse,
    );
    await _tap(tester, find.text('测试连接'));
    await _settle(
      tester,
      () => find
          .byKey(
            const ValueKey('image-generation-test-preview'),
          )
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('连接成功，生图模型可用'), findsOneWidget);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/v1/images/generations');
    expect(jsonDecode(requests.single.body)['model'], 'image-a');
    expect(requests.single.headers['Authorization'], 'Bearer image-key-a');
    expect(CloudUsageService().used(CloudUsageKind.imageGeneration), 1);
    expect(CloudUsageService().used(CloudUsageKind.llm), 0);
    expect(PictureStoryRepository().catalogState().versions, isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('服务只返回坏图片时不能显示连接成功', (tester) async {
    await tester.runAsync(seed);
    await mount(
      tester,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(utf8.encode('not an image'))},
            ],
          }),
          200,
        ),
      ),
    );
    await _tap(tester, find.byTooltip('编辑此配置').first);
    await _tap(tester, find.text('测试连接'));
    await _settle(
      tester,
      () => find.text('服务没有返回可以读取的图片').evaluate().isNotEmpty,
    );
    expect(find.text('连接成功，生图模型可用'), findsNothing);
    expect(
      find.byKey(const ValueKey('image-generation-test-preview')),
      findsNothing,
    );
    expect(CloudUsageService().used(CloudUsageKind.imageGeneration), 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('小屏大字号的配置列表和全屏弹窗不溢出', (tester) async {
    await mount(tester, size: const Size(320, 900), scale: 2);
    await _tap(tester, find.text('新增配置'));
    await tester.ensureVisible(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
