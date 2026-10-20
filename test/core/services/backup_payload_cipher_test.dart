import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_history_service.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_payload_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import '../../helpers/hive_test_helper.dart';

class _Store extends SecureCredentialStore {
  String? raw;
  bool fail = false;
  int writes = 0;
  @override
  Future<String?> readRawSecret(String key, {IOSOptions? iOptions}) async {
    if (fail) throw StateError('key unavailable');
    return raw;
  }

  @override
  Future<void> writeRawSecret(
    String key,
    String value, {
    IOSOptions? iOptions,
  }) async {
    writes++;
    raw = value;
  }
}

void main() {
  late Directory root;
  final keyBytes = List<int>.generate(32, (i) => i);
  final key = SecretKey(keyBytes);
  const plain =
      '{"version":1,"exportedAt":"2026-10-20T12:00:00Z","settings":{"theme_mode":"light"}}';
  setUp(() async {
    await setUpHiveForTesting();
    root = await Directory.systemTemp.createTemp('whole_backup_test_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await tearDownHiveForTesting();
  });

  test('整包口令加密往返，错误口令不改变任何现有数据', () async {
    final encrypted = await encryptBackupPayload(plain, passphrase: '合成测试口令');
    expect(encrypted, isNot(contains('theme_mode')));
    expect(await decryptBackupPayload(encrypted, passphrase: '合成测试口令'), plain);
    await HiveBoxes.settings.put('theme_mode', 'dark');
    await expectLater(
      BackupService().restoreFromJson(encrypted, passphrase: '错误口令'),
      throwsFormatException,
    );
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    await BackupService().restoreFromJson(encrypted, passphrase: '合成测试口令');
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
  });

  test('整包解密后跳过未来版本凭据仍可恢复学习数据', () async {
    const passphrase = '合成测试口令';
    final credentials = await encryptCredentials(
      {'future_vendor_key': 'synthetic-key'},
      passphrase,
    );
    final encrypted = await encryptBackupPayload(
      jsonEncode({
        'version': 1,
        'settings': {'theme_mode': 'light'},
        'credentials': credentials,
      }),
      passphrase: passphrase,
    );
    final decrypted = await decryptBackupPayload(
      encrypted,
      passphrase: passphrase,
    );
    final backup = BackupService();
    final preview = backup.inspectJson(decrypted);
    expect(preview.hasCredentials, isTrue);
    await HiveBoxes.settings.put('theme_mode', 'dark');
    await expectLater(
      backup.validateRestoreCredentials(preview, passphrase: passphrase),
      throwsFormatException,
    );
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    await backup.validateRestoreCredentials(preview, passphrase: '');
    await backup.restoreFromJson(preview.json, passphrase: '');
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
  });

  test('认证覆盖密文和 envelope 元数据，损坏格式不能回落明文恢复', () async {
    final encrypted = await encryptBackupPayload(plain, deviceKey: key);
    final original = jsonDecode(encrypted) as Map<String, dynamic>;
    for (final field in ['ciphertext', 'exportedAt']) {
      final changed = Map<String, dynamic>.from(original);
      if (field == 'ciphertext') {
        final bytes = base64Decode(changed[field] as String);
        bytes[15] ^= 1;
        changed[field] = base64Encode(bytes);
      } else {
        changed[field] = '2026-10-21T00:00:00Z';
      }
      await expectLater(
        decryptBackupPayload(jsonEncode(changed), deviceKey: key),
        throwsFormatException,
      );
    }
    for (final version in [null, 1]) {
      final changed = Map<String, dynamic>.from(original)
        ..['format'] = 'broken-format';
      if (version == null) {
        changed.remove('version');
      } else {
        changed['version'] = version;
      }
      await HiveBoxes.settings.put('theme_mode', 'dark');
      final damaged = jsonEncode(changed);
      expect(() => BackupService().inspectJson(damaged), throwsFormatException);
      await expectLater(
        BackupService().restoreFromJson(damaged),
        throwsFormatException,
      );
      expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    }
  });

  test('恶意 KDF 和超大文件在解析或派生前拒绝', () async {
    final node = jsonDecode(await encryptBackupPayload(plain, deviceKey: key))
        as Map<String, dynamic>;
    node['kdf'] = {
      'algorithm': 'pbkdf2-sha256',
      'iterations': 999999999,
      'salt': base64Encode(List.filled(16, 0)),
    };
    await expectLater(
      decryptBackupPayload(jsonEncode(node), passphrase: '合成测试'),
      throwsFormatException,
    );
    final file = File('${root.path}/large.json');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(maxBackupBytes + 1);
    await handle.close();
    await expectLater(readBackupFile(file), throwsFormatException);
  });

  test('旧明文历史迁移后磁盘不含学习明文且读回一致', () async {
    final dir = await Directory('${root.path}/backup_history').create();
    final file = File('${dir.path}/1_manual_deadbeef.json');
    await file.writeAsString(plain);
    final history = BackupHistoryService(
      backup: BackupService(),
      directoryProvider: () async => root,
      keyProvider: () async => keyBytes,
    );
    await history.maybeCreateDaily();
    final stored = await file.readAsString();
    expect(stored, isNot(contains('theme_mode')));
    expect(isEncryptedBackup(stored), isTrue);
    expect(await history.read('1_manual_deadbeef.json'), plain);
  });

  test('密钥暂不可读、丢失或损坏时不覆盖密钥和原密文', () async {
    final dir = await Directory('${root.path}/backup_history').create();
    final file = File('${dir.path}/1_manual_deadbeef.json');
    final encrypted = await encryptBackupPayload(plain, deviceKey: key);
    await file.writeAsString(encrypted);
    final store = _Store()
      ..raw = base64Encode(keyBytes)
      ..fail = true;
    final history = BackupHistoryService(
      backup: BackupService(),
      directoryProvider: () async => root,
      credentialStore: store,
    );
    await expectLater(history.read('1_manual_deadbeef.json'), throwsStateError);
    expect(store.writes, 0);
    expect(store.raw, base64Encode(keyBytes));
    store
      ..fail = false
      ..raw = null;
    await expectLater(history.read('1_manual_deadbeef.json'), throwsStateError);
    expect(store.writes, 0);
    store.raw = 'corrupt!';
    await expectLater(
      history.read('1_manual_deadbeef.json'),
      throwsFormatException,
    );
    expect(store.writes, 0);
    expect(await file.readAsString(), encrypted);
    store.raw = base64Encode(keyBytes);
    expect(await history.read('1_manual_deadbeef.json'), plain);
  });
}
