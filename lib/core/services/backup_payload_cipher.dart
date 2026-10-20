import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int maxBackupBytes = 32 * 1024 * 1024;
const String _format = 'poemath-encrypted-backup';
const int _iterations = 120000;

void validateBackupSize(String json) {
  if (json.length > maxBackupBytes ||
      utf8.encode(json).length > maxBackupBytes) {
    throw const FormatException('备份超过 32 MiB，请缩减聊天历史后再导出');
  }
}

Object? decodeBackupJson(String json) {
  validateBackupSize(json);
  return jsonDecode(json);
}

Future<String> readBackupFile(File file) async {
  if (await file.length() > maxBackupBytes) {
    throw const FormatException('备份超过允许大小');
  }
  var count = 0;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    count += chunk.length;
    if (count > maxBackupBytes) throw const FormatException('备份超过允许大小');
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

bool isEncryptedBackup(String json) {
  validateBackupSize(json);
  final value = jsonDecode(json);
  // A damaged envelope must never fall back to destructive legacy restore.
  return value is Map && ['format', 'kdf', 'ciphertext'].any(value.containsKey);
}

List<int> _aad(Map<String, dynamic> node) => utf8.encode(
      jsonEncode([
        node['format'],
        node['version'],
        node['exportedAt'],
        node['kdf'],
      ]),
    );

Future<String> encryptBackupPayload(
  String json, {
  String? passphrase,
  SecretKey? deviceKey,
}) async {
  validateBackupSize(json);
  final value = jsonDecode(json) as Map<String, dynamic>;
  final node = <String, dynamic>{
    'format': _format,
    // Old clients reject this version before clearing any collections.
    'version': 2,
    'exportedAt': value['exportedAt'],
  };
  final SecretKey key;
  if (deviceKey != null) {
    key = deviceKey;
    node['kdf'] = {'algorithm': 'device-key'};
  } else {
    if (passphrase == null || passphrase.trim().isEmpty) {
      throw ArgumentError('加密备份口令不能为空');
    }
    final salt = SecretKeyData.random(length: 16).bytes;
    node['kdf'] = {
      'algorithm': 'pbkdf2-sha256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
    };
    key = await _derive(passphrase.trim(), salt);
  }
  final box = await AesGcm.with256bits()
      .encrypt(utf8.encode(json), secretKey: key, aad: _aad(node));
  node['ciphertext'] = base64Encode(box.concatenation());
  final encrypted = jsonEncode(node);
  validateBackupSize(encrypted);
  return encrypted;
}

Future<String> decryptBackupPayload(
  String json, {
  String? passphrase,
  SecretKey? deviceKey,
}) async {
  validateBackupSize(json);
  final node = jsonDecode(json);
  if (node is! Map<String, dynamic> ||
      node['format'] != _format ||
      node['version'] != 2) {
    throw const FormatException('加密备份格式无效');
  }
  final kdf = node['kdf'];
  final ciphertext = node['ciphertext'];
  if (kdf is! Map || ciphertext is! String) {
    throw const FormatException('加密备份参数无效');
  }
  final SecretKey key;
  try {
    if (kdf['algorithm'] == 'device-key' && deviceKey != null) {
      key = deviceKey;
    } else if (kdf['algorithm'] == 'pbkdf2-sha256' &&
        kdf['iterations'] == _iterations &&
        kdf['salt'] is String) {
      final saltText = kdf['salt'] as String;
      if (saltText.length != 24 ||
          passphrase == null ||
          passphrase.trim().isEmpty) {
        throw const FormatException('请输入备份加密口令');
      }
      final salt = base64Decode(saltText);
      if (salt.length != 16) throw const FormatException('加密备份盐长度无效');
      key = await _derive(passphrase.trim(), salt);
    } else {
      throw const FormatException('加密备份参数无效或本机密钥不可用');
    }
    final combined = base64Decode(ciphertext);
    if (combined.length < 28) throw const FormatException('加密备份已损坏');
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox.fromConcatenation(combined, nonceLength: 12, macLength: 16),
      secretKey: key,
      aad: _aad(node),
    );
    final result = utf8.decode(clear);
    validateBackupSize(result);
    return result;
  } on SecretBoxAuthenticationError {
    throw const FormatException('备份加密口令错误或备份已损坏');
  }
}

Future<SecretKey> _derive(String passphrase, List<int> salt) => Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
