import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/profile_nickname.dart';
import 'package:poemath/data/repositories/profile_nickname_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _FailOnceBox extends Fake implements Box<dynamic> {
  _FailOnceBox(this.delegate);
  final Box<dynamic> delegate;
  bool fail = true;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) {
      fail = false;
      throw HiveError('write failed');
    }
    await delegate.put(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpHiveForTesting);
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('不同仓储并发保存按档案隔离，重开后仍保留昵称', () async {
    await Future.wait([
      ProfileNicknameRepository().save('default', '  小月亮  '),
      ProfileNicknameRepository().save('child-b', '小太阳🌞'),
    ]);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = ProfileNicknameRepository();
    expect(reopened.read('default'), '小月亮');
    expect(reopened.read('child-b'), '小太阳🌞');
    expect(reopened.read('child-c'), isNull);
  });

  test('昵称按可见字符限制，非法输入与失败写入不覆盖原值，重试可保存', () async {
    final repository = ProfileNicknameRepository();
    await repository.save('default', '原昵称');
    final original = HiveBoxes.settings.get(ProfileNickname.settingsKey);
    for (final name in ['   ', '第一行\n第二行', List.filled(21, '字').join()]) {
      await expectLater(
        repository.save('default', name),
        throwsFormatException,
      );
      expect(HiveBoxes.settings.get(ProfileNickname.settingsKey), original);
    }
    final failing = ProfileNicknameRepository(
      settings: _FailOnceBox(HiveBoxes.settings),
    );
    await expectLater(
      failing.save('default', '新昵称'),
      throwsA(isA<HiveError>()),
    );
    expect(repository.read('default'), '原昵称');
    final emojiName = List.filled(20, '👨‍👩‍👧').join();
    await failing.save('default', emojiName);
    expect(repository.read('default'), emojiName);
  });

  test('昵称备份真实往返恢复，旧备份缺键或非法昵称保留现有值', () async {
    await unlockParentForTesting();
    final repository = ProfileNicknameRepository();
    await repository.save('default', '小月亮');
    await repository.save('child-b', '小太阳');
    final backup = BackupService();
    final exported = await backup.exportToJson(includeCredentials: false);
    final data = jsonDecode(exported) as Map<String, dynamic>;
    expect(
      (data['settings'] as Map)[ProfileNickname.settingsKey],
      '{"default":"小月亮","child-b":"小太阳"}',
    );
    await HiveBoxes.settings.delete(ProfileNickname.settingsKey);
    await backup.restoreFromJson(exported);
    expect(repository.read('default'), '小月亮');
    expect(repository.read('child-b'), '小太阳');
    for (final settings in [
      <String, Object>{},
      {ProfileNickname.settingsKey: '{"default":""}'},
      {ProfileNickname.settingsKey: '{"default":123}'},
    ]) {
      await backup.restoreFromJson(
        jsonEncode({'version': 1, 'settings': settings}),
      );
      expect(repository.read('default'), '小月亮');
      expect(repository.read('child-b'), '小太阳');
    }
  });

  test('损坏的本机昵称只读回退，不在读取时修改记录', () async {
    await HiveBoxes.settings.put(ProfileNickname.settingsKey, 'broken');
    expect(ProfileNicknameRepository().read('default'), isNull);
    expect(HiveBoxes.settings.get(ProfileNickname.settingsKey), 'broken');
    expect(ProfileNickname.accepts('{"":"昵称"}'), isFalse);
    expect(ProfileNickname.accepts('{"default":"昵称"}'), isTrue);
  });
}
