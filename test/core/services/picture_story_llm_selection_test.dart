import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _Secrets extends SecureCredentialStore {
  final keys = <String, String>{};
  @override
  Future<String?> readLlmApiKeyFor(String id) async => keys[id];
  @override
  Future<void> saveLlmApiKeyFor(String id, String key) async => keys[id] = key;
}

class _DelayedSelectionBox extends Fake implements Box<dynamic> {
  _DelayedSelectionBox(this.delegate);
  final Box<dynamic> delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  bool containsKey(dynamic key) => delegate.containsKey(key);
  @override
  Future<void> put(dynamic key, dynamic value) => delegate.put(key, value);
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    await delegate.putAll(entries);
    entered.complete();
    await release.future;
  }
}

String _event(Object value) => 'data: ${jsonEncode(value)}\n\n';
http.Response _completion(Object value, {required bool streaming}) =>
    http.Response.bytes(
      utf8.encode(
        streaming
            ? '${_event({
                    'choices': [
                      {
                        'delta': {'content': jsonEncode(value)},
                      },
                    ],
                  })}'
                  'data: [DONE]\n\n'
            : jsonEncode({
                'choices': [
                  {
                    'message': {'content': jsonEncode(value)},
                    'finish_reason': 'stop',
                  },
                ],
              }),
      ),
      200,
      headers: {
        'content-type': streaming
            ? 'text/event-stream; charset=utf-8'
            : 'application/json; charset=utf-8',
      },
    );

