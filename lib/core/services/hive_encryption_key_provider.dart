// lib/core/services/hive_encryption_key_provider.dart
//
// 层级：core/services
// 职责：Hive box 的 AES-256 密钥的生成与持久化。
//
// 密钥本身存在平台安全存储（SecureCredentialStore 的通用原始键值接口），
// 不落 Hive、不进备份 —— 见 `backup_rules.xml` 对 FlutterSecureStorage.xml
// 的排除。这样即便密文 box 随云备份漂到另一台设备，没有密钥也解不开。

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/utils/logger.dart';

/// 安全存储暂时不可访问；启动应保留原密钥和文件，允许重试。
class HiveKeyUnavailable implements Exception {
  const HiveKeyUnavailable();

  @override
  String toString() => '加密密钥暂时无法读取，请解锁设备后重试。原有记录已保留。';
}

/// Hive 加密密钥的读写。
///
/// **只负责「取到一把密钥」，不负责判断这把密钥能不能解开现有 box** ——
/// 那是 `HiveEncryptionKeyResolver` 的职责（它需要看迁移状态）。
class HiveEncryptionKeyProvider {
  HiveEncryptionKeyProvider({required SecureCredentialStore store})
      : _store = store;

  final SecureCredentialStore _store;

  /// `HiveAesCipher` 强制 256 bit，即 32 字节。
  static const int keyLengthBytes = 32;

  /// 安全存储中的键名。**不要改名**：改名等于丢掉密钥，用户全部学习记录
  /// 会使原有密文无法读取。
  static const String keyName = 'hive_encryption_key';

  /// iOS 可访问性：`first_unlock_this_device`。
  ///
  /// - `first_unlock*`：设备重启后首次解锁即可读。启动流程要读它来开 box，
  ///   用更严的 `unlocked*` 会让「重启后未解锁就被后台唤醒」读不到密钥，
  ///   因此读取失败必须保留原状并重试。
  /// - `*_this_device`：不随 iCloud 钥匙串同步到其他设备。密钥必须设备本机
  ///   持有 —— 同步过去会让「云端备份里的密文 + 另一台设备的密钥」变成
  ///   可解密组合，等于把加密的意义抹掉。
  ///
  /// 与 `SecureCredentialStore._parentIosOptions` 保持一致（同一理由）。
  static const IOSOptions _iosOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  /// 读取已有密钥；不存在则生成并持久化。
  ///
  /// 返回 `(key, isNew)`。`isNew == true` 表示本次新生成 —— 调用方据此判断
  /// 「有明文 box 却没有密钥」这一首启迁移场景（见 design.md §7.3）。
  ///
  /// 安全存储里存在但格式损坏（非 base64 / 长度不对）时**当作不存在**：
  /// 重新生成密钥后，上层隔离保留无法读取的文件。平台读取异常则抛出
  /// `HiveKeyUnavailable`，启动显示可重试提示，绝不覆盖旧密钥。
  Future<({List<int> key, bool isNew})> loadOrCreate() async {
    final existing = await _read();
    if (existing != null) return (key: existing, isNew: false);

    final key = _generateKey();
    await _write(key);
    return (key: key, isNew: true);
  }

  /// 生成一把新密钥并覆盖写入。
  ///
  /// 仅用于「密钥丢失降级」路径：确认旧密文已放弃后才可调用，
  /// 否则会把仍能解密的旧数据变成永久不可读。
  Future<List<int>> regenerate() async {
    final key = _generateKey();
    await _write(key);
    return key;
  }

  /// 删除密钥。**只应被测试或「用户主动重置」使用** —— 调用后现有密文
  /// box 全部不可读。
  Future<void> deleteKey() =>
      _store.deleteRawSecret(keyName, iOptions: _iosOptions);

  Future<List<int>?> _read() async {
    final String? raw;
    try {
      raw = await _store.readRawSecret(keyName, iOptions: _iosOptions);
    } on Object catch (error) {
      AppLogger.e(
        'Hive 加密密钥暂时无法读取，保留现有密钥并等待重试',
        tag: 'Hive',
        error: error,
      );
      throw const HiveKeyUnavailable();
    }
    if (raw == null) return null;
    try {
      final decoded = base64Decode(raw);
      if (decoded.length == keyLengthBytes) return decoded;
      AppLogger.e('Hive 加密密钥长度异常，原文件将隔离保留', tag: 'Hive');
    } on FormatException {
      AppLogger.e('Hive 加密密钥格式异常，原文件将隔离保留', tag: 'Hive');
    }
    return null;
  }

  Future<void> _write(List<int> key) async {
    await _store.writeRawSecret(
      keyName,
      base64Encode(key),
      iOptions: _iosOptions,
    );
  }

  /// 32 字节密码学安全随机数。
  ///
  /// 用 `Random.secure()` 而非 `Random()`：后者的种子可预测，
  /// 用它生成的密钥等于没加密。
  List<int> _generateKey() {
    final random = Random.secure();
    return List<int>.generate(keyLengthBytes, (_) => random.nextInt(256));
  }
}
