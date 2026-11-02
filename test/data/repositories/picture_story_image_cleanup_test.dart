import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _FailingCleanupImages extends PictureStoryImageService {
  _FailingCleanupImages({required super.directoryProvider});
  bool failNext = true;

  @override
  Future<void> removeUnreferenced(
    Set<String> retainedIds, {
    required void Function() authorize,
  }) async {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('模拟题图清理失败');
    }
    await super.removeUnreferenced(retainedIds, authorize: authorize);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PictureStoryImageService images;
  late PictureStoryRepository repository;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    directory = await Directory.systemTemp.createTemp('picture-image-cleanup-');
    images = PictureStoryImageService(directoryProvider: () async => directory);
    repository = PictureStoryRepository(images: images);
  });
  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  Future<PictureStoryImage> image(int width) =>
      pictureStoryPng(width: width).then(images.importBytes);

  Future<PictureStoryPrompt> publish(String id, PictureStoryImage image) =>
      repository.savePrompt(
        prompt: pictureStoryFixture(id: id, image: image),
        profileId: 'default',
      );

  Future<void> practice(
    PictureStoryPrompt prompt, {
    required String profile,
    String status = 'completed',
  }) async {
    ProfileScope.switchTo(profile);
    await repository.save(
      PictureStoryPracticeRecord(
        id: '$profile-history',
        profileId: profile,
        promptId: prompt.id,
        promptVersion: prompt.version,
        startedAt: DateTime(2026),
        status: status,
        segmentsJson: '[]',
        answerText: '$profile 已保存的表达',
      ),
    );
    ProfileScope.reset();
  }

  test('没有练习引用的题目删除实际题图，重开保留删除状态，晚到练习不能新增引用', () async {
    final picture = await image(4);
    final prompt = await publish('local-unused', picture);
    final path = (await images.imagePath(picture.value))!;
    await repository.deletePrompt(prompt: prompt, profileId: 'default');
    expect(await File(path).exists(), isFalse);
    expect((await images.storageUsage()).entries, 0);
    await HiveBoxes.close();
    await HiveBoxes.init();
    repository = PictureStoryRepository(images: images);
    expect(repository.catalogState().versions, isEmpty);
    expect(repository.catalogState().deletedIds, {prompt.id});
    expect(repository.findPrompt(prompt.id), isNull);
    await expectLater(
      practice(prompt, profile: 'default'),
      throwsFormatException,
    );
    expect(HiveBoxes.pictureStoryPractice.values, isEmpty);
  });

  test('所有孩子的历史和未完成练习保留精确版本与题图，无引用的中间版本释放', () async {
    final firstImage = await image(4);
    final secondImage = await image(5);
    final thirdImage = await image(6);
    final first = await publish('local-versions', firstImage);
    final second = await repository.savePrompt(
      prompt: first.copyWith(title: '第二版', image: secondImage),
      original: first,
      profileId: 'default',
    );
    final third = await repository.savePrompt(
      prompt: second.copyWith(title: '第三版', image: thirdImage),
      original: second,
      profileId: 'default',
    );
    await practice(first, profile: 'child-a', status: 'draft');
    await practice(third, profile: 'child-b');
    final audio = File('${directory.path}/picture_story_audio/practice.wav');
    await audio.parent.create();
    await audio.writeAsString('saved recording');
    await repository.deletePrompt(prompt: third, profileId: 'default');
    expect(repository.catalogState().versions.map((p) => p.version), [1, 3]);
    expect(
      repository.findPrompt(first.id, version: 1)!.toJson(),
      first.toJson(),
    );
    expect(repository.findPrompt(first.id, version: 2), isNull);
    expect(
      repository.findPrompt(first.id, version: 3)!.toJson(),
      third.toJson(),
    );
    expect(await images.imagePath(firstImage.value), isNotNull);
    expect(await images.imagePath(secondImage.value), isNull);
    expect(await images.imagePath(thirdImage.value), isNotNull);
    expect(
      HiveBoxes.pictureStoryPractice.values.map((r) => r.status).toSet(),
      {'draft', 'completed'},
    );
    expect(await audio.readAsString(), 'saved recording');
    await HiveBoxes.close();
    await HiveBoxes.init();
    repository = PictureStoryRepository(images: images);
    expect(repository.catalogState().versions.map((p) => p.version), [1, 3]);
    ProfileScope.switchTo('child-b');
    expect(repository.records().single.answerText, 'child-b 已保存的表达');
    ProfileScope.switchTo('child-a');
    expect(repository.find('child-a-history')!.promptVersion, 1);
  });

  test('共用题图只在最后一道题删除且没有历史引用时释放', () async {
    final shared = await image(4);
    final first = await publish('local-first', shared);
    final second = await publish('local-second', shared);
    expect((await images.storageUsage()).entries, 1);
    await repository.deletePrompt(prompt: first, profileId: 'default');
    expect(await images.readImage(shared.value), isNotEmpty);
    expect(repository.findPrompt(second.id), isNotNull);
    await repository.deletePrompt(prompt: second, profileId: 'default');
    expect(await images.imagePath(shared.value), isNull);
    expect(repository.catalogState().deletedIds, {first.id, second.id});
  });

  test('题图清理失败如实报告目录已删除，保留剩余文件且重试不复活题目', () async {
    final picture = await image(4);
    final prompt = await publish('local-cleanup-retry', picture);
    final failing =
        _FailingCleanupImages(directoryProvider: () async => directory);
    repository = PictureStoryRepository(images: failing);
    await expectLater(
      repository.deletePrompt(prompt: prompt, profileId: 'default'),
      throwsA(
        isA<PictureStoryImageCleanupException>().having(
          (error) => error.cause,
          'cause',
          isA<FileSystemException>(),
        ),
      ),
    );
    expect(repository.findPrompt(prompt.id), isNull);
    expect(repository.catalogState().deletedIds, {prompt.id});
    expect(await images.imagePath(picture.value), isNotNull);
    await repository.deletePrompt(prompt: prompt, profileId: 'default');
    expect(await images.imagePath(picture.value), isNull);
    expect(repository.findPrompt(prompt.id), isNull);
  });

  test('练习排队写入保留调用时的文字副本，不能通过切换档案写入错误的键', () async {
    final gate = Completer<void>();
    final blocking = PictureStoryRepository.exclusive(() => gate.future);
    final record = PictureStoryPracticeRecord(
      id: 'queued-record',
      profileId: 'default',
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026),
      status: 'draft',
      segmentsJson: '[]',
      answerText: '开始保存时的表达',
    );
    final saving = repository.save(record);
    record.answerText = '排队期间修改的表达';
    gate.complete();
    await blocking;
    await saving;
    expect(repository.find(record.id)!.answerText, '开始保存时的表达');

    final nextGate = Completer<void>();
    final nextBlock = PictureStoryRepository.exclusive(() => nextGate.future);
    final mismatched = PictureStoryPracticeRecord(
      id: record.id,
      profileId: 'child-b',
      promptId: record.promptId,
      promptVersion: record.promptVersion,
      startedAt: record.startedAt,
      status: 'draft',
      segmentsJson: '[]',
    );
    final denied = expectLater(repository.save(mismatched), throwsStateError);
    ProfileScope.switchTo('child-b');
    nextGate.complete();
    await nextBlock;
    await denied;
    expect(repository.find(record.id), isNull);
    ProfileScope.reset();
    expect(repository.find(record.id)!.profileId, 'default');
    expect(repository.find(record.id)!.answerText, '开始保存时的表达');
  });

  test('编辑草稿原图、新图和其他孩子的 AI 草稿题图均保留，放弃引用后可回收', () async {
    final originalImage = await image(4);
    final editingImage = await image(5);
    final generatedImage = await image(6);
    final orphan = await image(7);
    final prompt = await publish('local-editing', originalImage);
    final editor = PictureStoryEditorDraft.create(
      id: prompt.id,
      profileId: 'default',
      original: prompt,
    ).copyWith(image: editingImage);
    await HiveBoxes.settings
        .put(PictureStoryEditorDraft.storageKey, editor.encode());
    final generation = PictureStoryGenerationDraft(
      id: 'batch-1',
      profileId: 'child-b',
      options: PictureStoryGenerationOptions(
        level: PictureStoryLevel.starter,
        count: 1,
        themes: const ['日常生活'],
      ),
      candidates: [
        PictureStoryGenerationCandidate(
          edit: PictureStoryEditorDraft.create(
            id: 'local-generated',
            profileId: 'child-b',
          ).copyWith(image: generatedImage),
          imagePrompt: '孩子在公园里看花',
          requestId: 'request-1',
          stage: PictureStoryGenerationStage.imageReady,
        ),
      ],
    );
    final generationKey = 'child-b${PictureStoryGenerationDraft.storageSuffix}';
    await HiveBoxes.settings.put(generationKey, generation.encode());
    await repository.deletePrompt(prompt: prompt, profileId: 'default');
    for (final picture in [originalImage, editingImage, generatedImage]) {
      expect(await images.imagePath(picture.value), isNotNull);
    }
    expect(await images.imagePath(orphan.value), isNull);
    expect((await images.storageUsage()).entries, 3);
    await HiveBoxes.settings
        .deleteAll([PictureStoryEditorDraft.storageKey, generationKey]);
    await repository.deletePrompt(prompt: prompt, profileId: 'default');
    expect((await images.storageUsage()).entries, 0);
  });

  for (final draftKey in [
    PictureStoryEditorDraft.storageKey,
    'child-b${PictureStoryGenerationDraft.storageSuffix}',
  ]) {
    test('无法读取草稿引用时拒绝删除，原题和题图均保留：$draftKey', () async {
      final picture = await image(4);
      final prompt = await publish('local-corrupt-draft', picture);
      await HiveBoxes.settings.put(draftKey, '{');
      final before = repository.storageSnapshot();
      await expectLater(
        repository.deletePrompt(prompt: prompt, profileId: 'default'),
        throwsFormatException,
      );
      expect(repository.storageSnapshot(), before);
      expect(repository.findPrompt(prompt.id), isNotNull);
      expect(await images.readImage(picture.value), isNotEmpty);
    });
  }

  test('schema 3 只允许已删除题目保留稀疏版本，旧格式仍校验连续性和删除标记', () {
    final prompt =
        pictureStoryFixture(image: PictureStoryImage.local('a' * 64));
    final sparse = PictureStoryCatalogState(
      [prompt.copyWith(version: 3)],
      deletedIds: [prompt.id],
    ).toJson();
    expect(
      PictureStoryCatalogState.fromJson(sparse).versions.single.version,
      3,
    );
    for (final version in [1, 2]) {
      expect(
        () => PictureStoryCatalogState.fromJson(
          {...sparse, 'schemaVersion': version},
        ),
        throwsFormatException,
      );
    }
    expect(
      () => PictureStoryCatalogState.fromJson(
        {...sparse, 'deletedIds': <String>[]},
      ),
      throwsFormatException,
    );
    expect(
      () => PictureStoryCatalogState.fromJson({
        ...sparse,
        'versions': [
          ...sparse['versions'] as List,
          ...sparse['versions'] as List,
        ],
      }),
      throwsFormatException,
    );
    final markerOnly =
        PictureStoryCatalogState([], deletedIds: [prompt.id]).toJson();
    expect(
      PictureStoryCatalogState.fromJson(markerOnly).deletedIds,
      {prompt.id},
    );
    expect(
      () => PictureStoryCatalogState.fromJson(
        {...markerOnly, 'schemaVersion': 2},
      ),
      throwsFormatException,
    );
  });
}
