// test/core/services/hive_encryption_key_provider_test.dart
//
// 读取失败不得覆盖密钥；成功读取的损坏编码与缺失值单独处理。

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
  Object? readError;
  final Map<String, String> values = {};

  @override
  Future<String?> readRawSecret(String key, {IOSOptions? iOptions}) async {
    if (readError != null) throw readError!;
    if (_throwOnRead.contains(key)) throw StateError('模拟安全存储不可读');
    return values[key];
  }

  @override
  Future<void> writeRawSecret(
    String key,
    String value, {
    IOSOptions? iOptions,
  }) async {
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
      final a =
          await HiveEncryptionKeyProvider(store: _MemoryStore()).loadOrCreate();
      final b =
          await HiveEncryptionKeyProvider(store: _MemoryStore()).loadOrCreate();
      expect(a.key, isNot(b.key));
    });

    test('密钥是 0-255 的字节序列', () async {
      final result =
          await HiveEncryptionKeyProvider(store: _MemoryStore()).loadOrCreate();
      expect(result.key.every((b) => b >= 0 && b <= 255), isTrue);
    });

    test('平台读取抛 FormatException 不能当作已读出的损坏编码覆盖密钥', () async {
      final store = _MemoryStore();
      final raw = base64Encode(List<int>.filled(32, 8));
      store.values[HiveEncryptionKeyProvider.keyName] = raw;
      store.readError = const FormatException('platform decode failed');
      await expectLater(HiveEncryptionKeyProvider(store: store).loadOrCreate(), throwsA(isA<HiveKeyUnavailable>()));
      expect(store.values[HiveEncryptionKeyProvider.keyName], raw);
      store.readError = null;
      expect((await HiveEncryptionKeyProvider(store: store).loadOrCreate()).key, List<int>.filled(32, 8));
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

      test('安全存储读取抛错 → 保留旧密钥并允许重试', () async {
        final store = _MemoryStore(
          throwOnRead: {
            HiveEncryptionKeyProvider.keyName,
          },
        );

        final old = base64Encode(List<int>.filled(32, 8));
        store.values[HiveEncryptionKeyProvider.keyName] = old;
        await expectLater(
          HiveEncryptionKeyProvider(store: store).loadOrCreate(),
          throwsA(isA<HiveKeyUnavailable>()),
        );
        expect(store.values[HiveEncryptionKeyProvider.keyName], old);
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
