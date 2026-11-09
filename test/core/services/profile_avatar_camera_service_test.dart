import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/services/profile_avatar_camera_service.dart';
import 'package:poemath/core/services/profile_avatar_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/profile_avatar.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/repositories/profile_avatar_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File photo;
  late ProfileAvatar oldAvatar;
  late ProfileAvatarRepository repository;
  const pendingKey = ProfileAvatarCameraService.pendingKey;

  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    directory = await Directory.systemTemp.createTemp('avatar_camera_');
    photo = File('${directory.path}/photo.png');
    await photo.writeAsBytes(await pictureStoryPng(width: 720, height: 480));
    oldAvatar = ProfileAvatar(await pictureStoryPng(width: 256, height: 256));
    repository = ProfileAvatarRepository();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  test('启动拍照前记录所属档案，导入完成后清除标记并释放缓存保护', () async {
    await repository.save('other-child', oldAvatar);
    final source = await photo.readAsBytes();
    final service = ProfileAvatarCameraService(
      repository: repository,
      images: ProfileAvatarImageService(
        capturePath: () async {
          expect(HiveBoxes.settings.get(pendingKey), 'child-a');
          await expectLater(
            CacheActivity.clear(TemporaryCacheKind.pickers, () async {}),
            throwsA(isA<CacheInUseException>()),
          );
          return photo.path;
        },
      ),
    );
    await service.capture('child-a');
    expect(
      repository.read('child-a')!.bytes,
      (await ProfileAvatarImageService.normalize(source)).bytes,
    );
    expect(repository.read('other-child')!.bytes, oldAvatar.bytes);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
    expect(await photo.readAsBytes(), source);
    await CacheActivity.clear(TemporaryCacheKind.pickers, () async {});
  });

  test('取消和权限失败保留原头像，清除恢复标记后仍可重试', () async {
    await repository.save('default', oldAvatar);
    var attempt = 0;
    final service = ProfileAvatarCameraService(
      repository: repository,
      images: ProfileAvatarImageService(
        capturePath: () async {
          switch (attempt++) {
            case 0:
              return null;
            case 1:
              throw PlatformException(code: 'camera_access_denied');
            default:
              return photo.path;
          }
        },
      ),
    );
    await service.capture('default');
    expect(repository.read('default')!.bytes, oldAvatar.bytes);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
    await expectLater(
      service.capture('default'),
      throwsA(isA<PlatformException>()),
    );
    expect(repository.read('default')!.bytes, oldAvatar.bytes);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
    await service.capture('default');
    expect(
      repository.read('default')!.bytes,
      (await ProfileAvatarImageService().importPath(photo.path)).bytes,
    );
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
  });

  test('重启后的拍照结果恢复到原档案，不受当前档案切换影响且仅恢复一次', () async {
    await repository.save('other-child', oldAvatar);
    await HiveBoxes.settings.put(pendingKey, 'child-a');
    await HiveBoxes.close();
    await HiveBoxes.init();
    ProfileScope.switchTo('other-child');
    var recoveries = 0;
    final service = ProfileAvatarCameraService(
      supportsLostData: true,
      recoverPath: () async {
        recoveries++;
        return photo.path;
      },
    );
    await service.recoverPending();
    await service.recoverPending();
    expect(recoveries, 1);
    expect(
      repository.read('child-a')!.bytes,
      (await ProfileAvatarImageService().importPath(photo.path)).bytes,
    );
    expect(repository.read('other-child')!.bytes, oldAvatar.bytes);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
  });

  test('没有头像恢复标记时不消费原生缓存，损坏标记不能误恢复成题图', () async {
    var recoveries = 0;
    final service = ProfileAvatarCameraService(
      supportsLostData: true,
      recoverPath: () async {
        recoveries++;
        return photo.path;
      },
    );
    await service.recoverPending();
    expect(recoveries, 0);
    await HiveBoxes.settings.put(pendingKey, 123);
    await service.recoverPending();
    expect(recoveries, 1);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
    expect(repository.read('default'), isNull);
  });

  test('不同服务实例共享拍照保护，题图恢复等待当前头像拍照保存完成', () async {
    final reached = Completer<void>();
    final result = Completer<String?>();
    final service = ProfileAvatarCameraService(
      images: ProfileAvatarImageService(
        capturePath: () {
          reached.complete();
          return result.future;
        },
      ),
    );
    final capture = service.capture('default');
    await reached.future;
    var entered = false;
    final recovery = ProfileAvatarCameraService().withRecovery(() async {
      entered = true;
      expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
      expect(repository.read('default'), isNotNull);
    });
    await Future<void>.delayed(Duration.zero);
    expect(entered, isFalse);
    result.complete(photo.path);
    await Future.wait([capture, recovery]);
    expect(entered, isTrue);
  });

  test('启动时头像先取回自己的照片，题目草稿不会接到头像照片', () async {
    final draft = PictureStoryEditorDraft.create(
      id: 'local-pending',
      profileId: 'default',
      original: pictureStoryFixture(),
    ).copyWith(pendingRequest: 'pick-pending');
    await HiveBoxes.settings.put(
      PictureStoryEditorService.draftKey,
      draft.encode(),
    );
    await HiveBoxes.settings.put(pendingKey, 'default');
    var consumed = false;
    Future<String?> recover() async {
      if (consumed) return null;
      consumed = true;
      return photo.path;
    }

    final editor = PictureStoryEditorService(
      images: PictureStoryImageService(
        directoryProvider: () async => directory,
      ),
      avatarCamera: ProfileAvatarCameraService(
        supportsLostData: true,
        recoverPath: recover,
      ),
      supportsLostData: true,
      recoverPath: recover,
    );
    addTearDown(editor.dispose);
    await editor.recoverLostImage();
    expect(repository.read('default'), isNotNull);
    expect(editor.readDraft()!.image, draft.image);
    expect(editor.readDraft()!.fields, draft.fields);
    expect(editor.readDraft()!.pendingRequest, isNull);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
  });

  test('头像恢复异常不会污染题图，也不会阻断随后重新选图', () async {
    await repository.save('default', oldAvatar);
    await HiveBoxes.settings.put(pendingKey, 'default');
    var editorRecoveryCalls = 0;
    final editor = PictureStoryEditorService(
      images: PictureStoryImageService(
        directoryProvider: () async => directory,
      ),
      avatarCamera: ProfileAvatarCameraService(
        supportsLostData: true,
        recoverPath: () async => throw StateError('recovery failed'),
      ),
      supportsLostData: true,
      recoverPath: () async {
        editorRecoveryCalls++;
        return photo.path;
      },
      pickPath: (_) async => photo.path,
    );
    addTearDown(editor.dispose);
    await editor.recoverLostImage();
    expect(editorRecoveryCalls, 0);
    expect(repository.read('default')!.bytes, oldAvatar.bytes);
    expect(HiveBoxes.settings.containsKey(pendingKey), isFalse);
    final draft = editor.openDraft(original: pictureStoryFixture());
    await editor.chooseImage(draft, PictureStoryImageSource.file);
    expect(editor.readDraft()!.image!.isLocal, isTrue);
    expect(editor.readDraft()!.fields, draft.fields);
    expect(editor.readDraft()!.message, isNull);
    expect(editor.isPicking, isFalse);
  });
}
