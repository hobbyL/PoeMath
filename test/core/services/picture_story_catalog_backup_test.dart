import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_payload_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/picture_story_catalog_backup.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _FailingFavorites extends Fake implements Box<PoemFavorite> {
  _FailingFavorites(this.delegate, {required this.alwaysFail});
  final Box<PoemFavorite> delegate;
  final bool alwaysFail;
  var clearCalls = 0;

  @override
  Iterable<PoemFavorite> get values => delegate.values;
  @override
  Future<void> put(dynamic key, PoemFavorite value) => delegate.put(key, value);
  @override
  Future<int> clear() async {
    final result = await delegate.clear();
    clearCalls++;
    if (alwaysFail || clearCalls == 1) throw HiveError('模拟收藏写入后失败');
    return result;
  }
}

class _BudgetImages extends PictureStoryImageService {
  var readCalls = 0;
  @override
  Future<void> ensureStored(PictureStoryImage image) async {}
  @override
  Future<int> storedImageSize(String id) async =>
      PictureStoryImageService.maxStoredBytes;
  @override
  Future<Uint8List> readImage(String id) async {
    readCalls++;
    throw StateError('超限导出不应先读取图片');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PictureStoryImageService images;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp('picture_story_backup_');
    images = PictureStoryImageService(directoryProvider: () async => directory);
  });
  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  BackupService backup({PictureStoryImageService? imageService}) =>
      BackupService(pictureStoryImages: imageService ?? images);

  Future<PictureStoryImage> importImage(String name, int width) async {
    final source = File('${directory.path}/$name.png');
    await source.writeAsBytes(await pictureStoryPng(width: width, height: 7));
    return images.importPath(source.path);
  }

  Future<String> populatedBackup() async {
    final repository = PictureStoryRepository(images: images);
    final firstImage = await importImage('first', 11);
    final secondImage = await importImage('second', 13);
    final first = await repository.savePrompt(
      prompt: pictureStoryFixture(image: firstImage),
      profileId: 'default',
      enableForProfile: false,
    );
    await repository.savePrompt(
      prompt: first.copyWith(title: '小猫和窗外的小鸟', image: secondImage),
      original: first,
      profileId: 'default',
    );
    final builtin = PictureStoryCatalog.prompts.first;
    await repository.savePrompt(
      prompt: builtin.copyWith(title: '我们一起放风筝', image: firstImage),
      original: builtin,
      profileId: 'default',
    );
    ProfileScope.switchTo('child-a');
    await repository.setEnabled(first.id, true);
    ProfileScope.switchTo('child-b');
    await repository.setEnabled(first.id, true);
    await repository.setEnabled('rainy-day-umbrella', false);
    ProfileScope.reset();
    return backup().exportToJson();
  }

  test('题库版本、去重图片和各档案启用选择在新目录恢复，重启后离线一致', () async {
    final text = await populatedBackup();
    final sourceRepository = PictureStoryRepository(images: images);
    final catalog = sourceRepository.catalogState().toJson();
    final enabled = sourceRepository.enabledByProfile();
    final imageBytes = <String, Uint8List>{};
    for (final id in sourceRepository.catalogState().imageIds) {
      imageBytes[id] = await images.readImage(id);
    }
    expect(backup().inspectJson(text).counts['看图说话题目'], 2);
    expect(backup().inspectJson(text).counts['题目图片'], 2);
    await tearDownHiveForTesting();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    final target = Directory('${directory.path}/new-device');
    final targetImages =
        PictureStoryImageService(directoryProvider: () async => target);
    await backup(imageService: targetImages).restoreFromJson(text);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = PictureStoryRepository(images: targetImages);
    expect(reopened.catalogState().toJson(), catalog);
    expect(reopened.enabledByProfile(), enabled);
    expect(reopened.findPrompt('local-fixture')!.version, 2);
    expect(reopened.findPrompt('local-fixture', version: 1)!.title, '窗前的小猫');
    expect(
      reopened.findPrompt('kite-in-the-park', version: 1)!.toJson(),
      PictureStoryCatalog.prompts.first.toJson(),
    );
    for (final entry in imageBytes.entries) {
      expect(await targetImages.readImage(entry.key), entry.value);
      expect(
        await File('${target.path}/picture_story/images/${entry.key}.png')
            .exists(),
        isTrue,
      );
    }
    expect(reopened.isEnabled('local-fixture'), isFalse);
    ProfileScope.switchTo('child-a');
    expect(reopened.isEnabled('local-fixture'), isTrue);
    ProfileScope.switchTo('child-b');
    expect(reopened.isEnabled('rainy-day-umbrella'), isFalse);
  });

  test('整包加密和本机保护快照共用完整题库段，临时表单与录音历史不迁移', () async {
    await populatedBackup();
    final repository = PictureStoryRepository(images: images);
    final expected = repository.catalogState().toJson();
    final draft = PictureStoryEditorDraft.create(
      id: 'local-unsaved',
      profileId: 'default',
    );
    await HiveBoxes.settings
        .put(PictureStoryEditorService.draftKey, jsonEncode(draft.toJson()));
    await repository.save(
      PictureStoryPracticeRecord(
        id: 'keep-record-on-device',
        profileId: 'default',
        promptId: 'local-fixture',
        promptVersion: 1,
        startedAt: DateTime(2026),
        status: 'completed',
        segmentsJson: jsonEncode([
          {'audioPath': '/private/device-only.m4a'},
        ]),
      ),
    );
    final plain =
        jsonDecode(await backup().exportToJson()) as Map<String, dynamic>;
    final settings = plain['settings'] as Map;
    expect(settings.containsKey(PictureStoryRepository.catalogKey), isFalse);
    expect(settings.containsKey(PictureStoryEditorService.draftKey), isFalse);
    expect(plain.containsKey('pictureStoryPractice'), isFalse);
    expect(jsonEncode(plain), isNot(contains('keep-record-on-device')));
    expect(jsonEncode(plain), isNot(contains('/private/device-only.m4a')));
    final encrypted = await backup().exportToJson(
      passphrase: 'picture-test-passphrase',
      encryptPayload: true,
      includeCredentials: false,
    );
    expect(isEncryptedBackup(encrypted), isTrue);
    final history = BackupHistoryService(
      backup: backup(),
      directoryProvider: () async => directory,
      keyProvider: () async => List<int>.generate(32, (index) => index),
    );
    final snapshot = await history.create(reason: 'before_restore');
    final saved = await history.read(snapshot.id);
    expect(
      jsonDecode(saved)['pictureStoryCatalog'],
      plain['pictureStoryCatalog'],
    );
    final fileText =
        await File('${directory.path}/backup_history/${snapshot.id}')
            .readAsString();
    expect(isEncryptedBackup(fileText), isTrue);
    await HiveBoxes.settings.delete(PictureStoryRepository.catalogKey);
    await backup()
        .restoreFromJson(encrypted, passphrase: 'picture-test-passphrase');
    expect(
      PictureStoryRepository(images: images).catalogState().toJson(),
      expected,
    );
    expect(
      PictureStoryRepository(images: images).find('keep-record-on-device'),
      isNotNull,
    );
  });

  test('旧备份缺少题库段保留原始键值，坏旧目录也不要求读取图片', () async {
    await HiveBoxes.settings.put(PictureStoryRepository.catalogKey, '损坏的旧目录原值');
    await HiveBoxes.settings
        .put(PictureStoryRepository.enabledKeyFor('child-a'), ['原始旧类型']);
    final repository = PictureStoryRepository(images: images);
    final before = repository.storageSnapshot();
    var calls = 0;
    final unavailableImages = PictureStoryImageService(
      directoryProvider: () async {
        calls++;
        throw StateError('不应请求图片目录');
      },
    );
    await backup(imageService: unavailableImages)
        .restoreFromJson(jsonEncode({'version': 1}));
    expect(repository.storageSnapshot(), before);
    expect(calls, 0);
  });

  test('显式空题库段恢复内置默认，已保存图片与本机临时表单保留', () async {
    await populatedBackup();
    final repository = PictureStoryRepository(images: images);
    final id = repository.catalogState().imageIds.first;
    final beforeBytes = await images.readImage(id);
    await HiveBoxes.settings
        .put(PictureStoryEditorService.draftKey, '本机尚未发布的表单');
    await backup().restoreFromJson(
      jsonEncode({
        'version': 1,
        'pictureStoryCatalog': {
          'schemaVersion': 1,
          'versions': <Map<String, Object>>[],
          'enabledByProfile': <String, List<String>>{},
          'images': <String, String>{},
        },
      }),
    );
    expect(repository.storageSnapshot(), isEmpty);
    expect(
      repository.listPrompts().map((prompt) => prompt.toJson()).toList(),
      PictureStoryCatalog.prompts.map((prompt) => prompt.toJson()).toList(),
    );
    expect(repository.listPrompts(enabledOnly: true).length, 3);
    expect(await images.readImage(id), beforeBytes);
    expect(
      HiveBoxes.settings.get(PictureStoryEditorService.draftKey),
      '本机尚未发布的表单',
    );
  });

  test('坏 schema、版本、必填字段、启用类型和图片引用均在数据变更前拒绝', () async {
    final text = await populatedBackup();
    final before = PictureStoryRepository(images: images).storageSnapshot();
    final key = 'default_keep-favorite';
    await HiveBoxes.poemFavorites
        .put(key, PoemFavorite(poemId: 'keep-favorite', profileId: 'default'));
    final changes = <void Function(Map<String, dynamic>)>[
      (node) => node['schemaVersion'] = 99,
      (node) =>
          (node['versions'] as List).add((node['versions'] as List).first),
      (node) => (node['versions'] as List).first['version'] = 7,
      (node) => (node['versions'] as List).first['id'] = '../outside',
      (node) => (node['versions'] as List).first['title'] = ' ',
      (node) => (node['versions'] as List).first['questions'] = <String>[],
      (node) => node['enabledByProfile'] = {
            'child-a': <bool>[true],
          },
      (node) => node['enabledByProfile'] = {'': <String>[]},
      (node) => node['images'] = <String, String>{},
      (node) =>
          (node['images'] as Map)[(node['images'] as Map).keys.first] = '!!!',
      (node) => (node['images'] as Map)[(node['images'] as Map).keys.first] =
          base64Encode(List<int>.filled(33, 0)),
    ];
    for (final change in changes) {
      final data = jsonDecode(text) as Map<String, dynamic>;
      change(data['pictureStoryCatalog'] as Map<String, dynamic>);
      await expectLater(
        backup().restoreFromJson(jsonEncode(data)),
        throwsFormatException,
      );
      expect(PictureStoryRepository(images: images).storageSnapshot(), before);
      expect(HiveBoxes.poemFavorites.get(key)!.poemId, 'keep-favorite');
      expect(HiveBoxes.meta.containsKey('practice_draft_epoch'), isFalse);
    }
  });

  test('图片通过头部与 SHA 检查但完整解码失败时，尚未发布文件或清空数据', () async {
    final png = await pictureStoryPng();
    final broken = Uint8List.fromList(png.sublist(0, 33));
    final id = sha256.convert(broken).toString();
    final node = {
      'schemaVersion': 1,
      'versions': [
        pictureStoryFixture(image: PictureStoryImage.local(id)).toJson(),
      ],
      'enabledByProfile': <String, Object>{},
      'images': {id: base64Encode(broken)},
    };
    PictureStoryCatalogBackup.fromJson(node);
    await HiveBoxes.settings
        .put(PictureStoryRepository.enabledKeyFor('default'), '[]');
    final before = PictureStoryRepository(images: images).storageSnapshot();
    final text = jsonEncode({'version': 1, 'pictureStoryCatalog': node});
    await expectLater(
      backup().restoreFromJson(text),
      throwsA(isA<Exception>()),
    );
    expect(PictureStoryRepository(images: images).storageSnapshot(), before);
    expect(HiveBoxes.meta.containsKey('practice_draft_epoch'), isFalse);
    expect(
      await Directory('${directory.path}/picture_story/images').exists(),
      isFalse,
    );
  });

  test('超过总图片预算在读取与 Base64 分配前拒绝，缺失图片也不静默省略', () async {
    final budgetImages = _BudgetImages();
    final repository = PictureStoryRepository(images: budgetImages);
    for (var index = 0; index < 13; index++) {
      final id = sha256.convert([index]).toString();
      await repository.savePrompt(
        prompt: pictureStoryFixture(
          id: 'local-budget-$index',
          image: PictureStoryImage.local(id),
        ),
        profileId: 'default',
      );
    }
    await expectLater(
      backup(imageService: budgetImages).exportToJson(),
      throwsA(
        isA<FormatException>()
            .having((error) => error.message, 'message', contains('32 MiB')),
      ),
    );
    expect(budgetImages.readCalls, 0);
    final before = repository.storageSnapshot();
    await expectLater(
      backup().exportToJson(),
      throwsA(
        isA<PictureStoryImageException>()
            .having((error) => error.message, 'message', contains('图片缺失')),
      ),
    );
    expect(repository.storageSnapshot(), before);
  });

  for (final alwaysFail in [false, true]) {
    test('后续 Hive 恢复失败，题库原值与不存在状态独立补偿（持续失败=$alwaysFail）', () async {
      final text = await populatedBackup();
      await HiveBoxes.settings.delete(PictureStoryRepository.catalogKey);
      await HiveBoxes.settings
          .put(PictureStoryRepository.enabledKeyFor('child-a'), 7);
      await HiveBoxes.settings
          .delete(PictureStoryRepository.enabledKeyFor('child-b'));
      final repository = PictureStoryRepository(images: images);
      final before = repository.storageSnapshot();
      await HiveBoxes.poemFavorites.put(
        'default_old',
        PoemFavorite(poemId: 'old', profileId: 'default'),
      );
      final originalBox = HiveBoxes.poemFavorites;
      final failing = _FailingFavorites(originalBox, alwaysFail: alwaysFail);
      HiveBoxes.poemFavorites = failing;
      try {
        await expectLater(
          backup().restoreFromJson(text),
          alwaysFail
              ? throwsA(
                  isA<BackupRestoreException>().having(
                    (error) => error.rollbackFailed,
                    'rollbackFailed',
                    isTrue,
                  ),
                )
              : throwsA(isA<HiveError>()),
        );
      } finally {
        HiveBoxes.poemFavorites = originalBox;
      }
      expect(failing.clearCalls, 2);
      expect(repository.storageSnapshot(), before);
      expect(
        HiveBoxes.settings.containsKey(PictureStoryRepository.catalogKey),
        isFalse,
      );
      expect(
        HiveBoxes.settings
            .containsKey(PictureStoryRepository.enabledKeyFor('child-b')),
        isFalse,
      );
      expect(HiveBoxes.meta.containsKey('practice_draft_epoch'), isFalse);
      if (!alwaysFail) {
        expect(HiveBoxes.poemFavorites.get('default_old')!.poemId, 'old');
      }
    });
  }

  test('恢复后统一失效能重新读取先前缓存的缺失图片，题库监听同步更新', () async {
    final bytes = await pictureStoryPng(width: 19, height: 7);
    final id = sha256.convert(bytes).toString();
    final container = ProviderContainer(
      overrides: [
        pictureStoryImageServiceProvider.overrideWithValue(images),
      ],
    );
    addTearDown(container.dispose);
    final subscription =
        container.listen(pictureStoryImageBytesProvider(id), (_, __) {});
    addTearDown(subscription.close);
    await expectLater(
      container.read(pictureStoryImageBytesProvider(id).future),
      throwsA(isA<PictureStoryImageException>()),
    );
    expect(container.read(pictureStoryPromptCountProvider), 3);
    await backup().restoreFromJson(
      jsonEncode({
        'version': 1,
        'pictureStoryCatalog': {
          'schemaVersion': 1,
          'versions': [
            pictureStoryFixture(image: PictureStoryImage.local(id)).toJson(),
          ],
          'enabledByProfile': {
            'default': [
              ...PictureStoryCatalog.prompts.map((prompt) => prompt.id),
              'local-fixture',
            ],
          },
          'images': {id: base64Encode(bytes)},
        },
      }),
    );
    invalidateAllHiveProviders(container.invalidate);
    expect(
      await container.read(pictureStoryImageBytesProvider(id).future),
      bytes,
    );
    expect(container.read(pictureStoryPromptCountProvider), 4);
  });
}
