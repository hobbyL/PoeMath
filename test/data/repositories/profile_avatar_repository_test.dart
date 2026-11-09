import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/profile_avatar_camera_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/profile_avatar.dart';
import 'package:poemath/data/repositories/profile_avatar_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _FailOnceBox extends Fake implements Box<dynamic> {
  _FailOnceBox(this.inner);
  final Box<dynamic> inner;
  bool fail = true;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) {
      fail = false;
      throw StateError('write failed');
    }
    await inner.put(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileAvatar avatar;
  setUp(() async {
    await setUpHiveForTesting();
    avatar = ProfileAvatar(await pictureStoryPng(width: 256, height: 256));
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('并发保存不同档案不丢失，关闭重开 Hive 后仍能读取原图内容', () async {
    final repository = ProfileAvatarRepository();
    await Future.wait([
      repository.save('default', avatar),
      repository.save('child-2', avatar),
    ]);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = ProfileAvatarRepository();
    expect(reopened.read('default')!.bytes, avatar.bytes);
    expect(reopened.read('child-2')!.bytes, avatar.bytes);
    expect(reopened.read('child-3'), isNull);
  });

  test('保存失败保留原图，并允许再次保存', () async {
    await ProfileAvatarRepository().save('default', avatar);
    final original = HiveBoxes.settings.get(ProfileAvatar.settingsKey);
    final repository = ProfileAvatarRepository(
      settings: _FailOnceBox(HiveBoxes.settings),
    );
    await expectLater(repository.save('child-2', avatar), throwsStateError);
    expect(HiveBoxes.settings.get(ProfileAvatar.settingsKey), original);
    await repository.save('child-2', avatar);
    expect(repository.read('child-2')!.bytes, avatar.bytes);
  });

  test('头像真实导出恢复，旧备份缺失或坏图数据保留现有头像', () async {
    await unlockParentForTesting();
    final repository = ProfileAvatarRepository();
    await repository.save('default', avatar);
    await HiveBoxes.settings.put(
      ProfileAvatarCameraService.pendingKey,
      'default',
    );
    final backup = BackupService();
    final exported = await backup.exportToJson(includeCredentials: false);
    final data = jsonDecode(exported) as Map<String, dynamic>;
    final stored = HiveBoxes.settings.get(ProfileAvatar.settingsKey);
    expect((data['settings'] as Map)[ProfileAvatar.settingsKey], stored);
    expect(
      (data['settings'] as Map).containsKey(
        ProfileAvatarCameraService.pendingKey,
      ),
      isFalse,
    );
    await HiveBoxes.settings.delete(ProfileAvatar.settingsKey);
    await backup.restoreFromJson(exported);
    expect(repository.read('default')!.bytes, avatar.bytes);
    for (final settings in [
      <String, Object>{},
      {ProfileAvatar.settingsKey: '{"default":"bad image"}'},
    ]) {
      await backup.restoreFromJson(
        jsonEncode({'version': 1, 'settings': settings}),
      );
      expect(HiveBoxes.settings.get(ProfileAvatar.settingsKey), stored);
    }
  });

  test('损坏头像记录回退默认头像，模型拒绝无效格式', () async {
    await HiveBoxes.settings.put(ProfileAvatar.settingsKey, 'broken');
    expect(ProfileAvatarRepository().read('default'), isNull);
    expect(ProfileAvatar.accepts('{"default":true}'), isFalse);
    expect(
      ProfileAvatar.accepts(
        jsonEncode({
          'default': base64Encode([1, 2, 3]),
        }),
      ),
      isFalse,
    );
  });
}
