// lib/core/services/backup_credentials_cipher.dart
//
// 层级：core/services
// 职责：备份凭据节的加密 / 解密（PBKDF2 派生 + AES-256-GCM）。
// 纯函数、无平台依赖；备份 JSON 中凭据只允许以本模块的密文形态出现。

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// 备份 `credentials` 节的加密参数（写死的安全基线，写入备份供解密端校验）。
const String _kdfAlgorithm = 'pbkdf2-sha256';
const int _kdfIterations = 120000;
const String _cipherAlgorithm = 'aes-256-gcm';

/// 备份中凭据加密的明文载荷键（与 SecureCredentialStore 的存储键一致）。
const List<String> kBackupCredentialKeys = [
  'tencent_asr_secret_id',
  'tencent_asr_secret_key',
  'worker_tts_api_key',
  'llm_api_key',
];

/// 用口令加密凭据明文，产出备份 `credentials` 节的 JSON 结构。
///
/// [credentials] 只应包含 [kBackupCredentialKeys] 中存在且非空的项；
/// 空载荷应在上游直接省略本节。
Future<Map<String, dynamic>> encryptCredentials(
  Map<String, String> credentials,
  String passphrase,
) async {
  if (credentials.isEmpty) {
    throw ArgumentError('凭据载荷为空');
  }

  final salt = SecretKeyData.random(length: 16).bytes;
  final nonce = SecretKeyData.random(length: 12).bytes;

  final key = await _deriveKey(passphrase, salt, _kdfIterations);
  final cipher = AesGcm.with256bits();
  final secretBox = await cipher.encrypt(
    utf8.encode(jsonEncode(credentials)),
    secretKey: key,
    nonce: nonce,
  );

  return <String, dynamic>{
    'kdf': <String, dynamic>{
      'algorithm': _kdfAlgorithm,
      'iterations': _kdfIterations,
      'salt': base64Encode(salt),
    },
    'cipher': <String, dynamic>{
      'algorithm': _cipherAlgorithm,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(secretBox.concatenation()),
    },
  };
}

/// 解密备份 `credentials` 节。
///
/// 口令错误或数据被篡改时 AES-GCM 认证失败，抛 [FormatException]；
/// 结构不合法（算法不符、迭代数超界、base64 损坏）同样抛
/// [FormatException]。
Future<Map<String, String>> decryptCredentials(
  Map<String, dynamic> node,
  String passphrase,
) async {
  final kdf = node['kdf'];
  final cipherNode = node['cipher'];
  if (kdf is! Map<Object?, Object?> || cipherNode is! Map<Object?, Object?>) {
    throw const FormatException('备份凭据节结构无效');
  }

  final kdfAlgorithm = kdf['algorithm'];
  final iterations = kdf['iterations'];
  final saltB64 = kdf['salt'];
  if (kdfAlgorithm != _kdfAlgorithm ||
      iterations is! int ||
      iterations < 1000 ||
      iterations > 10000000 ||
      saltB64 is! String) {
    throw const FormatException('备份凭据节加密参数无效');
  }

  final cipherAlgorithm = cipherNode['algorithm'];
  final nonceB64 = cipherNode['nonce'];
  final ciphertextB64 = cipherNode['ciphertext'];
  if (cipherAlgorithm != _cipherAlgorithm ||
      nonceB64 is! String ||
      ciphertextB64 is! String) {
    throw const FormatException('备份凭据节加密参数无效');
  }

  final salt = _decodeBase64(saltB64, 'salt');
  final nonce = _decodeBase64(nonceB64, 'nonce');
  final combined = _decodeBase64(ciphertextB64, 'ciphertext');
  // combined = nonce(12) + cipherText + mac(16)，短于 28 必然结构损坏。
  if (nonce.length != 12 || combined.length < 28) {
    throw const FormatException('备份凭据节加密参数无效');
  }

  final key = await _deriveKey(passphrase, salt, iterations);
  final cipher = AesGcm.with256bits();
  final box = SecretBox.fromConcatenation(
    combined,
    nonceLength: 12,
    macLength: 16,
  );

  final List<int> clearBytes;
  try {
    clearBytes = await cipher.decrypt(box, secretKey: key);
  } on SecretBoxAuthenticationError {
    // 口令错误或密文被篡改：GCM 认证失败。
    throw const FormatException('备份加密口令错误或备份已损坏');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(clearBytes));
  } on FormatException {
    throw const FormatException('备份凭据节载荷无效');
  }
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('备份凭据节载荷无效');
  }

  final result = <String, String>{};
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (entry.key is! String ||
        value is! String ||
        !kBackupCredentialKeys.contains(entry.key)) {
      throw const FormatException('备份凭据节载荷无效');
    }
    result[entry.key as String] = value;
  }
  if (result.isEmpty) {
    throw const FormatException('备份凭据节载荷无效');
  }
  return result;
}

Future<SecretKey> _deriveKey(
  String passphrase,
  List<int> salt,
  int iterations,
) async {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  return kdf.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
}

List<int> _decodeBase64(String value, String field) {
  try {
    final decoded = base64Decode(value);
    if (decoded.isEmpty) throw const FormatException('空');
    return decoded;
  } on FormatException {
    throw FormatException('备份凭据节 $field 编码无效');
  }
}
