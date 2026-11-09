import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/prompts/generation_prompt_defaults.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

const _llm = LlmConfig(
  baseUrl: 'https://llm.example.com',
  apiKey: 'test-text-key',
  model: 'gpt-4o-mini',
);
const _imageProvider = ImageGenerationProviderConfig(
  name: '配图',
  baseUrl: 'https://image.example.com/v1',
  model: 'image-model',
);
const _imageConfig = ImageGenerationConfig(
  provider: _imageProvider,
  apiKey: 'test-image-key',
);

http.Response _completion(
  Object content, {
  bool sse = false,
  bool complete = true,
}) {
  final text = content is String ? content : jsonEncode(content);
  if (sse) {
    final midpoint = text.length ~/ 2;
    final events = [
      for (final part in [
        text.substring(0, midpoint),
        text.substring(midpoint),
      ])
        'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': part},
                },
              ],
            })}\n\n',
      if (complete) 'data: [DONE]\n\n',
    ];
    return http.Response.bytes(
      utf8.encode(events.join()),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
  return http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': text},
          },
        ],
      }),
    ),
    200,
  );
}

class _ImageSecrets extends SecureCredentialStore {
  String? key;
  bool failNextWrite = false;
  @override
  Future<String?> readImageGenerationApiKey() async => key;
  @override
  Future<void> saveImageGenerationApiKey(String apiKey) async {
    key = apiKey;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('synthetic write failure');
    }
  }

  @override
  Future<void> deleteImageGenerationApiKey() async {
    key = null;
  }
}

class _PartialWriteBox extends Fake implements Box<dynamic> {
  _PartialWriteBox(this.delegate);
  final Box<dynamic> delegate;
  bool failNext = true;
  @override
  Iterable<dynamic> get keys => delegate.keys;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  bool containsKey(dynamic key) => delegate.containsKey(key);
  @override
  Future<void> delete(dynamic key) => delegate.delete(key);
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    if (failNext && entries.isNotEmpty) {
      failNext = false;
      await delegate.put(entries.keys.first, entries.values.first);
      throw StateError('第二个键写入失败');
    }
    await delegate.putAll(entries);
  }
}

class _BudgetImages extends PictureStoryImageService {
  int reads = 0;
  @override
  Future<void> ensureStored(PictureStoryImage image) async {}
  @override
  Future<int> storedImageSize(String id) async =>
      PictureStoryImageService.maxStoredBytes;
  @override
  Future<Uint8List> readImage(String id) async {
    reads++;
    throw StateError('预算拒绝前不应读取题图');
  }
}

class _PausedGeneratedImages extends PictureStoryImageService {
  _PausedGeneratedImages({required super.directoryProvider});
  final stored = Completer<void>();
  final proceed = Completer<void>();

