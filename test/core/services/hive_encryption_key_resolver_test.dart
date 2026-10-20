// test/core/services/hive_encryption_key_resolver_test.dart
//
// 验证启动逐 box 迁移、失败重试以及不可读文件的完整留底。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/services/hive_encryption_key_provider.dart';
import 'package:poemath/core/services/hive_encryption_key_resolver.dart';
import 'package:poemath/core/services/secure_credential_store.dart';

final class _InertSecureStorage implements FlutterSecureStorage {
  const _InertSecureStorage();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试不应直连底层存储: ${invocation.memberName}');
}

final class _MemoryStore extends SecureCredentialStore {
  _MemoryStore() : super(storage: const _InertSecureStorage());

  final Map<String, String> values = {};

  @override
  Future<String?> readRawSecret(String key, {IOSOptions? iOptions}) async =>
      values[key];

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

List<int> _key([int seed = 1]) {
  final r = Random(seed);
  return List<int>.generate(32, (_) => r.nextInt(256));
}

/// 直接往目录里写一个加/未加密的 box。
Future<void> _writeBox(
  Directory dir,
  String name,
  Map<dynamic, dynamic> data, {
  List<int>? key,
}) async {
  Hive.init(dir.path);
  final box = await Hive.openBox<dynamic>(
    name,
    encryptionCipher: key == null ? null : HiveAesCipher(key),
  );
  await box.putAll(data);
  await box.close();
  await Hive.close();
}

void main() {
  late Directory dir;
  late _MemoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_resolver_');
    store = _MemoryStore();
  });

  tearDown(() async {
    try {
      await Hive.close();
    } on Object {
      // 有些用例故意让 box 处于半打开状态。
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<ResolvedCipher> resolve() => HiveEncryptionKeyResolver.resolve(
        boxDir: dir.path,
        credentialStore: store,
      );

  group('全新安装', () {
    test('无密钥、无文件 → newInstall，生成密钥', () async {
      final result = await resolve();

      expect(result.status, HiveKeyStatus.newInstall);
      expect(HiveEncryptionKeyResolver.isPlaintext(result.cipher), isFalse);
      expect(store.values[HiveEncryptionKeyProvider.keyName], isNotNull);
    });
  });

  group('已加密 + 密钥正确', () {
    test('密钥与数据匹配 → ok', () async {
      final key = _key();
      store.values[HiveEncryptionKeyProvider.keyName] = base64Encode(key);
      await _writeBox(dir, 'poems', {'p1': 'data'}, key: key);

      final result = await resolve();

      expect(result.status, HiveKeyStatus.ok);
      expect(HiveEncryptionKeyResolver.isPlaintext(result.cipher), isFalse);
    });
  });

  group('密钥丢失（降级，不抛异常）', () {
    test('密钥存在但解不开数据 → 保留密钥并隔离完整文件', () async {
      // 数据用 key A 加密，安全存储里却是 key B（换机恢复备份、
      // 安全存储被清后重新生成等情形）。
      await _writeBox(dir, 'poems', {'p1': 'data'}, key: _key(1));
      store.values[HiveEncryptionKeyProvider.keyName] = base64Encode(_key(2));

      final before = await File('${dir.path}/poems.hive').readAsBytes();
      final result = await resolve();

      expect(result.status, HiveKeyStatus.recoveredEmpty);
      expect(HiveEncryptionKeyResolver.isPlaintext(result.cipher), isFalse);
      // 不可读的密文应被清掉，为新数据让路。
      expect(File('${dir.path}/poems.hive').existsSync(), isFalse);
      // 已存密钥不覆盖，原始文件完整留在隔离目录。
      expect(
        base64Decode(store.values[HiveEncryptionKeyProvider.keyName]!),
        _key(2),
      );
      final files =
          Directory('${dir.path}/hive_recovery').listSync().whereType<File>();
      expect(files, hasLength(1));
      expect(await files.single.readAsBytes(), before);
    });

    test('降级后同一把新密钥可开新 box（自洽）', () async {
      await _writeBox(dir, 'poems', {'p1': 'data'}, key: _key(1));
      store.values[HiveEncryptionKeyProvider.keyName] = base64Encode(_key(2));

      final result = await resolve();

      // 用返回的 cipher 写一个新 box，应能读回。
      final box = await Hive.openBox<dynamic>(
        'settings',
        encryptionCipher: result.cipher,
      );
      await box.put('after', 'ok');
      await box.close();
      await Hive.close();

      Hive.init(dir.path);
      final reopened = await Hive.openBox<dynamic>(
        'settings',
        encryptionCipher: result.cipher,
      );
      expect(reopened.get('after'), 'ok');
      await reopened.close();
    });

    test('只删不存在的文件时不抛异常；多个 box 一并清掉', () async {
      await _writeBox(dir, 'poems', {'a': '1'}, key: _key(1));
      await _writeBox(dir, 'authors', {'b': '2'}, key: _key(1));
      store.values[HiveEncryptionKeyProvider.keyName] = base64Encode(_key(2));

      final result = await resolve();

      expect(result.status, HiveKeyStatus.recoveredEmpty);
      expect(File('${dir.path}/poems.hive').existsSync(), isFalse);
      expect(File('${dir.path}/authors.hive').existsSync(), isFalse);
    });
  });

  group('有明文数据 + 无密钥 → 迁移', () {
    test('明文 box 被加密，状态为 ok（不是 newInstall）', () async {
      await _writeBox(dir, 'poems', {'p1': 'plaintext'});

      final result = await resolve();

      expect(result.status, HiveKeyStatus.ok);
      expect(HiveEncryptionKeyResolver.isPlaintext(result.cipher), isFalse);

      // 磁盘上不该再有明文。
      final raw = File('${dir.path}/poems.hive').readAsBytesSync();
      final needle = ascii.encode('plaintext');
      var found = false;
      for (var i = 0; i + needle.length <= raw.length; i++) {
        var hit = true;
        for (var j = 0; j < needle.length; j++) {
          if (raw[i + j] != needle[j]) {
            hit = false;
            break;
          }
        }
        if (hit) {
          found = true;
          break;
        }
      }
      expect(found, isFalse, reason: '迁移后仍是明文');

      // 数据能读回。
      Hive.init(dir.path);
      final box = await Hive.openBox<dynamic>(
        'poems',
        encryptionCipher: result.cipher,
      );
      expect(box.get('p1'), 'plaintext');
      await box.close();
    });
  });

  group('有密文数据 + 无密钥 → 降级（真机回归）', () {
    // **这一组的存在理由**：真机首次验证「密钥丢失」场景时，删掉安全存储后
    // 应用走进了**迁移**分支而不是降级分支 —— 因为当时只用「文件是否存在」
    // 区分「全新安装」与「有明文待迁移」，而「有密文但没密钥」也是
    // 「文件存在」，被误判成后者。后果很严重：
    //
    //   迁移必然失败（密文不是可读明文）→ 退回明文模式启动
    //   → `Hive.openBox` 的默认 crashRecovery 把解不开的密文**就地截断成空 box**
    //   → 应用随即写入新数据 → 用户数据被静默销毁
    //
    // 最后一条是实测到的：`authors.hive` 从 107043 字节（密文）被改写成
    // 97734 字节，且内容已非原密文。所以这里的断言不能只看状态码，
    // 必须同时钉住「磁盘上的密文还在 / 被明确清掉」。
    test('密钥丢失但有密文 → recoveredEmpty（而不是误走迁移）', () async {
      await _writeBox(dir, 'poems', {'p1': 'v'}, key: _key(1));
      // 安全存储为空 = 密钥丢失（换机、系统重置、Keystore 被清）。
      expect(store.values, isEmpty);

      final result = await resolve();

      expect(
        result.status,
        HiveKeyStatus.recoveredEmpty,
        reason: '密文 + 无密钥必须走降级，不能误判成「有明文待迁移」',
      );
      // 降级语义：解不开的密文被清掉，用户看到提示 + 重新开始。
      expect(File('${dir.path}/poems.hive').existsSync(), isFalse);
    });

    test('密文 + 明文混存时仍判为可迁移（不能因个别密文否定整批）', () async {
      // 真实场景：迁移中途失败过，或用户换过部分数据 —— 目录里可能
      // 明文与密文并存。只要有一个 box 可读明文，就按「老用户升级」处理。
      await _writeBox(dir, 'poems', {'p1': 'plaintext'});
      await _writeBox(dir, 'authors', {'a1': 'x'}, key: _key(1));

      final result = await resolve();

      expect(result.status, HiveKeyStatus.recoveredEmpty);
      expect(HiveEncryptionKeyResolver.isPlaintext(result.cipher), isFalse);
      // 明文那个 box 必须已转密文。
      final reopened = await Hive.openBox<dynamic>(
        'poems',
        encryptionCipher: result.cipher,
      );
      expect(reopened.get('p1'), 'plaintext');
      await reopened.close();
    });

    test('全是 0 字节文件 → 按可迁移处理（空文件无内容可丢）', () async {
      // 0 字节文件没有 checksum 可校验，Hive 用任意 cipher 都能「打开」它。
      // 判成「有明文待迁移」是安全的：`_migrateBox` 会把它归为 empty 跳过，
      // 不会写坏任何东西。
      File('${dir.path}/poems.hive').writeAsBytesSync(const []);
      File('${dir.path}/authors.hive').writeAsBytesSync(const []);

      final result = await resolve();

      expect(result.status, HiveKeyStatus.ok);
      // 文件被原样留着（没被删、也没被清）。
      expect(File('${dir.path}/poems.hive').lengthSync(), 0);
    });
  });

  group('中断迁移恢复', () {
    test('已有密钥和密文时仍补迁移余下明文', () async {
      final key = _key();
      store.values[HiveEncryptionKeyProvider.keyName] = base64Encode(key);
      await _writeBox(dir, 'poems', {'p': 'encrypted'}, key: key);
      await _writeBox(dir, 'settings', {'s': 'plaintext'});
      final result = await resolve();
      expect(result.status, HiveKeyStatus.ok);
      final box = await Hive.openBox<dynamic>(
        'settings',
        encryptionCipher: result.cipher,
        crashRecovery: false,
      );
      expect(box.get('s'), 'plaintext');
    });

    test('备份阶段失败保留完整源文件，重试可迁移', () async {
      await _writeBox(dir, 'poems', {'p': 'original'});
      final original = await File('${dir.path}/poems.hive').readAsBytes();
      final blocker =
          await Directory('${dir.path}/poems.hive.plaintext.bak.pending')
              .create();
      await expectLater(resolve(), throwsA(isA<HiveError>()));
      expect(await File('${dir.path}/poems.hive').readAsBytes(), original);
      final key = store.values[HiveEncryptionKeyProvider.keyName];
      await blocker.delete();
      expect((await resolve()).status, HiveKeyStatus.ok);
      expect(store.values[HiveEncryptionKeyProvider.keyName], key);
    });
  });

  group('allBoxNames', () {
    test('覆盖 HiveBoxes 打开的全部 19 个 box', () {
      // 漏一个就是一处明文泄漏，因此数量与名单都要钉住。
      expect(HiveEncryptionKeyResolver.allBoxNames, hasLength(19));
      expect(
        HiveEncryptionKeyResolver.allBoxNames.toSet(),
        hasLength(19),
        reason: '名单中不应有重复项',
      );
      for (final required in ['poems', 'settings', 'meta']) {
        expect(HiveEncryptionKeyResolver.allBoxNames, contains(required));
      }
    });
  });
}
