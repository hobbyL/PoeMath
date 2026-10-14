// lib/core/services/backup_credentials_cipher.dart
//
// 层级：core/services
// 职责：备份凭据节的加密 / 解密（PBKDF2 派生 + AES-256-GCM）。
// 纯函数、无平台依赖；备份 JSON 中凭据只允许以本模块的密文形态出现。

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'package:poemath/core/utils/logger.dart';

/// 备份 `credentials` 节的加密参数（写死的安全基线，写入备份供解密端校验）。
const String _kdfAlgorithm = 'pbkdf2-sha256';
const int _kdfIterations = 120000;
const String _cipherAlgorithm = 'aes-256-gcm';

/// 备份凭据明文载荷的键名 —— **单一来源**，生产端与消费端都必须引用这里。
///
/// 这些是**备份 JSON 内部**的 payload 键，与 [SecureCredentialStore] 的存储键
/// 没有耦合：恢复端经 `saveTencentAsrCredentials` / `saveWorkerTtsApiKey` 等
/// 方法写入安全存储，不按键直写，两套名字恰好同名纯属巧合。改这里不会影响
/// 已存在设备上的凭据，但**会影响跨版本备份的可读性** —— 见
/// [decryptCredentials] 对未知键的处理。
const String kCredKeyTencentSecretId = 'tencent_asr_secret_id';
const String kCredKeyTencentSecretKey = 'tencent_asr_secret_key';
const String kCredKeyWorkerTtsApiKey = 'worker_tts_api_key';
const String kCredKeyLlmApiKey = 'llm_api_key';
const String kCredKeyLlmApiKeyHint = 'llm_api_key_hint';

/// 本版本可识别的全部载荷键。
///
/// 新增凭据键时只需在上面加常量并补进本表，生产端（`BackupService`
/// `_exportCredentials`）与消费端（`_restoreCredentials`）引用常量即可，
/// 不再有字面量副本各自漂移的空间。
const List<String> kBackupCredentialKeys = [
  kCredKeyTencentSecretId,
  kCredKeyTencentSecretKey,
  kCredKeyWorkerTtsApiKey,
  kCredKeyLlmApiKey,
  kCredKeyLlmApiKeyHint,
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
  final skipped = <String>[];
  for (final entry in decoded.entries) {
    final key = entry.key;
    final value = entry.value;
    // 结构损坏（键/值类型不对）与版本差异（键名不认识）必须区分对待：
    // 前者说明密文解出来的不是我们的载荷格式，继续解析没有意义。
    if (key is! String || value is! String) {
      throw const FormatException('备份凭据节载荷无效');
    }
    if (!kBackupCredentialKeys.contains(key)) {
      // 向前兼容：跳过而非抛错。
      //
      // 这里能走到说明 AES-GCM 认证**已经通过** —— 能产出合法密文的人
      // 必须知道口令，所以未知键不可能来自篡改，只可能来自「键集更新过
      // 的更高版本导出的合法备份」。旧版本对此抛错的代价极不对称：异常
      // 从 `BackupService.restoreFromJson` 冒到 UI，而解密发生在
      // `_doRestore` **之前**，于是用户的诗词进度、错题本、复习计划
      // 全都恢复不了，提示却只说「凭据节载荷无效」，无从自救。
      skipped.add(key);
      continue;
    }
    result[key] = value;
  }
  if (skipped.isNotEmpty) {
    // 只记键名，绝不记值 —— 这里每个 value 都是凭据明文。
    // 开发期加键漏改 kBackupCredentialKeys 时，这条日志是唯一线索。
    AppLogger.w(
      '备份凭据节含本版本不识别的键，已跳过：${skipped.join(", ")}',
      tag: 'Backup',
    );
  }
  if (result.isEmpty) {
    if (skipped.isNotEmpty) {
      // 全部键都不识别：无法降级恢复任何凭据，必须让用户知道，
      // 同时给出真实可行的出路 —— 口令留空时
      // `BackupService.restoreFromJson` 会整节跳过，学习数据照常恢复。
      throw const FormatException(
        '备份中的凭据来自更高版本，本版本无法识别；'
        '请升级应用后重试，或留空口令以只恢复学习数据',
      );
    }
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
