import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
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
const _imageConfig =
    ImageGenerationConfig(provider: _imageProvider, apiKey: 'test-image-key');

http.Response _completion(Object content) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': jsonEncode(content)},
            }
          ],
        }),
      ),
      200,
    );

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
  var failCaption = 0;
  final captionRequests = <Map<String, dynamic>>[];

  PictureStoryGenerationService createService({
    PictureStoryImageService? imageService,
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
              planCalls++;
              final saved = service.readDraft('default')!;
              return _completion([
                for (var i = 0; i < saved.options.count; i++)
                  {'imagePrompt': '场景 $i：公园里的孩子观察花朵。'},
              ]);
            }
            captionCalls++;
            captionRequests.add(body);
            if (captionCalls == failCaption) {
              return _completion({'title': '不完整内容'});
            }
            return _completion({
              'title': '观察花朵 $captionCalls',
              'theme': '',
              'sceneFacts': ['孩子在看花朵'],
              'questions': ['你看到了什么？', '想象孩子接下来会做什么？'],
              'goals': <String>[],
              'reference': '',
            });
          }),
        ),
        imageFactory: (active) => ImageGenerationClient(
          isActive: active,
          httpClient: MockClient((_) async {
            imageCalls++;
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

  Future<PictureStoryGenerationDraft> start({int count = 3}) async {
    final draft = await service.createDraft(
      PictureStoryGenerationOptions(
        level: PictureStoryLevel.growing,
        count: count,
        themes: ['自然观察', '友爱互助'],
      ),
    );
    await service.run(
      draft: draft,
      config: _llm,
      imageConfig: _imageConfig,
      isActive: () => true,
    );
    return service.readDraft('default')!;
  }

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory =
        await Directory.systemTemp.createTemp('picture_story_generation_');
    png = await pictureStoryPng(width: 640, height: 480);
    images = PictureStoryImageService(directoryProvider: () async => directory);
    repository = PictureStoryRepository(images: images);
    planCalls = 0;
    captionCalls = 0;
    imageCalls = 0;
    failCaption = 0;
    captionRequests.clear();
    service = createService();
  });
  tearDown(() async {
    service.pause('default');
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  test('先生成实图再看图出题，批量草稿可重读且确认前目录零变化', () async {
    final draft = await start();
    expect(planCalls, 1);
    expect(imageCalls, 3);
    expect(captionCalls, 3);
    expect(draft.readyCount, 3);
    expect(draft.candidates.map((c) => c.id).toSet().length, 3);
    expect(repository.catalogState().versions, isEmpty);
    expect(
      HiveBoxes.settings
          .containsKey(PictureStoryRepository.enabledKeyFor('default')),
      isFalse,
    );
    expect(
      draft.candidates
          .every((c) => c.edit.original == null && c.edit.image!.isLocal),
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
    await HiveBoxes.settings
        .put(PictureStoryGenerationService.keyFor('default'), snapshot);
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
      HiveBoxes.settings
          .containsKey(PictureStoryRepository.enabledKeyFor('default')),
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
              image:
                  PictureStoryImage.local(i.toRadixString(16).padLeft(64, '0')),
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
      HiveBoxes.settings
          .containsKey(PictureStoryRepository.enabledKeyFor('default')),
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
    await HiveBoxes.settings
        .put(LlmScenario.pictureStory.settingsKey, 'text-provider');
    await HiveBoxes.settings.put(LlmScenario.pictureStory.modelKey, _llm.model);
    await HiveBoxes.settings.put('cloud_daily_limit_image', 7);
    final draft = await start(count: 2);
    await service.setSelected(draft, draft.candidates.last.id, false);
    await service.publish(service.readDraft('default')!, check: () {});
    final source =
        BackupService(secureStore: secrets, pictureStoryImages: images);
    final text =
        await source.exportToJson(passphrase: 'test-backup-passphrase');
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
    final destination = await Directory.systemTemp
        .createTemp('picture_story_generation_restored_');
    addTearDown(() => destination.delete(recursive: true));
    await HiveBoxes.settings.clear();
    await unlockParentForTesting();
    secrets.key = null;
    final restoredImages =
        PictureStoryImageService(directoryProvider: () async => destination);
    final restored =
        BackupService(secureStore: secrets, pictureStoryImages: restoredImages);
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
