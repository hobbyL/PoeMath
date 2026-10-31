import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _PartialWriteBox extends Fake implements Box<dynamic> {
  _PartialWriteBox(this.delegate, {this.failNext = true});
  final Box<dynamic> delegate;
  bool failNext;
  int writes = 0;

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
  Future<void> deleteAll(Iterable<dynamic> keys) => delegate.deleteAll(keys);
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    writes++;
    if (failNext && entries.isNotEmpty) {
      failNext = false;
      await delegate.putAll({entries.keys.first: entries.values.first});
      throw StateError('模拟第二个键写入失败');
    }
    await delegate.putAll(entries);
  }
}

class _CountingImages extends PictureStoryImageService {
  _CountingImages({super.directoryProvider});
  int checks = 0;
  @override
  Future<void> ensureStored(PictureStoryImage image) async {
    checks++;
    await super.ensureStored(image);
  }
}

class _WaitingImages extends PictureStoryImageService {
  final reached = Completer<void>();
  final proceed = Completer<void>();
  @override
  Future<void> ensureStored(PictureStoryImage image) async {
    reached.complete();
    await proceed.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
  });
  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  List<PictureStoryPrompt> versions(int count, {PictureStoryImage? image}) =>
      List.generate(
        count,
        (i) => pictureStoryFixture(
          image: image ?? const PictureStoryImage.builtin('kite'),
        ).copyWith(version: i + 1, title: '版本 ${i + 1}'),
      );

  Future<void> seedVersions(int count, {PictureStoryImage? image}) async {
    await HiveBoxes.settings.put(
      PictureStoryRepository.catalogKey,
      jsonEncode(
        PictureStoryCatalogState(versions(count, image: image)).toJson(),
      ),
    );
  }

  test('目录生产与解码共用累计版本上限，10000可读、10001拒绝', () {
    expect(PictureStoryCatalogState.maxVersions, 10000);
    final entries = versions(10000);
    final atLimit = PictureStoryCatalogState(entries).toJson();
    expect(PictureStoryCatalogState.fromJson(atLimit).versions.length, 10000);
    final extra = entries.last.copyWith(version: 10001);
    expect(
      () => PictureStoryCatalogState([...entries, extra]),
      throwsFormatException,
    );
    expect(
      () => PictureStoryCatalogState.fromJson({
        'schemaVersion': PictureStoryCatalogState.schemaVersion,
        'versions': [...entries.map((p) => p.toJson()), extra.toJson()],
      }),
      throwsFormatException,
    );
  });

  test('9999编辑可到10000；满容量无变化成功，再修改零写入且重开仍可读', () async {
    await seedVersions(9999);
    final settings = _PartialWriteBox(HiveBoxes.settings, failNext: false);
    final images = _CountingImages();
    var repository = PictureStoryRepository(settings: settings, images: images);
    final original = repository.findPrompt('local-fixture')!;
    final saved = await repository.savePrompt(
      prompt: original.copyWith(title: '上限版本'),
      original: original,
      profileId: 'default',
    );
    expect(saved.version, 10000);
    expect(repository.catalogState().versions.length, 10000);
    expect(settings.writes, 1);
    expect(images.checks, 1);
    final before = repository.storageSnapshot();
    final unchanged = await repository.savePrompt(
      prompt: saved.copyWith(),
      original: saved,
      profileId: 'default',
    );
    expect(unchanged.toJson(), saved.toJson());
    await expectLater(
      repository.savePrompt(
        prompt: saved.copyWith(title: '不应发布'),
        original: saved,
        profileId: 'default',
      ),
      throwsFormatException,
    );
    expect(settings.writes, 1);
    expect(images.checks, 1);
    expect(repository.storageSnapshot(), before);
    expect(repository.findPrompt('local-fixture', version: 1)!.title, '版本 1');
    await HiveBoxes.close();
    await HiveBoxes.init();
    repository = PictureStoryRepository();
    expect(repository.findPrompt('local-fixture')!.version, 10000);
    expect(repository.listPrompts().length, 4);
  });

  test('满容量拒绝新增，目录、两档案选择、历史版本和实际图片完整保留', () async {
    final directory =
        await Directory.systemTemp.createTemp('picture_capacity_');
    addTearDown(() => directory.delete(recursive: true));
    final images = _CountingImages(directoryProvider: () async => directory);
    final source = File('${directory.path}/source.png');
    await source.writeAsBytes(await pictureStoryPng());
    final image = await images.importPath(source.path);
    final storedPath = (await images.imagePath(image.value))!;
    final stored = File(storedPath);
    final imageBytes = await stored.readAsBytes();
    await seedVersions(10000, image: image);
    await HiveBoxes.settings.putAll({
      PictureStoryRepository.enabledKeyFor('default'): '[ "local-fixture" ]',
      PictureStoryRepository.enabledKeyFor('child-b'): '[ ]',
    });
    final settings = _PartialWriteBox(HiveBoxes.settings, failNext: false);
    final repository =
        PictureStoryRepository(settings: settings, images: images);
    final record = PictureStoryPracticeRecord(
      id: 'capacity-history',
      profileId: 'default',
      promptId: 'local-fixture',
      promptVersion: 1,
      startedAt: DateTime(2026),
      status: 'completed',
      segmentsJson: '[]',
      answerText: '已经保存的表达',
    );
    await repository.save(record);
    final before = repository.storageSnapshot();
    await expectLater(
      repository.savePrompt(
        prompt: pictureStoryFixture(id: 'local-new', image: image),
        profileId: 'default',
      ),
      throwsFormatException,
    );
    expect(settings.writes, 0);
    expect(images.checks, 0);
    expect(repository.storageSnapshot(), before);
    expect(repository.findPrompt('local-new'), isNull);
    expect(repository.findPrompt('local-fixture', version: 1)!.image, image);
    expect(repository.find(record.id)!.answerText, '已经保存的表达');
    expect(repository.find(record.id)!.promptVersion, 1);
    expect(await images.imagePath(image.value), storedPath);
    expect(await stored.readAsBytes(), imageBytes);
    expect(await source.exists(), isTrue);
  });

  test('首次编辑内置题把补入的v1计入容量，9999拒绝、9998可发布v2', () async {
    await seedVersions(9999);
    final settings = _PartialWriteBox(HiveBoxes.settings, failNext: false);
    final repository = PictureStoryRepository(settings: settings);
    final original = repository.findPrompt('kite-in-the-park')!;
    final before = repository.storageSnapshot();
    await expectLater(
      repository.savePrompt(
        prompt: original.copyWith(title: '内置题修改'),
        original: original,
        profileId: 'default',
      ),
      throwsFormatException,
    );
    expect(settings.writes, 0);
    expect(repository.storageSnapshot(), before);
    expect(repository.findPrompt(original.id)!.toJson(), original.toJson());
    await seedVersions(9998);
    final saved = await repository.savePrompt(
      prompt: original.copyWith(title: '内置题修改'),
      original: original,
      profileId: 'default',
    );
    expect(saved.version, 2);
    expect(repository.catalogState().versions.length, 10000);
    expect(
      repository.findPrompt(original.id, version: 1)!.toJson(),
      original.toJson(),
    );
    expect(
      repository
          .storageSnapshot()
          .containsKey(PictureStoryRepository.enabledKeyFor('default')),
      isFalse,
    );
  });

  test('工作草稿修改不会通过 Hive 实例缓存提前改变持久记录', () async {
    final repository = PictureStoryRepository();
    final working = PictureStoryPracticeRecord(
      id: 'isolated-draft',
      profileId: 'default',
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026),
      status: 'draft',
      segmentsJson: '[]',
      answerText: '原先保存的表达',
    );
    await repository.save(working);
    working.status = 'completed';
    working.answerText = '尚未保存的表达';
    working.setSegments([
      const PictureStorySegment(
        id: 'new-segment',
        position: 0,
        audioPath: '/device/new.wav',
        durationSeconds: 2,
        editedText: '尚未保存',
      ),
    ]);
    final cached = repository.find(working.id)!;
    expect(cached.status, 'draft');
    expect(cached.answerText, '原先保存的表达');
    expect(cached.segments, isEmpty);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = PictureStoryRepository().find(working.id)!;
    expect(reopened.status, 'draft');
    expect(reopened.answerText, '原先保存的表达');
    expect(reopened.segments, isEmpty);
  });

  test('旧安装默认启用三道内置题，读取不创建共享目录', () {
    final repository = PictureStoryRepository();
    expect(
      repository.listPrompts().map((p) => p.toJson()),
      PictureStoryCatalog.prompts.map((p) => p.toJson()),
    );
    expect(repository.listPrompts(enabledOnly: true).length, 3);
    expect(
      HiveBoxes.settings.containsKey(PictureStoryRepository.catalogKey),
      isFalse,
    );
  });

  test('A/B 共用内容，各自启用；关闭重开仍保留内容和选择', () async {
    ProfileScope.switchTo('child-a');
    var repository = PictureStoryRepository();
    final saved = await repository.savePrompt(
      prompt: pictureStoryFixture(),
      profileId: 'child-a',
    );
    expect(repository.isEnabled(saved.id), isTrue);
    ProfileScope.switchTo('child-b');
    expect(repository.findPrompt(saved.id)!.toJson(), saved.toJson());
    expect(repository.isEnabled(saved.id), isFalse);
    await repository.setEnabled(saved.id, true);
    ProfileScope.switchTo('child-a');
    await repository.setEnabled(saved.id, false);
    await HiveBoxes.close();
    await HiveBoxes.init();
    repository = PictureStoryRepository();
    expect(repository.findPrompt(saved.id)!.toJson(), saved.toJson());
    expect(repository.isEnabled(saved.id), isFalse);
    ProfileScope.switchTo('child-b');
    expect(repository.isEnabled(saved.id), isTrue);
  });

  test('新增可保持停用，编辑内置题保留原版和练习版本', () async {
    final repository = PictureStoryRepository();
    await repository.savePrompt(
      prompt: pictureStoryFixture(),
      profileId: ProfileScope.currentId,
      enableForProfile: false,
    );
    expect(repository.isEnabled('local-fixture'), isFalse);
    final original = repository.findPrompt('kite-in-the-park')!;
    final record = PictureStoryPracticeRecord(
      id: 'completed-v1',
      profileId: ProfileScope.currentId,
      promptId: original.id,
      promptVersion: original.version,
      startedAt: DateTime(2026, 10, 30),
      status: 'completed',
      segmentsJson: '[]',
    );
    await repository.save(record);
    final updated = await repository.savePrompt(
      prompt: original.copyWith(title: '周末放风筝', reference: '孩子在公园放风筝。'),
      original: original,
      profileId: ProfileScope.currentId,
    );
    expect(updated.version, 2);
    expect(
      repository.findPrompt(original.id, version: 1)!.toJson(),
      original.toJson(),
    );
    expect(repository.findPrompt(original.id)!.toJson(), updated.toJson());
    expect(repository.find(record.id)!.promptVersion, 1);
    final raw = HiveBoxes.settings.get(PictureStoryRepository.catalogKey);
    await repository.savePrompt(
      prompt: updated,
      original: updated,
      profileId: ProfileScope.currentId,
    );
    expect(HiveBoxes.settings.get(PictureStoryRepository.catalogKey), raw);
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(
      PictureStoryRepository().findPrompt(original.id, version: 1)!.toJson(),
      original.toJson(),
    );
    expect(
      PictureStoryRepository().findPrompt(original.id)!.toJson(),
      updated.toJson(),
    );
  });

  test('旧表单不能覆盖新版，失败仍可继续进行下一次合法编辑', () async {
    final repository = PictureStoryRepository();
    final v1 = repository.findPrompt('kite-in-the-park')!;
    final v2 = await repository.savePrompt(
      prompt: v1.copyWith(title: '新标题'),
      original: v1,
      profileId: ProfileScope.currentId,
    );
    await expectLater(
      repository.savePrompt(
        prompt: v1.copyWith(title: '过期标题'),
        original: v1,
        profileId: ProfileScope.currentId,
      ),
      throwsFormatException,
    );
    expect(repository.findPrompt(v1.id)!.toJson(), v2.toJson());
    final v3 = await repository.savePrompt(
      prompt: v2.copyWith(title: '第三版'),
      original: v2,
      profileId: ProfileScope.currentId,
    );
    expect(v3.version, 3);
  });

  for (final priorSelection in [false, true]) {
    test('部分写入失败恢复原值和缺失键，已有启用键=$priorSelection', () async {
      final key = PictureStoryRepository.enabledKeyFor(ProfileScope.currentId);
      if (priorSelection) {
        await HiveBoxes.settings.put(key, jsonEncode(['tidy-up-toys']));
      }
      final before = PictureStoryRepository().storageSnapshot();
      final repository = PictureStoryRepository(
        settings: _PartialWriteBox(HiveBoxes.settings),
      );
      await expectLater(
        repository.savePrompt(
          prompt: pictureStoryFixture(),
          profileId: ProfileScope.currentId,
        ),
        throwsStateError,
      );
      expect(PictureStoryRepository().storageSnapshot(), before);
      expect(repository.findPrompt('local-fixture'), isNull);
      final saved = await repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: ProfileScope.currentId,
      );
      expect(saved.id, 'local-fixture');
      expect(
        repository.catalogState().versions.map((p) => p.id),
        ['local-fixture'],
      );
    });
  }

  test('图片校验期间家长锁定不能发布题目', () async {
    final images = _WaitingImages();
    var allowed = true;
    final repository = PictureStoryRepository(
      images: images,
      authorize: () {
        if (!allowed) throw const ParentAccessDenied();
      },
    );
    final saving = repository.savePrompt(
      prompt: pictureStoryFixture(),
      profileId: ProfileScope.currentId,
    );
    final expectation = expectLater(saving, throwsA(isA<ParentAccessDenied>()));
    await images.reached.future;
    allowed = false;
    images.proceed.complete();
    await expectation;
    expect(repository.storageSnapshot(), isEmpty);
  });

  test('图片校验期间切换档案，晚到发布不会修改任一档案', () async {
    final images = _WaitingImages();
    final repository = PictureStoryRepository(images: images);
    final saving = repository.savePrompt(
      prompt: pictureStoryFixture(),
      profileId: ProfileScope.currentId,
    );
    final expectation = expectLater(saving, throwsFormatException);
    await images.reached.future;
    ProfileScope.switchTo('child-b');
    images.proceed.complete();
    await expectation;
    expect(repository.storageSnapshot(), isEmpty);
  });

  test('目录和启用 Provider 随仓储写入、版本及档案变化刷新', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pictureStoryPromptCountProvider), 3);
    final saved =
        await container.read(pictureStoryRepositoryProvider).savePrompt(
              prompt: pictureStoryFixture(),
              profileId: ProfileScope.currentId,
            );
    expect(
      container.read(pictureStoryCatalogProvider).last.toJson(),
      saved.toJson(),
    );
    expect(container.read(pictureStoryPromptCountProvider), 4);
    final updated =
        await container.read(pictureStoryRepositoryProvider).savePrompt(
              prompt: saved.copyWith(title: '新的观察题'),
              original: saved,
              profileId: ProfileScope.currentId,
            );
    expect(
      container.read(pictureStoryPromptByIdProvider(saved.id))!.toJson(),
      updated.toJson(),
    );
    ProfileScope.switchTo('child-b');
    expect(container.read(pictureStoryPromptCountProvider), 3);
    expect(
      container.read(pictureStoryCatalogProvider).last.toJson(),
      updated.toJson(),
    );
  });

  test('损坏目录保留原始值，禁止静默覆盖并拒绝发布', () async {
    await HiveBoxes.settings
        .put(PictureStoryRepository.catalogKey, '{bad-json');
    final repository = PictureStoryRepository();
    expect(repository.listPrompts, throwsFormatException);
    await expectLater(
      repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: ProfileScope.currentId,
      ),
      throwsFormatException,
    );
    expect(
      HiveBoxes.settings.get(PictureStoryRepository.catalogKey),
      '{bad-json',
    );
  });
}