const _image = ImageGenerationConfig(
  provider: ImageGenerationProviderConfig(
    name: '测试图片',
    baseUrl: 'https://image.example.com/v1',
    model: 'test-image',
  ),
  apiKey: 'synthetic-image-key',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Uint8List png;
  late PictureStoryImageService images;
  late PictureStoryRepository repository;
  late SettingsRepository settings;
  late _Secrets secrets;
  late ProviderContainer container;
  late http.Client transport;
  late PictureStoryGenerationService service;
  // 同模型的 SSE 与普通 JSON 是不同尝试，必须一起核对模式和回退顺序。
  final requests = <(String, String, String, bool)>[];
  var imageRequests = 0;
  var changeCaptionModel = false;
  var invalidPlan = false;
  var invalidCaption = false;
  var invalidFirstCaption = false;
  var singleQuestion = false;
  var goodProviderRequiresNonStreaming = false;
  var primaryHttpFailure = false;
  Future<void> Function()? beforeGoodPlan;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp(
      'picture_story_selection_',
    );
    png = await pictureStoryPng();
    images = PictureStoryImageService(directoryProvider: () async => directory);
    repository = PictureStoryRepository(images: images);
    secrets = _Secrets();
    settings = SettingsRepository(credentialStore: secrets);
    for (final (id, host, model, models) in [
      ('p1', 'bad.example.com', 'gpt-4o-bad', ['gpt-4o-bad']),
      ('p2', 'good.example.com', 'gpt-4o-mini', ['gpt-4o-mini', 'gpt-4o']),
    ]) {
      await settings.saveLlmProviderConfig(
        id: id,
        name: id,
        baseUrl: 'https://$host/v1',
        model: model,
        models: models,
        apiKey: 'synthetic-key-$id',
      );
    }
    requests.clear();
    imageRequests = 0;
    changeCaptionModel = false;
    invalidPlan = false;
    invalidCaption = false;
    invalidFirstCaption = false;
    singleQuestion = false;
    goodProviderRequiresNonStreaming = false;
    primaryHttpFailure = false;
    beforeGoodPlan = null;
    transport = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final content = (body['messages'] as List).last['content'];
      final planning = content is String;
      final model = body['model'] as String;
      final streaming = body['stream'] == true;
      requests.add((
        request.url.host,
        model,
        planning ? 'plan' : 'caption',
        streaming,
      ));
      if (request.url.host == 'bad.example.com') {
        expect(request.headers['Authorization'], 'Bearer synthetic-key-p1');
        expect(settings.llmActiveProviderId, 'p1');
        expect(container.read(llmSelectionVersionProvider), 0);
        if (primaryHttpFailure) return http.Response('', 503);
        if (!streaming) {
          // 普通模式同样失败，才应切换到下一供应商。
          return http.Response(
            jsonEncode({
              'error': {'message': 'synthetic-key-p1 provider-private-detail'},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        // 即使片段已是有效规划，后续服务错误也不能确认此模型成功。
        return http.Response.bytes(
          utf8.encode(
            '${_event({
              'choices': [
                {
                  'delta': {'content': '[{"imagePrompt":"失败模型的场景"}]'},
                },
              ],
            })}'
            '${_event({
              'error': {'message': 'synthetic-key-p1 provider-private-detail'},
            })}'
            'data: [DONE]\n\n',
          ),
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      }
      expect(request.headers['Authorization'], 'Bearer synthetic-key-p2');
      if (goodProviderRequiresNonStreaming && streaming) {
        return http.Response(
          _event({
            'error': {'type': 'server_error'},
          }),
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      }
      if (planning) {
        await beforeGoodPlan?.call();
        return _completion(
          invalidPlan
              ? []
              : [
                  {'imagePrompt': '小朋友在雨中分享雨伞。'},
                  {'imagePrompt': '小朋友在教室帮同学捡起书本。'},
                ],
          streaming: streaming,
        );
      }
      if (changeCaptionModel && model == 'gpt-4o-mini') {
        return http.Response('', 503);
      }
      return _completion(
        (invalidCaption || (invalidFirstCaption && model == 'gpt-4o-mini'))
            ? {'title': '不完整题目'}
            : {
                'title': '雨中互助',
                'questions': ['小朋友正在做什么？'],
              },
        streaming: streaming,
      );
    });
    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        llmExplainHttpClientProvider.overrideWithValue(transport),
        pictureStoryImageServiceProvider.overrideWithValue(images),
        pictureStoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    service = PictureStoryGenerationService(
      images: images,
      repository: repository,
      llmFactory: (active) => createRuntimeLlmClient(
        httpClient: transport,
        settings: settings,
        isActive: active,
        onSelectionChanged: () =>
            container.read(llmSelectionVersionProvider.notifier).state++,
      ),
      imageFactory: (active) => ImageGenerationClient(
        isActive: active,
        httpClient: MockClient((request) async {
          imageRequests++;
          // 多题先保存规划成功模型；单题生图前不调用或回写大模型。
          expect(
            settings.providerIdForScenario(LlmScenario.pictureStory) ??
                settings.llmActiveProviderId,
            singleQuestion ? 'p1' : 'p2',
          );
          return http.Response(
            jsonEncode({
              'data': [
                {'b64_json': base64Encode(png)},
              ],
            }),
            200,
          );
        }),
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    transport.close();
    lockParentForTesting();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  Future<PictureStoryGenerationDraft> generate() async {
    var signature = settings.pictureStoryGenerationSignature;
    final config = (await settings.readLlmConfigForScenario(
      LlmScenario.pictureStory,
    ))!;
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: singleQuestion ? 1 : 2,
        themes: ['友爱互助'],
      ),
    );
    await service.run(
      draft: draft,
      config: config,
      imageConfig: _image,
      isActive: () => signature == settings.pictureStoryGenerationSignature,
      onLlmSelectionSaved: (saved) => signature = saved,
    );
    return service.readDraft('default')!;
  }

  test('单题先生图再执行视觉模型回退，只在有效题目完成后回写成功模型', () async {
    singleQuestion = true;
    changeCaptionModel = true;
    final draft = await generate();
    expect(draft.readyCount, 1);
    expect(requests, [
      ('bad.example.com', 'gpt-4o-bad', 'caption', true),
      ('bad.example.com', 'gpt-4o-bad', 'caption', false),
      ('good.example.com', 'gpt-4o-mini', 'caption', true),
      ('good.example.com', 'gpt-4o', 'caption', true),
    ]);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 4);
    expect(imageRequests, 1);
    expect(settings.llmActiveProviderId, 'p2');
    expect(settings.llmProviders.last.model, 'gpt-4o');
    expect(container.read(llmSelectionVersionProvider), 1);
    expect(draft.candidates.single.edit.toPrompt().questions, ['小朋友正在做什么？']);
    expect(repository.catalogState().versions, isEmpty);
  });

  for (final explicit in [false, true]) {
    test('看图出题${explicit ? '显式场景' : '跟随默认'}回写两次成功选择，下次直接使用最终模型', () async {
      if (explicit) {
        await settings.setScenarioSelection(
          LlmScenario.pictureStory,
          providerId: 'p1',
          model: 'gpt-4o-bad',
        );
      }
      await settings.setScenarioSelection(
        LlmScenario.mathExplain,
        providerId: 'p1',
        model: 'gpt-4o-bad',
      );
      changeCaptionModel = true;
      final draft = await generate();
      expect(draft.readyCount, 2);
      expect(requests, [
        ('bad.example.com', 'gpt-4o-bad', 'plan', true),
        ('bad.example.com', 'gpt-4o-bad', 'plan', false),
        ('good.example.com', 'gpt-4o-mini', 'plan', true),
        ('good.example.com', 'gpt-4o-mini', 'caption', true),
        ('good.example.com', 'gpt-4o', 'caption', true),
        ('good.example.com', 'gpt-4o', 'caption', true),
      ]);
      expect(CloudUsageService.instance.used(CloudUsageKind.llm), 6);
      expect(settings.llmActiveProviderId, explicit ? 'p1' : 'p2');
      expect(
        settings.providerIdForScenario(LlmScenario.pictureStory),
        explicit ? 'p2' : null,
      );
      expect(
        settings.modelForScenario(LlmScenario.pictureStory),
        explicit ? 'gpt-4o' : null,
      );
      expect(settings.llmProviders.last.model, 'gpt-4o');
      expect(settings.providerIdForScenario(LlmScenario.mathExplain), 'p1');
      expect(settings.modelForScenario(LlmScenario.mathExplain), 'gpt-4o-bad');
      expect(container.read(llmSelectionVersionProvider), 2);
      expect(imageRequests, 2);
      await service.discardDraft(draft);
      await HiveBoxes.close();
      await HiveBoxes.init();
      requests.clear();
      final next = await generate();
      expect(next.readyCount, 2);
      expect(requests, [
        ('good.example.com', 'gpt-4o', 'plan', true),
        ('good.example.com', 'gpt-4o', 'caption', true),
        ('good.example.com', 'gpt-4o', 'caption', true),
      ]);
      expect(container.read(llmSelectionVersionProvider), 2);
    });
  }

  test('备用模型普通响应恢复后回写成功选择，同批看图沿用普通模式', () async {
    goodProviderRequiresNonStreaming = true;
    final draft = await generate();
    expect(draft.readyCount, 2);
    expect(requests, [
      ('bad.example.com', 'gpt-4o-bad', 'plan', true),
      ('bad.example.com', 'gpt-4o-bad', 'plan', false),
      ('good.example.com', 'gpt-4o-mini', 'plan', true),
      ('good.example.com', 'gpt-4o-mini', 'plan', false),
      ('good.example.com', 'gpt-4o-mini', 'caption', false),
      ('good.example.com', 'gpt-4o-mini', 'caption', false),
    ]);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 6);
    expect(imageRequests, 2);
    expect(settings.llmActiveProviderId, 'p2');
    expect(settings.llmProviders.last.model, 'gpt-4o-mini');
    expect(container.read(llmSelectionVersionProvider), 1);
    for (final candidate in draft.candidates) {
      expect(candidate.edit.toPrompt().questions, ['小朋友正在做什么？']);
    }
    expect(repository.catalogState().versions, isEmpty);
  });

  test('HTTP 服务失败直接切换供应商，不触发普通响应兼容重试', () async {
    singleQuestion = true;
    primaryHttpFailure = true;
    final draft = await generate();
    expect(draft.readyCount, 1);
    expect(requests, [
      ('bad.example.com', 'gpt-4o-bad', 'caption', true),
      ('good.example.com', 'gpt-4o-mini', 'caption', true),
    ]);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 2);
    expect(imageRequests, 1);
    expect(settings.llmActiveProviderId, 'p2');
    expect(settings.llmProviders.last.model, 'gpt-4o-mini');
    expect(container.read(llmSelectionVersionProvider), 1);
    expect(repository.catalogState().versions, isEmpty);
  });

  test('生产 Provider 接线在规划成功后立即回写，后续生图失败仍保留成功模型', () async {
    // 阻止实际图片 HTTP，但保留生产服务与其大模型工厂的真实接线。
    await CloudUsageService.instance.setLimit(
      CloudUsageKind.imageGeneration,
      0,
    );
    service = container.read(pictureStoryGenerationServiceProvider);
    final draft = await generate();
    expect(draft.candidates.first.stage, PictureStoryGenerationStage.failed);
    expect(settings.llmActiveProviderId, 'p2');
    expect(settings.llmProviders.last.model, 'gpt-4o-mini');
    expect(container.read(llmSelectionVersionProvider), 1);
    expect(requests, [
      ('bad.example.com', 'gpt-4o-bad', 'plan', true),
      ('bad.example.com', 'gpt-4o-bad', 'plan', false),
      ('good.example.com', 'gpt-4o-mini', 'plan', true),
    ]);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 3);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 0);
  });

  test('场景数量未通过校验不回写模型，也不发出图片请求', () async {
    invalidPlan = true;
    await expectLater(generate(), throwsA(isA<LlmResponseFormatError>()));
    expect(settings.llmActiveProviderId, 'p1');
    expect(settings.llmProviders.last.model, 'gpt-4o-mini');
    expect(container.read(llmSelectionVersionProvider), 0);
    expect(imageRequests, 0);
  });

  test('完整流中的题目结构无效也会回退，同一图片只生成一次且不回写坏模型', () async {
    singleQuestion = true;
    invalidFirstCaption = true;
    final draft = await generate();
    expect(draft.readyCount, 1);
    expect(requests, [
      ('bad.example.com', 'gpt-4o-bad', 'caption', true),
      ('bad.example.com', 'gpt-4o-bad', 'caption', false),
      ('good.example.com', 'gpt-4o-mini', 'caption', true),
      ('good.example.com', 'gpt-4o', 'caption', true),
    ]);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 4);
    expect(imageRequests, 1);
    expect(settings.llmActiveProviderId, 'p2');
    expect(settings.llmProviders.last.model, 'gpt-4o');
    expect(container.read(llmSelectionVersionProvider), 1);
    expect(repository.catalogState().versions, isEmpty);
  });

  test('看图内容未通过校验不覆盖之前已确认的场景规划模型', () async {
    changeCaptionModel = true;
    invalidCaption = true;
    final draft = await generate();
    expect(draft.candidates.first.stage, PictureStoryGenerationStage.failed);
    expect(draft.candidates.first.edit.image, isNotNull);
    expect(settings.llmActiveProviderId, 'p2');
    expect(settings.llmProviders.last.model, 'gpt-4o-mini');
    expect(container.read(llmSelectionVersionProvider), 1);
  });

  test('规划响应返回前发生手动设置变更，不回写迟到的成功模型', () async {
    beforeGoodPlan = () => settings.setScenarioSelection(
      LlmScenario.pictureStory,
      providerId: 'p1',
      model: 'gpt-4o-bad',
    );
    await expectLater(generate(), throwsA(isA<LlmGenerationCancelled>()));
    expect(settings.llmActiveProviderId, 'p1');
    expect(settings.providerIdForScenario(LlmScenario.pictureStory), 'p1');
    expect(settings.modelForScenario(LlmScenario.pictureStory), 'gpt-4o-bad');
    expect(container.read(llmSelectionVersionProvider), 0);
    expect(imageRequests, 0);
  });

  test('自动回写落盘期间修改提示词，不会把并发变更当成自动回写继续生图', () async {
    final original = HiveBoxes.settings;
    final delayed = _DelayedSelectionBox(original);
    // 草稿先落盘，再只延迟自动选择的 putAll。
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: 2,
        themes: ['友爱互助'],
      ),
    );
    var signature = settings.pictureStoryGenerationSignature;
    final config = (await settings.readLlmConfigForScenario(
      LlmScenario.pictureStory,
    ))!;
    HiveBoxes.settings = delayed;
    try {
      final running = service.run(
        draft: draft,
        config: config,
        imageConfig: _image,
        isActive: () => signature == settings.pictureStoryGenerationSignature,
        onLlmSelectionSaved: (saved) => signature = saved,
      );
      final stopped = expectLater(
        running,
        throwsA(isA<LlmGenerationCancelled>()),
      );
      await delayed.entered.future.timeout(const Duration(seconds: 5));
      await original.put('llm_picture_story_image_prompt', '手动修改后的画面要求');
      delayed.release.complete();
      await stopped;
      expect(settings.pictureStoryImageGenerationPromptOverride, '手动修改后的画面要求');
      expect(imageRequests, 0);
      expect(service.readDraft('default')!.candidates, isEmpty);
    } finally {
      if (!delayed.release.isCompleted) delayed.release.complete();
      HiveBoxes.settings = original;
    }
  });
}
