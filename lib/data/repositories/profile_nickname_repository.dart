import 'package:hive/hive.dart';

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/profile_nickname.dart';

class ProfileNicknameRepository {
  ProfileNicknameRepository({Box<dynamic>? settings})
    : _settingsOverride = settings;

  final Box<dynamic>? _settingsOverride;
  Box<dynamic> get _settings => _settingsOverride ?? HiveBoxes.settings;
  static Future<void> _writes = Future.value();

  Stream<void> get changes =>
      _settings.watch(key: ProfileNickname.settingsKey).map((_) {});

  Map<String, String> _readProfiles() => ProfileNickname.decodeProfiles(
    _settings.get(ProfileNickname.settingsKey),
  );

  String? read(String profileId) {
    try {
      return _readProfiles()[profileId];
    } on FormatException {
      // 不记录用户输入的昵称内容。
      AppLogger.w('昵称记录无法读取，使用默认昵称', tag: 'ProfileNickname');
      return null;
    }
  }

  Future<void> save(String profileId, String value) {
    final write = _writes.then((_) async {
      final name = ProfileNickname.normalize(value);
      final names = _readProfiles()..[profileId] = name;
      final encoded = ProfileNickname.encodeProfiles(names);
      if (!ProfileNickname.accepts(encoded)) {
        throw const FormatException('昵称记录无法保存');
      }
      await _settings.put(ProfileNickname.settingsKey, encoded);
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
