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
  /// 会走「密钥丢失」降级路径被清空。
  static const String keyName = 'hive_encryption_key';

  /// iOS 可访问性：`first_unlock_this_device`。
  ///
  /// - `first_unlock*`：设备重启后首次解锁即可读。启动流程要读它来开 box，
  ///   用更严的 `unlocked*` 会让「重启后未解锁就被后台唤醒」读不到密钥，
  ///   从而误判成密钥丢失并清空数据。
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
  /// 重新生成一把新密钥，让上层走「密钥丢失」降级。不抛异常 —— 抛了会被
  /// `AppBootstrap` 变成永久重试页，用户连界面都进不去（P6）。
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
    try {
      final raw = await _store.readRawSecret(keyName, iOptions: _iosOptions);
      if (raw == null) return null;

      final decoded = base64Decode(raw);
      if (decoded.length != keyLengthBytes) {
        AppLogger.e(
          'Hive 加密密钥长度异常（${decoded.length} 字节，应为 $keyLengthBytes），按密钥丢失处理',
          tag: 'Hive',
        );
        return null;
      }
      return decoded;
    } on FormatException catch (error) {
      // base64 解不开：存储项损坏。
      AppLogger.e(
        'Hive 加密密钥不是合法 base64，按密钥丢失处理',
        tag: 'Hive',
        error: error,
      );
      return null;
    } on Object catch (error) {
      // 安全存储本身不可用（如 Keystore 异常）。同样走丢失路径：
      // 这里必须吞掉，否则启动直接失败。
      AppLogger.e(
        'Hive 加密密钥读取失败，按密钥丢失处理',
        tag: 'Hive',
        error: error,
      );
      return null;
    }
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
