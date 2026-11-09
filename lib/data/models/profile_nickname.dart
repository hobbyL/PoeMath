import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

/// 昵称与档案绑定；本机读取、编辑和备份导入使用相同的校验规则。
class ProfileNickname {
  const ProfileNickname._();

  static const settingsKey = 'profile_nicknames';
  static const defaultName = '小小学习家';
  static const maxLength = 20;
  static const _maxProfiles = 32;
  static final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]');

  static String normalize(String value) {
    final name = value.trim();
    if (name.isEmpty) throw const FormatException('请输入昵称');
    if (name.length > 256 || name.characters.length > maxLength) {
      throw const FormatException('昵称最多 20 个字');
    }
    if (_controls.hasMatch(name)) {
      throw const FormatException('昵称不能包含换行或控制字符');
    }
    return name;
  }

  static Map<String, String> decodeProfiles(Object? raw) {
    if (raw == null) return {};
    if (raw is! String || raw.length > 128 * 1024) {
      throw const FormatException('昵称记录无效');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded.length > _maxProfiles) {
      throw const FormatException('昵称记录无效');
    }
    final names = <String, String>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (entry.key.isEmpty || entry.key.length > 128 || value is! String) {
        throw const FormatException('昵称记录无效');
      }
      names[entry.key] = normalize(value);
    }
    return names;
  }

  static String encodeProfiles(Map<String, String> names) => jsonEncode(names);

  static bool accepts(Object value) {
    try {
      decodeProfiles(value);
      return true;
    } on FormatException {
      return false;
    }
  }
}
