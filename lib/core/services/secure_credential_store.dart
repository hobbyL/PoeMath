// lib/core/services/secure_credential_store.dart
//
// 层级：core/services
// 职责：使用平台安全存储（iOS Keychain / Android EncryptedSharedPreferences）
//       管理敏感凭据，替代 Hive 明文存储。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';

/// WebDAV and Tencent ASR credentials backed by platform secure storage.
///
/// 密钥格式：`webdav_{configId}_username` / `webdav_{configId}_password`。
class SecureCredentialStore {
  SecureCredentialStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;

  // ============ WebDAV 凭据 ============

  /// 保存 WebDAV 凭据。
  Future<void> saveWebDavCredentials({
    required String configId,
    required String username,
    required String password,
  }) async {
    await _storage.write(
      key: _usernameKey(configId),
      value: username,
    );
    await _storage.write(
      key: _passwordKey(configId),
      value: password,
    );
  }

  /// 读取 WebDAV 凭据，返回 (username, password)。
  /// 若不存在返回 `null`。
  Future<({String username, String password})?> readWebDavCredentials(
    String configId,
  ) async {
    final username = await _storage.read(key: _usernameKey(configId));
    final password = await _storage.read(key: _passwordKey(configId));
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  /// 删除 WebDAV 凭据。
  Future<void> deleteWebDavCredentials(String configId) async {
    await _storage.delete(key: _usernameKey(configId));
    await _storage.delete(key: _passwordKey(configId));
  }

  // ============ Tencent ASR 凭据 ============

  Future<void> saveTencentAsrCredentials(
    TencentAsrCredentials credentials,
  ) async {
    await _storage.write(
      key: _tencentSecretIdKey,
      value: credentials.secretId,
    );
    await _storage.write(
      key: _tencentSecretKeyKey,
      value: credentials.secretKey,
    );
  }

  Future<TencentAsrCredentials?> readTencentAsrCredentials() async {
    final secretId = await _storage.read(key: _tencentSecretIdKey);
    final secretKey = await _storage.read(key: _tencentSecretKeyKey);
    if (secretId == null || secretKey == null) return null;
    final credentials = TencentAsrCredentials(
      secretId: secretId,
      secretKey: secretKey,
    );
    return credentials.isComplete ? credentials : null;
  }

  Future<void> deleteTencentAsrCredentials() async {
    await _storage.delete(key: _tencentSecretIdKey);
    await _storage.delete(key: _tencentSecretKeyKey);
  }

  // ============ 内部 ============

  static String _usernameKey(String id) => 'webdav_${id}_username';
  static String _passwordKey(String id) => 'webdav_${id}_password';

  static const String _tencentSecretIdKey = 'tencent_asr_secret_id';
  static const String _tencentSecretKeyKey = 'tencent_asr_secret_key';
}
