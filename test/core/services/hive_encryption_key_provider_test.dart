// test/core/services/hive_encryption_key_provider_test.dart
//
// G6 的闸门：密钥的生成、持久化与「损坏/丢失」的降级判定。
//
// 这一层的每个失败方向都必须落在「当作没有密钥」而不是「抛异常」上：
// 它在启动路径上，抛出去 = 永久重试页 = 用户连界面都进不去（design.md P6）。

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/hive_encryption_key_provider.dart';
import 'package:poemath/core/services/secure_credential_store.dart';

/// 不触达平台通道的底层存储（测试环境里那个通道永不回应）。
final class _InertSecureStorage implements FlutterSecureStorage {
  const _InertSecureStorage();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试不应直连底层存储: ${invocation.memberName}');
}

/// 内存安全存储，可按 key 注入读取失败。
final class _MemoryStore extends SecureCredentialStore {
  _MemoryStore({Set<String> throwOnRead = const {}})
      : _throwOnRead = throwOnRead,
        super(storage: const _InertSecureStorage());

  final Set<String> _throwOnRead;
  final Map<String, String> values = {};

  @override
  Future<String?> readRawSecret(String key, {IOSOptions? iOptions}) async {
    if (_throwOnRead.contains(key)) throw StateError('模拟安全存储不可读');
    return values[key];
  }

  @override
  Future<void> writeRawSecret(String key, String value,
      {IOSOptions? iOptions,}) async {
    values[key] = value;
  }

  @override
  Future<void> deleteRawSecret(String key, {IOSOptions? iOptions}) async {
    values.remove(key);
  }
}

void main() {
  group('HiveEncryptionKeyProvider.loadOrCreate', () {
    test('无密钥时生成 32 字节并以 base64 落进安全存储', () async {
      final store = _MemoryStore();
      final provider = HiveEncryptionKeyProvider(store: store);

      final result = await provider.loadOrCreate();

      expect(result.isNew, isTrue);
      expect(result.key, hasLength(HiveEncryptionKeyProvider.keyLengthBytes));

      final raw = store.values[HiveEncryptionKeyProvider.keyName];
      expect(raw, isNotNull);
      expect(base64Decode(raw!), result.key);
    });

    test('已有密钥时原样返回，isNew 为 false', () async {
      final store = _MemoryStore();
      final provider = HiveEncryptionKeyProvider(store: store);

      final first = await provider.loadOrCreate();
      final second = await provider.loadOrCreate();

      expect(second.isNew, isFalse);
      expect(second.key, first.key);
    });

    test('两次生成（不同实例、空存储）得到不同密钥', () async {
      final a = await HiveEncryptionKeyProvider(store: _MemoryStore())
          .loadOrCreate();
      final b = await HiveEncryptionKeyProvider(store: _MemoryStore())
          .loadOrCreate();
      expect(a.key, isNot(b.key));
    });

    test('密钥是 0-255 的字节序列', () async {
      final result =
          await HiveEncryptionKeyProvider(store: _MemoryStore()).loadOrCreate();
      expect(result.key.every((b) => b >= 0 && b <= 255), isTrue);
    });

    group('损坏的密钥按「丢失」处理，不抛异常', () {
      test('非 base64 → 重新生成', () async {
        final store = _MemoryStore();
        store.values[HiveEncryptionKeyProvider.keyName] = '不是 base64!!!';

        final result =
            await HiveEncryptionKeyProvider(store: store).loadOrCreate();

        expect(result.isNew, isTrue);
        expect(result.key, hasLength(32));
        // 新密钥应已写回，覆盖掉坏值。
        expect(
          base64Decode(store.values[HiveEncryptionKeyProvider.keyName]!),
          result.key,
        );
      });

      test('base64 合法但长度不对 → 重新生成', () async {
        final store = _MemoryStore();
        // 16 字节，AES-256 要 32。
        store.values[HiveEncryptionKeyProvider.keyName] =
            base64Encode(List<int>.filled(16, 7));

        final result =
            await HiveEncryptionKeyProvider(store: store).loadOrCreate();

        expect(result.isNew, isTrue);
        expect(result.key, hasLength(32));
      });

      test('安全存储读取抛错 → 当作无密钥，不向上抛', () async {
        final store = _MemoryStore(throwOnRead: {
          HiveEncryptionKeyProvider.keyName,
        },);

        // 不 expect throws：这一层必须吞掉，否则启动直接失败。
        final result =
            await HiveEncryptionKeyProvider(store: store).loadOrCreate();

        expect(result.isNew, isTrue);
        expect(result.key, hasLength(32));
      });
    });
  });

  group('regenerate / deleteKey', () {
    test('regenerate 覆盖为新密钥', () async {
      final store = _MemoryStore();
      final provider = HiveEncryptionKeyProvider(store: store);
      final old = await provider.loadOrCreate();

      final fresh = await provider.regenerate();

      expect(fresh, isNot(old.key));
      final again = await provider.loadOrCreate();
      expect(again.key, fresh);
      expect(again.isNew, isFalse);
    });

    test('deleteKey 之后 loadOrCreate 视为新生成', () async {
      final store = _MemoryStore();
      final provider = HiveEncryptionKeyProvider(store: store);
      final first = await provider.loadOrCreate();

      await provider.deleteKey();
      final second = await provider.loadOrCreate();

      expect(second.isNew, isTrue);
      expect(second.key, isNot(first.key));
    });
  });
}