  @override
  Future<PictureStoryImage> importBytes(Uint8List bytes) async {
    final result = await super.importBytes(bytes);
    stored.complete();
    await proceed.future;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PictureStoryImageService images;
  late Uint8List png;
  late PictureStoryRepository repository;
  late PictureStoryGenerationService service;
  var planCalls = 0;
  var captionCalls = 0;
  var imageCalls = 0;
  var imageClients = 0;
  var failCaption = 0;
  var incompleteSsePlans = false;
  var incompleteSseCaptions = false;
  int? captionStatus;
  String? captionLimitNotice;
  String? plannedImagePrompt;
  final planningResponses = <Object>[];
  final captionRequests = <Map<String, dynamic>>[];
  final planRequests = <Map<String, dynamic>>[];
  final imageRequests = <Map<String, dynamic>>[];
  final requestOrder = <String>[];

  PictureStoryGenerationService createService({
    PictureStoryImageService? imageService,
    bool sse = false,
  }) =>
      PictureStoryGenerationService(
        images: imageService ?? images,
        repository: repository,
        backup: BackupService(
          pictureStoryImages: imageService ?? images,
          pictureStoryRepository: repository,
        ),
        llmFactory: (active) => LlmClient(
          isActive: active,
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final messages = body['messages'] as List<dynamic>;
            final content = (messages.last as Map<String, dynamic>)['content'];
            if (content is String) {
              planRequests.add(body);
              planCalls++;
              requestOrder.add('规划');
              final saved = service.readDraft('default')!;
              if (planningResponses.isNotEmpty) {
                return _completion(planningResponses.removeAt(0), sse: sse);
              }
              return _completion([
                for (var i = 0; i < saved.options.count; i++)
                  {'imagePrompt': plannedImagePrompt ?? '场景 $i：公园里的孩子观察花朵。'},
              ], sse: sse, complete: !incompleteSsePlans);
            }
            captionCalls++;
            requestOrder.add('看图 $captionCalls');
            captionRequests.add(body);
            if (captionStatus != null) {
              return http.Response('private provider response', captionStatus!);
            }
            if (captionLimitNotice != null) {
              return _completion(captionLimitNotice!, sse: sse);
            }
            if (captionCalls == failCaption) {
              return _completion({'title': '不完整内容'}, sse: sse);
            }
            return _completion(
              {
                'title': '观察花朵 $captionCalls',
                'theme': '',
                'sceneFacts': ['孩子在看花朵'],
                'questions': ['你看到了什么？', '想象孩子接下来会做什么？'],
                'goals': <String>[],
                'reference': '',
              },
              sse: sse,
              complete: !incompleteSseCaptions,
            );
          }),
        ),
        imageFactory: (active) {
          imageClients++;
          return ImageGenerationClient(
            isActive: active,
            httpClient: MockClient((request) async {
              imageRequests
                  .add(jsonDecode(request.body) as Map<String, dynamic>);
              imageCalls++;
              requestOrder.add('生图 $imageCalls');
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
        },
      );

  Future<PictureStoryGenerationDraft> start({
    int count = 3,
    LlmConfig config = _llm,
    String? imagePromptOverride,
    String? questionPromptOverride,
  }) async {
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.growing,
        count: count,
        themes: ['自然观察', '友爱互助'],
      ),
    );
    await service.run(
      draft: draft,
      config: config,
      imageConfig: _imageConfig,
      isActive: () => true,
      imagePromptOverride: imagePromptOverride,
      questionPromptOverride: questionPromptOverride,
    );
    return service.readDraft('default')!;
  }

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp(
      'picture_story_generation_',
    );
    png = await pictureStoryPng(width: 640, height: 480);
    images = PictureStoryImageService(directoryProvider: () async => directory);
    repository = PictureStoryRepository(images: images);
    planCalls = 0;
    captionCalls = 0;
    imageCalls = 0;
    imageClients = 0;
    failCaption = 0;
    incompleteSsePlans = false;
    incompleteSseCaptions = false;
    captionStatus = null;
    captionLimitNotice = null;
    plannedImagePrompt = null;
    planningResponses.clear();
    captionRequests.clear();
    planRequests.clear();
    imageRequests.clear();
    requestOrder.clear();
    service = createService();
  });
  tearDown(() async {
    service.pause('default');
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  test('AI 图片落盘到生成草稿保存之间阻止删除，随后删除不影响候选题图和看图出题', () async {
    final oldImage = await images.importBytes(await pictureStoryPng());
    final prompt = await repository.savePrompt(
      prompt: pictureStoryFixture(image: oldImage),
      profileId: 'default',
    );
    final paused = _PausedGeneratedImages(
      directoryProvider: () async => directory,
    );
    service = createService(imageService: paused);
    final generating = start(count: 1);
    await paused.stored.future;
    final before = repository.storageSnapshot();
    await expectLater(
      repository.deletePrompt(prompt: prompt, profileId: 'default'),
      throwsA(isA<CacheInUseException>()),
    );
    expect(repository.storageSnapshot(), before);
    paused.proceed.complete();
    final draft = await generating;
    final generatedImage = draft.candidates.single.edit.image!;
    await repository.deletePrompt(prompt: prompt, profileId: 'default');
    expect(await images.imagePath(oldImage.value), isNull);
    expect(await images.readImage(generatedImage.value), isNotEmpty);
    expect(service.readDraft('default')!.candidates.single.isReady, isTrue);
    expect(captionCalls, 1);
  });

  test('单题直接按原要求生图，只消耗一次看图请求，检查点及图片完整保留', () async {
    service = createService(sse: true);
    final options = PictureStoryGenerationOptions(
      level: PictureStoryLevel.growing,
      count: 1,
      themes: PictureStoryGenerationOptions.availableThemes,
      requirements: '补' * 1000,
    );
    final draft = await service.createDraft(options);
    await service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
      imagePromptOverride: '图' * kPictureStoryImagePromptMaxLength,
      questionPromptOverride: '从画面中的动作提问',
      onPlanningAttempt: (_) => fail('单题不应请求场景规划'),
    );
    final saved = service.readDraft('default')!;
    expect(saved.readyCount, 1);
    expect(saved.options.toJson(), options.toJson());
    expect(requestOrder, ['生图 1', '看图 1']);
    expect(planCalls, 0);
    final prompt = imageRequests.single['prompt'] as String;
    expect(prompt, startsWith('图' * kPictureStoryImagePromptMaxLength));
    expect(prompt, contains('主题：${options.themes.join('、')}'));
    expect(prompt, contains('难度：${options.level.label}'));
    expect(prompt, endsWith(options.requirements));
    expect(prompt.runes.length, lessThanOrEqualTo(4000));
    final candidate = saved.candidates.single;
    expect(prompt, endsWith(candidate.imagePrompt));
    final messages = captionRequests.single['messages'] as List;
    expect(messages.first['content'], startsWith('从画面中的动作提问'));
    final parts = messages.last['content'] as List;
    final url = parts.last['image_url']['url'] as String;
    expect(
      base64Decode(url.split(',').last),
      await images.readForVision(candidate.edit.image!.value),
    );
    expect(jsonEncode(messages), isNot(contains(options.requirements)));
    expect(candidate.edit.toPrompt().questions, ['你看到了什么？', '想象孩子接下来会做什么？']);
    expect(repository.catalogState().versions, isEmpty);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 1);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 1);
  });

  test('SSE 规划与逐题看图出题保留完整题图、内容和生成顺序', () async {
    service = createService(sse: true);
    final draft = await start(count: 2);
    expect(requestOrder, ['规划', '生图 1', '看图 1', '生图 2', '看图 2']);
    expect(draft.readyCount, 2);
    expect(draft.candidates.map((c) => c.edit.toPrompt().title), [
      '观察花朵 1',
      '观察花朵 2',
    ]);
    expect(planRequests.single['stream'], isTrue);
    for (final (index, request) in captionRequests.indexed) {
      expect(request['stream'], isTrue);
      final candidate = draft.candidates[index];
      expect(candidate.edit.toPrompt().questions, ['你看到了什么？', '想象孩子接下来会做什么？']);
      final parts =
          ((request['messages'] as List).last as Map)['content'] as List;
      final url = ((parts.last as Map)['image_url'] as Map)['url'] as String;
      expect(
        base64Decode(url.split(',').last),
        await images.readForVision(candidate.edit.image!.value),
      );
    }
    expect(service.readDraft('default')!.encode(), draft.encode());
    expect(repository.catalogState().versions, isEmpty);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 3);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 2);
  });

  test('SSE 中断即使 JSON 已闭合也不入库，重试复用原图只发看图请求', () async {
    service = createService(sse: true);
    incompleteSseCaptions = true;
    var draft = await start(count: 1);
    final failed = draft.candidates.single;
    final image = failed.edit.image!;
    final stored = await images.readImage(image.value);
    expect(failed.stage, PictureStoryGenerationStage.failed);
    expect(failed.error, '看图出题内容不完整或格式不正确，可保留图片重试');
    expect(draft.readyCount, 0);
    expect(failed.edit.fields[PictureStoryEditorField.title], '');
    expect(repository.catalogState().versions, isEmpty);

    incompleteSseCaptions = false;
    await service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
      candidateId: failed.id,
      reuseImageId: image.value,
    );
    draft = service.readDraft('default')!;
    expect(draft.readyCount, 1);
    expect(draft.candidates.single.id, failed.id);
    expect(draft.candidates.single.edit.image, image);
    expect(draft.candidates.single.edit.toPrompt().title, '观察花朵 2');
    expect(await images.readImage(image.value), stored);
    expect(requestOrder, ['生图 1', '看图 1', '看图 2']);
    expect(planCalls, 0);
    expect(imageCalls, 1);
    expect(imageClients, 1);
    expect(captionCalls, 2);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 2);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 1);
    expect(repository.catalogState().versions, isEmpty);
  });

  test('生图与看图出题自定义提示词分别进入真实 SSE 请求，保留各阶段约束', () async {
    service = createService(sse: true);
    final draft = await start(
      count: 2,
      imagePromptOverride: '  用水彩描绘孩子互助的小事  ',
      questionPromptOverride: '  先观察画面，再用短句表达  ',
    );
    expect(planCalls, 1);
    expect(imageCalls, 2);
    expect(captionCalls, 2);
    expect(draft.readyCount, 2);
    final planning =
        (planRequests.single['messages'] as List).first['content'] as String;
    expect(planning, startsWith('用水彩描绘孩子互助的小事\n\n'));
    expect(planning, isNot(contains('先观察画面，再用短句表达')));
    expect(planning, contains('只输出严格 JSON 数组'));
    expect(planning, contains('imagePrompt'));
    expect(planning, contains('不要先编题目或答案'));
    expect(planning, contains('不拼图、不分镜'));
    expect(imageRequests, hasLength(2));
    for (final request in imageRequests) {
      expect(request['prompt'], startsWith('用水彩描绘孩子互助的小事\n\n'));
      expect(request['prompt'], contains('具体场景：\n场景'));
      expect(request['prompt'], isNot(contains('先观察画面，再用短句表达')));
      expect(request['prompt'], isNot(contains('平面手绘儿童教材插图')));
    }
    for (final request in captionRequests) {
      final messages = request['messages'] as List;
      final prompt = messages.first['content'] as String;
      expect(prompt, startsWith('先观察画面，再用短句表达\n\n'));
      expect(prompt, isNot(contains('用水彩描绘孩子互助的小事')));
      expect(prompt, contains('只输出严格 JSON 对象'));
      expect(prompt, contains('只依据实际图片'));
      expect(prompt, contains('不要编造图中看不到'));
      expect(messages.last['content'], isA<List<Object?>>());
    }
    expect(repository.catalogState().versions, isEmpty);
  });

  test('生图提示词和规划场景均达长度上限时仍可实际请求，出题提示独立生效', () async {
    plannedImagePrompt = '场' * kPictureStorySceneDescriptionMaxLength;
    planningResponses.add([
      {'imagePrompt': plannedImagePrompt},
      {'imagePrompt': '景' * kPictureStorySceneDescriptionMaxLength},
    ]);
    final draft = await start(
      count: 2,
      imagePromptOverride: '图' * kPictureStoryImagePromptMaxLength,
      questionPromptOverride: '题' * kPictureStoryQuestionPromptMaxLength,
    );
    expect(draft.readyCount, 2);
    expect(requestOrder, ['规划', '生图 1', '看图 1', '生图 2', '看图 2']);
    final prompt = imageRequests.first['prompt'] as String;
    expect(prompt.runes.length, lessThanOrEqualTo(4000));
    expect(prompt, endsWith(plannedImagePrompt!));
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 2);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 3);
  });

  test('生图提示词超长在规划及计费请求前拒绝，保留草稿', () async {
    await expectLater(
      start(imagePromptOverride: '图' * (kPictureStoryImagePromptMaxLength + 1)),
      throwsA(isA<ImageGenerationException>()),
    );
    expect(requestOrder, isEmpty);
    expect(imageClients, 0);
    expect(service.readDraft('default')!.candidates, isEmpty);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 0);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 0);
  });

  test('看图出题提示词超长在规划及计费请求前拒绝，保留草稿', () async {
    await expectLater(
      start(
        questionPromptOverride:
            '题' * (kPictureStoryQuestionPromptMaxLength + 1),
      ),
      throwsFormatException,
    );
    expect(requestOrder, isEmpty);
    expect(imageClients, 0);
    expect(service.readDraft('default')!.candidates, isEmpty);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 0);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 0);
  });

  test('规划场景超长不进入生图，保留草稿且不使用图片额度', () async {
    plannedImagePrompt = '场' * (kPictureStorySceneDescriptionMaxLength + 1);
    await expectLater(start(count: 2), throwsA(isA<LlmResponseFormatError>()));
    expect(requestOrder, ['规划', '规划']);
    expect(service.readDraft('default')!.candidates, isEmpty);
    expect(imageCalls, 0);
    expect(captionCalls, 0);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 0);
  });

  for (final count in [2, 3, 4, 5]) {
    test('多题规划接受 scenes 对象，$count 题均完整生成并保留顺序', () async {
      service = createService(sse: true);
      planningResponses.add({
        'scenes': [
          for (var i = 0; i < count; i++) {'imagePrompt': '场景 $i：孩子在不同地点帮助伙伴。'},
        ],
      });
      final draft = await start(count: count);
      expect(draft.candidates.length, count);
      expect(draft.candidates.every((item) => item.isReady), isTrue);
      expect(draft.candidates.map((item) => item.imagePrompt), [
        for (var i = 0; i < count; i++) '场景 $i：孩子在不同地点帮助伙伴。',
      ]);
      expect(planCalls, 1);
      expect(imageCalls, count);
      expect(captionCalls, count);
    });
  }

  test('规划数量不足只补缺项，完整规划之前不发起生图', () async {
    planningResponses.addAll([
      [
        {'imagePrompt': '孩子在公园观察蝴蝶。'},
      ],
      [
        {'imagePrompt': '孩子在教室帮助同学。'},
        {'imagePrompt': '孩子在家整理玩具。'},
      ],
    ]);
    final draft = await start(count: 3);
    expect(draft.candidates.length, 3);
    expect(draft.candidates.every((item) => item.isReady), isTrue);
    expect(requestOrder.take(3), ['规划', '规划', '生图 1']);
    final repair =
        ((planRequests.last['messages'] as List).last as Map)['content']
            as String;
    expect(repair, contains('严格生成 2 个'));
    expect(repair, contains('孩子在公园观察蝴蝶。'));
    expect(imageCalls, 3);
  });

  test('规划流被截断时保留传输错误，不当作缺题重复请求', () async {
    incompleteSsePlans = true;
    service = createService(sse: true);
    await expectLater(
      start(count: 2),
      throwsA(isA<LlmResponseFormatError>().having(
        (error) => error.message,
        'message',
        contains('流式响应未完成'),
      )),
    );
    expect(planCalls, 1);
    expect(imageCalls, 0);
    expect(service.readDraft('default')!.candidates, isEmpty);
  });

  test('规划格式修复有界，重复失败保留草稿且不消耗生图额度', () async {
    planningResponses.addAll([
      '不完整 JSON',
      {'scenes': <Object>[]},
    ]);
    await expectLater(start(count: 5), throwsA(isA<LlmResponseFormatError>()));
    expect(planCalls, 2);
    expect(imageCalls, 0);
    expect(service.readDraft('default')!.candidates, isEmpty);
  });

  for (final status in [200, 429]) {
    test('全部看图模型限额后停止后续生图，恢复后可复用原图重试：HTTP $status', () async {
      const config = LlmConfig(
        baseUrl: 'https://llm.example.com',
        apiKey: 'test-text-key',
        model: 'gpt-4o-mini',
        models: ['gpt-4o-mini', 'gpt-4o'],
      );
      if (status == 200) {
        captionLimitNotice =
            "You've used your daily chat limit. Please try again later.";
      } else {
        captionStatus = status;
      }
      service = createService(sse: true);
      final draft = await start(config: config);
      expect(requestOrder, ['规划', '生图 1', '看图 1', '看图 2']);
      expect(captionRequests.map((request) => request['model']).toList(), [
        'gpt-4o-mini',
        'gpt-4o',
      ]);
      expect(imageCalls, 1);
      expect(draft.candidates.map((candidate) => candidate.stage).toList(), [
        PictureStoryGenerationStage.failed,
        PictureStoryGenerationStage.planned,
        PictureStoryGenerationStage.planned,
      ]);
      final failed = draft.candidates.first;
      expect(failed.error, '看图模型额度已用尽或请求受限，请切换模型或稍后保留图片重试');
      final image = failed.edit.image!;
      final stored = await images.readImage(image.value);
      expect(
        draft.candidates.skip(1).map((candidate) => candidate.edit.image),
        [null, null],
      );
      expect(CloudUsageService.instance.used(CloudUsageKind.llm), 3);
      expect(
        CloudUsageService.instance.used(CloudUsageKind.imageGeneration),
        1,
      );

      captionLimitNotice = null;
      captionStatus = null;
      await service.run(
        draft: draft,
        config: config,
        imageConfig: _imageConfig,
        isActive: () => true,
        candidateId: failed.id,
        reuseImageId: image.value,
      );
      final retried = service.readDraft('default')!;
      expect(retried.readyCount, 1);
      expect(retried.candidates.first.edit.image, image);
      expect(retried.candidates.first.edit.toPrompt().title, '观察花朵 3');
      expect(await images.readImage(image.value), stored);
      expect(imageCalls, 1);
      expect(planCalls, 1);
      expect(captionCalls, 3);
      expect(CloudUsageService.instance.used(CloudUsageKind.llm), 4);
      expect(
        CloudUsageService.instance.used(CloudUsageKind.imageGeneration),
        1,
      );
      expect(retried.candidates.skip(1).map((candidate) => candidate.stage), [
        PictureStoryGenerationStage.planned,
        PictureStoryGenerationStage.planned,
      ]);
      expect(repository.catalogState().versions, isEmpty);
    });
  }

  test('先生成实图再看图出题，批量草稿可重读且确认前目录零变化', () async {
    final draft = await start();
    expect(planCalls, 1);
    expect(imageCalls, 3);
    expect(captionCalls, 3);
    expect(draft.readyCount, 3);
    final planning =
        (planRequests.single['messages'] as List).first['content'] as String;
    expect(planning, contains('小学语文课本式看图说话'));
    expect(planning, contains('正在发生的一个关键时刻'));
    expect(planning, contains('不能仅换颜色或装饰'));
    expect(imageRequests, hasLength(3));
    for (var i = 0; i < imageRequests.length; i++) {
      final prompt = imageRequests[i]['prompt'] as String;
      expect(prompt, contains('小学语文课本式插图'));
      expect(prompt, contains('平面手绘儿童教材插图'));
      expect(prompt, contains('正在做什么、与谁或什么物体互动'));
      expect(prompt, contains('不拼图、不分镜'));
      expect(prompt, endsWith('具体场景：\n场景 $i：公园里的孩子观察花朵。'));
    }
    expect(draft.candidates.map((c) => c.id).toSet().length, 3);
    expect(repository.catalogState().versions, isEmpty);
    expect(
      HiveBoxes.settings.containsKey(
        PictureStoryRepository.enabledKeyFor('default'),
      ),
      isFalse,
    );
    expect(
      draft.candidates.every(
        (c) => c.edit.original == null && c.edit.image!.isLocal,
      ),
      isTrue,
    );
    for (final request in captionRequests) {
      final parts = ((request['messages'] as List<dynamic>).last
          as Map<String, dynamic>)['content'] as List<dynamic>;
      final url = ((parts.last as Map<String, dynamic>)['image_url']
          as Map<String, dynamic>)['url'] as String;
      final uploaded = base64Decode(url.split(',').last);
      expect(
        uploaded.length,
        lessThanOrEqualTo(PictureStoryImageService.maxUploadBytes),
      );
      expect(ByteData.sublistView(uploaded).getUint32(16), 640);
      expect(ByteData.sublistView(uploaded).getUint32(20), 480);
      expect(utf8.encode(jsonEncode(request)).length, lessThan(1024 * 1024));
      expect(jsonEncode(parts), isNot(contains('场景 0')));
    }
    final reopened =
        PictureStoryGenerationService(images: images).readDraft('default')!;
    expect(reopened.encode(), draft.encode());
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 4);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 3);
  });

  test('单题文字失败保留图片；只重试该题的看图请求，完成项不重复生成', () async {
    failCaption = 2;
    var draft = await start();
    expect(draft.readyCount, 2);
    final failed = draft.candidates[1];
    expect(failed.stage, PictureStoryGenerationStage.failed);
    expect(failed.error, '看图出题内容不完整或格式不正确，可保留图片重试');
    expect(failed.edit.image, isNotNull);
    final completed = draft.candidates.first.edit.toPrompt();
    await service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
      candidateId: failed.id,
    );
    draft = service.readDraft('default')!;
    expect(draft.readyCount, 3);
    expect(imageCalls, 3);
    expect(planCalls, 1);
    expect(captionCalls, 4);
    expect(draft.candidates[1].edit.image, failed.edit.image);
    expect(
      draft.candidates.first.edit.toPrompt().sameContent(completed),
      isTrue,
    );
  });

  test('复杂大图可以实际发送看图请求，失败后重试复用原图与草稿', () async {
    png = await pictureStoryNoisePng();
    failCaption = 1;
    var draft = await start(count: 1);
    expect(planCalls, 0);
    expect(imageCalls, 1);
    expect(captionCalls, 1);
    final failed = draft.candidates.single;
    expect(failed.stage, PictureStoryGenerationStage.failed);
    final image = failed.edit.image!;
    final stored = await images.readImage(image.value);
    final requestBytes = utf8.encode(jsonEncode(captionRequests.single)).length;
    expect(requestBytes, greaterThan(256 * 1024));
    expect(requestBytes, lessThan(1024 * 1024));
    await service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
      candidateId: failed.id,
      reuseImageId: image.value,
    );
    draft = service.readDraft('default')!;
    expect(draft.readyCount, 1);
    expect(planCalls, 0);
    expect(imageCalls, 1);
    expect(captionCalls, 2);
    expect(imageClients, 1);
    final completed = draft.candidates.single;
    expect(completed.id, failed.id);
    expect(completed.edit.image, image);
    expect(completed.error, isNull);
    expect(completed.edit.toPrompt().title, '观察花朵 2');
    expect(completed.edit.toPrompt().questions, ['你看到了什么？', '想象孩子接下来会做什么？']);
    expect(await images.readImage(image.value), stored);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 2);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 1);
    expect(repository.catalogState().versions, isEmpty);
  });

  test('看图模型服务失败给出明确原因，保留原图后可以只重试出题', () async {
    captionStatus = 400;
    var draft = await start(count: 1);
    final failed = draft.candidates.single;
    expect(failed.stage, PictureStoryGenerationStage.failed);
    expect(failed.error, '看图模型服务请求失败，请检查服务或稍后重试');
    expect(draft.readyCount, 0);
    captionStatus = null;
    await service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
      candidateId: failed.id,
      reuseImageId: failed.edit.image!.value,
    );
    draft = service.readDraft('default')!;
    expect(draft.readyCount, 1);
    expect(draft.candidates.single.edit.image, failed.edit.image);
    expect(planCalls, 0);
    expect(imageCalls, 1);
    expect(captionCalls, 2);
    expect(imageClients, 1);
  });

  test('重试出题的图片缺失或已被替换时零请求失败，不新建图片', () async {
    final expected = await images.importBytes(await pictureStoryPng());
    final replacement = await images.importBytes(
      await pictureStoryPng(width: 5),
    );
    for (final currentImage in [null, replacement]) {
      final draft = await service.createDraft(
        PictureStoryGenerationOptions(
          level: PictureStoryLevel.starter,
          count: 1,
          themes: ['日常生活'],
        ),
      );
      final candidate = PictureStoryGenerationCandidate(
        edit: PictureStoryEditorDraft.create(
          id: 'local-retry-missing-image',
          profileId: draft.profileId,
        ).copyWith(image: currentImage),
        imagePrompt: '已有场景',
        requestId: 'request-before-retry',
        stage: PictureStoryGenerationStage.failed,
      );
      final saved = draft.copyWith([candidate]);
      await HiveBoxes.settings.put(
        PictureStoryGenerationService.keyFor(draft.profileId),
        saved.encode(),
      );
      await expectLater(
        service.run(
          draft: saved,
          config: _llm,
          imageConfig: _imageConfig,
          isActive: () => true,
          candidateId: candidate.id,
          reuseImageId: expected.value,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            '图片归属检查',
            '题图已变化，请重新打开草稿后重试出题',
          ),
        ),
      );
      expect(service.readDraft(draft.profileId)!.encode(), saved.encode());
      expect(planCalls, 0);
      expect(captionCalls, 0);
      expect(imageCalls, 0);
      expect(imageClients, 0);
      await service.discardDraft(saved);
    }
  });

  test('图片已返回时家长锁定，迟到结果只保存原草稿；重新验证后续做不重画', () async {
    final reached = Completer<void>();
    final proceed = Completer<void>();
    var first = true;
    final waitingImages = PictureStoryImageService(
      directoryProvider: () async => directory,
      normalizer: (bytes) async {
        if (first) {
          first = false;
          reached.complete();
          await proceed.future;
        }
        return bytes;
      },
    );
    service = createService(imageService: waitingImages);
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: 3,
        themes: ['日常生活'],
      ),
    );
    final work = service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
    );
    await reached.future;
    lockParentForTesting();
    proceed.complete();
    await work;
    final paused = service.readDraft('default')!;
    expect(
      paused.candidates.first.stage,
      PictureStoryGenerationStage.imageReady,
    );
    expect(paused.candidates.first.edit.image, isNotNull);
    expect(imageCalls, 1);
    expect(captionCalls, 0);
    expect(repository.catalogState().versions, isEmpty);
    await unlockParentForTesting();
    await service.run(
      draft: paused,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
    );
    expect(service.readDraft('default')!.readyCount, 3);
    expect(imageCalls, 3);
    expect(planCalls, 1);
  });

  test('孩子切走再切回仍停止后续请求，原孩子的图片草稿保留', () async {
    final reached = Completer<void>();
    final proceed = Completer<void>();
    final waitingImages = PictureStoryImageService(
      directoryProvider: () async => directory,
      normalizer: (bytes) async {
        reached.complete();
        await proceed.future;
        return bytes;
      },
    );
    service = createService(imageService: waitingImages);
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: 2,
        themes: ['日常生活'],
      ),
    );
    final work = service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
    );
    await reached.future;
    ProfileScope.switchTo('child-b');
    ProfileScope.switchTo('default');
    proceed.complete();
    await work;
    expect(imageCalls, 1);
    expect(captionCalls, 0);
    expect(
      service.readDraft('default')!.candidates.first.edit.image,
      isNotNull,
    );
    expect(service.readDraft('child-b'), isNull);
  });

  test('迟到图片不能覆盖已经替换的批次', () async {
    final reached = Completer<void>();
    final proceed = Completer<void>();
    final waitingImages = PictureStoryImageService(
      directoryProvider: () async => directory,
      normalizer: (bytes) async {
        reached.complete();
        await proceed.future;
        return bytes;
      },
    );
    service = createService(imageService: waitingImages);
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: 1,
        themes: ['日常生活'],
      ),
    );
    final work = service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
    );
    await reached.future;
    final replacement = PictureStoryGenerationDraft(
      id: 'batch-replacement',
      profileId: 'default',
      options: draft.options,
      candidates: [],
    );
    await HiveBoxes.settings.put(
      PictureStoryGenerationService.keyFor('default'),
      replacement.encode(),
    );
    proceed.complete();
    await work;
    expect(service.readDraft('default')!.encode(), replacement.encode());
    expect(captionCalls, 0);
    expect(repository.catalogState().versions, isEmpty);
  });

  test('编辑可空字段，部分内容可恢复；原始输入能在重新锁定后保留但不能入库', () async {
    var draft = await start(count: 1);
    final session = await service.beginEdit(draft, draft.candidates.first.id);
    final fields = {
      ...session.candidate.edit.fields,
      PictureStoryEditorField.title: '',
      PictureStoryEditorField.theme: '',
      PictureStoryEditorField.sceneFacts: '',
      PictureStoryEditorField.goals: '',
      PictureStoryEditorField.reference: '',
    };
    lockParentForTesting();
    await service.saveEdit(
      session,
      session.candidate.edit.copyWith(fields: fields),
    );
    draft = service.readDraft('default')!;
    expect(
      draft.candidates.first.stage,
      PictureStoryGenerationStage.needsEditing,
    );
    expect(
      draft.candidates.first.edit.fields[PictureStoryEditorField.title],
      '',
    );
    await expectLater(
      service.publish(draft, check: () {}),
      throwsA(isA<ParentAccessDenied>()),
    );
    expect(repository.catalogState().versions, isEmpty);
    await unlockParentForTesting();
    await service.saveEdit(
      session,
      session.candidate.edit.copyWith(
        fields: {...fields, PictureStoryEditorField.title: '新的题目'},
      ),
    );
    draft = service.readDraft('default')!;
    expect(draft.readyCount, 1);
    expect(await service.publish(draft, check: () {}), 1);
    expect(repository.findPrompt(draft.candidates.first.id)!.theme, '');
  });

  test('勾选题目一次入库，只启用当前孩子；清理失败重试同 id 不重复添加', () async {
    var draft = await start();
    await service.setSelected(draft, draft.candidates[1].id, false);
    draft = service.readDraft('default')!;
    final snapshot = draft.encode();
    expect(await service.publish(draft, check: () {}), 2);
    expect(repository.catalogState().versions.length, 2);
    final enabled = repository.enabledByProfile()['default']!;
    expect(
      enabled,
      containsAll([draft.candidates[0].id, draft.candidates[2].id]),
    );
    expect(enabled, isNot(contains(draft.candidates[1].id)));
    expect(repository.enabledByProfile(), isNot(contains('child-b')));
    // 模拟提交成功但清理快照失败，读取者见到旧草稿。
    await HiveBoxes.settings.put(
      PictureStoryGenerationService.keyFor('default'),
      snapshot,
    );
    expect(await service.publish(draft, check: () {}), 2);
    expect(repository.catalogState().versions.length, 2);
    expect(service.readDraft('default')!.candidates[1].isReady, isTrue);
    expect(
      service.readDraft('default')!.candidates[0].stage,
      PictureStoryGenerationStage.published,
    );
  });

  test('入库中途写失败回滚原始目录和键缺失状态，草稿可重试', () async {
    final draft = await start(count: 2);
    final faulty = PictureStoryRepository(
      images: images,
      settings: _PartialWriteBox(HiveBoxes.settings),
    );
    final publisher = PictureStoryGenerationService(
      images: images,
      repository: faulty,
      backup: BackupService(
        pictureStoryImages: images,
        pictureStoryRepository: faulty,
      ),
    );
    await expectLater(publisher.publish(draft, check: () {}), throwsStateError);
    expect(
      HiveBoxes.settings.containsKey(PictureStoryRepository.catalogKey),
      isFalse,
    );
    expect(
      HiveBoxes.settings.containsKey(
        PictureStoryRepository.enabledKeyFor('default'),
      ),
      isFalse,
    );
    expect(service.readDraft('default')!.readyCount, 2);
    expect(await publisher.publish(draft, check: () {}), 2);
  });

  test('AI 批量入库先检查全部历史题图的备份预算，超限零写入且零读图', () async {
    final budgetImages = _BudgetImages();
    final entries = [
      for (var i = 0; i < 11; i++)
        pictureStoryFixture(
          id: 'local-history-$i',
          image: PictureStoryImage.local(i.toRadixString(16).padLeft(64, '0')),
        ),
    ];
    final raw = jsonEncode(PictureStoryCatalogState(entries).toJson());
    await HiveBoxes.settings.put(PictureStoryRepository.catalogKey, raw);
    final budgetRepository = PictureStoryRepository(images: budgetImages);
    final backup = BackupService(
      pictureStoryImages: budgetImages,
      pictureStoryRepository: budgetRepository,
    );
    await expectLater(
      budgetRepository.saveGeneratedPrompts(
        prompts: [
          for (var i = 11; i < 13; i++)
            pictureStoryFixture(
              id: 'local-new-$i',
              image: PictureStoryImage.local(
                i.toRadixString(16).padLeft(64, '0'),
              ),
            ),
        ],
        profileId: 'default',
        check: () {},
        beforeCommit: backup.validatePictureStoryPublication,
      ),
      throwsFormatException,
    );
    expect(HiveBoxes.settings.get(PictureStoryRepository.catalogKey), raw);
    expect(
      HiveBoxes.settings.containsKey(
        PictureStoryRepository.enabledKeyFor('default'),
      ),
      isFalse,
    );
    expect(budgetImages.reads, 0);
  });

  test('生成题图、出题场景、生图设置及加密密钥在新目录完整恢复，草稿和已用额度不搬运', () async {
    final secrets = _ImageSecrets();
    final settings = SettingsRepository(credentialStore: secrets);
    await settings.saveImageGenerationConfig(
      provider: _imageProvider,
      apiKey: 'image-backup-secret',
    );
    await settings.saveLlmProviderConfig(
      id: 'text-provider',
      name: '看图',
      baseUrl: _llm.baseUrl,
      model: _llm.model,
      apiKey: '',
    );
    await HiveBoxes.settings.put(
      LlmScenario.pictureStory.settingsKey,
      'text-provider',
    );
    await HiveBoxes.settings.put(LlmScenario.pictureStory.modelKey, _llm.model);
    await HiveBoxes.settings.put('cloud_daily_limit_image', 7);
    final draft = await start(count: 2);
    await service.setSelected(draft, draft.candidates.last.id, false);
    await service.publish(service.readDraft('default')!, check: () {});
    final source = BackupService(
      secureStore: secrets,
      pictureStoryImages: images,
    );
    final text = await source.exportToJson(
      passphrase: 'test-backup-passphrase',
    );
    expect(text, isNot(contains('image-backup-secret')));
    expect(text, isNot(contains(draft.id)));
    final data = jsonDecode(text) as Map<String, dynamic>;
    final payload = await decryptCredentials(
      data['credentials'] as Map<String, dynamic>,
      'test-backup-passphrase',
    );
    expect(payload[kCredKeyImageGenerationApiKey], 'image-backup-secret');
    expect(payload[kCredKeyImageGenerationHint], _imageProvider.credentialHint);
    final catalog = repository.catalogState().toJson();
    final enabled = repository.enabledByProfile();
    final usage = CloudUsageService.exportCounts();
    final destination = await Directory.systemTemp.createTemp(
      'picture_story_generation_restored_',
    );
    addTearDown(() => destination.delete(recursive: true));
    await HiveBoxes.settings.clear();
    await unlockParentForTesting();
    secrets.key = null;
    final restoredImages = PictureStoryImageService(
      directoryProvider: () async => destination,
    );
    final restored = BackupService(
      secureStore: secrets,
      pictureStoryImages: restoredImages,
    );
    expect(
      BackupService.detectLlmEndpointChanges(text)!.added,
      contains('image.example.com'),
    );
    await restored.restoreFromJson(text, passphrase: 'test-backup-passphrase');
    final reopened = PictureStoryRepository(images: restoredImages);
    expect(reopened.catalogState().toJson(), catalog);
    expect(reopened.enabledByProfile(), enabled);
    expect(
      SettingsRepository(credentialStore: secrets)
          .imageGenerationProvider!
          .encode(),
      _imageProvider.encode(),
    );
    expect(secrets.key, 'image-backup-secret');
    expect(
      HiveBoxes.settings.get(LlmScenario.pictureStory.settingsKey),
      'text-provider',
    );
    expect(
      HiveBoxes.settings.get(LlmScenario.pictureStory.modelKey),
      _llm.model,
    );
    expect(HiveBoxes.settings.get('cloud_daily_limit_image'), 7);
    expect(service.readDraft('default'), isNull);
    expect(CloudUsageService.exportCounts(), usage);
    for (final id in reopened.catalogState().imageIds) {
      expect(await restoredImages.readImage(id), await images.readImage(id));
    }
  });
}
