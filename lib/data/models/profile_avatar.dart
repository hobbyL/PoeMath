import 'dart:convert';
import 'dart:typed_data';

/// 头像保存压缩后的 PNG 内容，不依赖系统选图返回的临时路径。
class ProfileAvatar {
  ProfileAvatar(Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    _validate(this.bytes);
  }

  static const settingsKey = 'profile_avatars';
  static const dimension = 256;
  static const maxBytes = 384 * 1024;
  static const _maxProfiles = 32;
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  final Uint8List bytes;

  static void _validate(Uint8List bytes) {
    if (bytes.length < 33 || bytes.length > maxBytes) {
      throw const FormatException('头像图片大小无效');
    }
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) {
        throw const FormatException('头像图片格式无效');
      }
    }
    final data = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR' ||
        data.getUint32(16) != dimension ||
        data.getUint32(20) != dimension) {
      throw const FormatException('头像图片尺寸无效');
    }
  }

  static Map<String, ProfileAvatar> decodeProfiles(Object? raw) {
    if (raw == null) return {};
    if (raw is! String || raw.length > _maxProfiles * maxBytes * 2) {
      throw const FormatException('头像记录无效');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded.length > _maxProfiles) {
      throw const FormatException('头像记录无效');
    }
    final profiles = <String, ProfileAvatar>{};
    for (final entry in decoded.entries) {
      final encoded = entry.value;
      if (entry.key.isEmpty ||
          entry.key.length > 128 ||
          encoded is! String ||
          encoded.length > maxBytes * 2) {
        throw const FormatException('头像记录无效');
      }
      profiles[entry.key] = ProfileAvatar(base64Decode(encoded));
    }
    return profiles;
  }

  static String encodeProfiles(Map<String, ProfileAvatar> profiles) =>
      jsonEncode({
        for (final entry in profiles.entries)
          entry.key: base64Encode(entry.value.bytes),
      });

  static bool accepts(Object value) {
    try {
      decodeProfiles(value);
      return true;
    } on FormatException {
      return false;
    }
  }
}
