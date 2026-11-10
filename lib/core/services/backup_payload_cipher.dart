import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

const String _format = 'poemath-encrypted-backup';
const int _iterations = 120000;

/// 逐块解码完整备份，避免先累积整份字节再复制为字符串。
Future<String> readBackupFile(File file) =>
    file.openRead().transform(utf8.decoder).join();

bool isEncryptedBackup(String json) {
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
  final keyBytes = await deviceKey?.extractBytes();
  return _runEncryption(json, passphrase, keyBytes);
}

// Only immutable input crosses this boundary; no storage/plugin objects or
// caller closures are captured. JSON/Base64 and crypto all run off the UI loop.
Future<String> _runEncryption(
  String json,
  String? passphrase,
  List<int>? keyBytes,
) => Isolate.run(
  () => _encryptBackupPayload(
    json,
    passphrase: passphrase,
    deviceKey: keyBytes == null ? null : SecretKey(keyBytes),
  ),
);

Future<String> _encryptBackupPayload(
  String json, {
  String? passphrase,
  SecretKey? deviceKey,
}) async {
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
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(json),
    secretKey: key,
    aad: _aad(node),
  );
  node['ciphertext'] = base64Encode(box.concatenation());
  return jsonEncode(node);
}

Future<String> decryptBackupPayload(
  String json, {
  String? passphrase,
  SecretKey? deviceKey,
}) async {
  final keyBytes = await deviceKey?.extractBytes();
  return _runDecryption(json, passphrase, keyBytes);
}

Future<String> _runDecryption(
  String json,
  String? passphrase,
  List<int>? keyBytes,
) => Isolate.run(
  () => _decryptBackupPayload(
    json,
    passphrase: passphrase,
    deviceKey: keyBytes == null ? null : SecretKey(keyBytes),
  ),
);

Future<String> _decryptBackupPayload(
  String json, {
  String? passphrase,
  SecretKey? deviceKey,
}) async {
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
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw const FormatException('备份加密口令错误或备份已损坏');
  }
}

Future<SecretKey> _derive(String passphrase, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: _iterations,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
