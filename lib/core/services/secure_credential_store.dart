// lib/core/services/secure_credential_store.dart
//
// 层级：core/services
// 职责：使用平台安全存储（iOS Keychain / Android EncryptedSharedPreferences）
//       管理敏感凭据，替代 Hive 明文存储。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// WebDAV 凭据的安全存储。
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

  // ============ 内部 ============

  static String _usernameKey(String id) => 'webdav_${id}_username';
  static String _passwordKey(String id) => 'webdav_${id}_password';
}
