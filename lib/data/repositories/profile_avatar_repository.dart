import 'package:hive/hive.dart';

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/profile_avatar.dart';

class ProfileAvatarRepository {
  ProfileAvatarRepository({Box<dynamic>? settings})
    : _settingsOverride = settings;

  final Box<dynamic>? _settingsOverride;
  Box<dynamic> get _settings => _settingsOverride ?? HiveBoxes.settings;
  Future<void> _writes = Future.value();

  Stream<void> get changes =>
      _settings.watch(key: ProfileAvatar.settingsKey).map((_) {});

  ProfileAvatar? read(String profileId) {
    try {
      return _readProfiles()[profileId];
    } on FormatException catch (error) {
      AppLogger.w('头像记录无法读取，使用默认头像：$error', tag: 'ProfileAvatar');
      return null;
    }
  }

  Map<String, ProfileAvatar> _readProfiles() =>
      ProfileAvatar.decodeProfiles(_settings.get(ProfileAvatar.settingsKey));

  Future<void> save(String profileId, ProfileAvatar avatar) {
    final write = _writes.then((_) async {
      final profiles = _readProfiles()..[profileId] = avatar;
      final encoded = ProfileAvatar.encodeProfiles(profiles);
      if (!ProfileAvatar.accepts(encoded)) {
        throw const FormatException('头像记录无法保存');
      }
      await _settings.put(ProfileAvatar.settingsKey, encoded);
    });
    // 保留本次错误给调用者，下一次重试不被失败的写链阻断。
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
