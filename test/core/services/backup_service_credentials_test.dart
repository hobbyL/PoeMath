// test/core/services/backup_service_credentials_test.dart
//
// BackupService 凭据节集成测试（AC1–AC6）：口令加密随备份导出/恢复、
// 错口令零变更、无口令无节、留空跳过、旧备份兼容、明文不泄露。

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem_progress.dart';

import '../../helpers/hive_test_helper.dart';

final class _MemoryCredentialStore extends SecureCredentialStore {
  String? tencentSecretId;
  String? tencentSecretKey;
  String? workerApiKey;

  /// 模拟安全存储不可用（系统密钥库被重置 / 桌面无插件）。
  bool throwOnRead = false;

  Never _failRead() => throw PlatformException(
        code: 'unavailable',
        message: '安全存储不可用',
      );

  @override
  Future<void> saveTencentAsrCredentials(
    TencentAsrCredentials credentials,
  ) async {
    tencentSecretId = credentials.secretId;
    tencentSecretKey = credentials.secretKey;
  }

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async {
    if (throwOnRead) _failRead();
    final id = tencentSecretId;
    final key = tencentSecretKey;
    if (id == null || key == null) return null;
    final credentials = TencentAsrCredentials(secretId: id, secretKey: key);
    return credentials.isComplete ? credentials : null;
  }

  @override
  Future<void> deleteTencentAsrCredentials() async {
    tencentSecretId = null;
    tencentSecretKey = null;
  }

  @override
  Future<void> saveWorkerTtsApiKey(String apiKey) async {
    workerApiKey = apiKey;
  }

  @override
  Future<String?> readWorkerTtsApiKey() async {
    if (throwOnRead) _failRead();
    return workerApiKey;
  }

  @override
  Future<void> deleteWorkerTtsApiKey() async {
    workerApiKey = null;
  }

  // LLM Key 同步走内存（真实 FlutterSecureStorage 在测试环境不可用）。
  String? llmApiKey;

  @override
  Future<void> saveLlmApiKey(String apiKey) async {
    llmApiKey = apiKey;
  }

  @override
  Future<String?> readLlmApiKey() async {
    if (throwOnRead) _failRead();
    return llmApiKey;
  }

  @override
  Future<void> deleteLlmApiKey() async {
    llmApiKey = null;
  }
}

void main() {
  late _MemoryCredentialStore credentialStore;
  late BackupService backupService;

  setUp(() async {
    await setUpHiveForTesting();
    credentialStore = _MemoryCredentialStore();
    backupService = BackupService(secureStore: credentialStore);
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  Future<void> seedCredentials() async {
    await credentialStore.saveTencentAsrCredentials(
      const TencentAsrCredentials(
        secretId: 'AKID-private-secret-id',
        secretKey: 'SK-private-secret-key',
      ),
    );
    await credentialStore.saveWorkerTtsApiKey('worker-tts-private-key');
  }

  Future<void> seedProgress(String poemId) async {
    await HiveBoxes.poemProgress.put(
      'default_$poemId',
      PoemProgress(
        poemId: poemId,
        profileId: 'default',
        stars: 3,
      ),
    );
  }

  test('AC1 roundtrip：导出 → 清空 → 同口令恢复，凭据与数据齐回', () async {
    await seedCredentials();
    await seedProgress('poem_1');
    final json = await backupService.exportToJson(passphrase: '同步口令');

    await credentialStore.deleteTencentAsrCredentials();
    await credentialStore.deleteWorkerTtsApiKey();
    await HiveBoxes.poemProgress.clear();

    final count = await backupService.restoreFromJson(json, passphrase: '同步口令');

    expect(count, greaterThan(0));
    expect(credentialStore.tencentSecretId, 'AKID-private-secret-id');
    expect(credentialStore.tencentSecretKey, 'SK-private-secret-key');
    expect(credentialStore.workerApiKey, 'worker-tts-private-key');
    expect(HiveBoxes.poemProgress.values.single.poemId, 'poem_1');
  });

  test('跨版本恢复：备份含未来版本的凭据键，学习数据与已知凭据照常恢复',
      () async {
    // 回归「旧版本读不了新版本备份」：此前 decryptCredentials 对任一
    // 未知键直接抛 FormatException，而解密发生在 _doRestore **之前**，
    // 异常一路冒到 UI —— 用户的诗词进度、错题本、复习计划全都恢复不了，
    // 提示却只说「凭据节载荷无效」，无从自救。
    //
    // 场景：一台设备升级后新增了凭据键并导出，另一台未升级的设备恢复。
    await seedCredentials();
    await seedProgress('poem_1');
    final json = await backupService.exportToJson(passphrase: '同步口令');

    // 伪造「更高版本」的备份：凭据节里多一个本版本不认识的键。
    final data = jsonDecode(json) as Map<String, dynamic>;
    data['credentials'] = await encryptCredentials({
      kCredKeyTencentSecretId: 'AKID-private-secret-id',
      kCredKeyTencentSecretKey: 'SK-private-secret-key',
      kCredKeyWorkerTtsApiKey: 'worker-tts-private-key',
      'future_vendor_api_key': '来自更高版本',
    }, '同步口令',);
    final futureJson = jsonEncode(data);

    await credentialStore.deleteTencentAsrCredentials();
    await credentialStore.deleteWorkerTtsApiKey();
    await HiveBoxes.poemProgress.clear();

    final count =
        await backupService.restoreFromJson(futureJson, passphrase: '同步口令');

    // 学习数据必须照常恢复 —— 这是此前整体失败的那一部分。
    expect(count, greaterThan(0));
    expect(HiveBoxes.poemProgress.values.single.poemId, 'poem_1');
    // 本版本认识的凭据也照常恢复，未知键只是被跳过。
    expect(credentialStore.tencentSecretId, 'AKID-private-secret-id');
    expect(credentialStore.tencentSecretKey, 'SK-private-secret-key');
    expect(credentialStore.workerApiKey, 'worker-tts-private-key');
  });

  test('AC2 错口令：写入前失败，Hive 与安全存储零变更', () async {    await seedCredentials();
    await seedProgress('poem_1');
    final json = await backupService.exportToJson(passphrase: '同步口令');

    // 导出后本地数据与凭据继续演化
    await seedProgress('poem_2');
    await credentialStore.saveWorkerTtsApiKey('本地新Key');

    await expectLater(
      backupService.restoreFromJson(json, passphrase: '错误口令'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('口令'),
        ),
      ),
    );

    expect(HiveBoxes.poemProgress.values.map((p) => p.poemId),
        containsAll(['poem_1', 'poem_2']),);
    expect(credentialStore.workerApiKey, '本地新Key');
  });

  test('AC3 无口令导出：备份不含 credentials 节', () async {
    await seedCredentials();
    final json = await backupService.exportToJson();
    final node = jsonDecode(json) as Map<String, dynamic>;
    expect(node.containsKey('credentials'), isFalse);
    expect(BackupService.jsonHasCredentials(json), isFalse);
  });

  test('AC3 变体：口令留白等同未设置，同样无节', () async {
    await seedCredentials();
    final json = await backupService.exportToJson(passphrase: '   ');
    final node = jsonDecode(json) as Map<String, dynamic>;
    expect(node.containsKey('credentials'), isFalse);
  });

  test('AC4 留空跳过：凭据不恢复，其余数据正常恢复', () async {
    await seedCredentials();
    await seedProgress('poem_1');
    final json = await backupService.exportToJson(passphrase: '同步口令');

    await credentialStore.deleteTencentAsrCredentials();
    await credentialStore.deleteWorkerTtsApiKey();
    await HiveBoxes.poemProgress.clear();

    final count =
        await backupService.restoreFromJson(json, passphrase: '');

    expect(count, greaterThan(0));
    expect(HiveBoxes.poemProgress.values.single.poemId, 'poem_1');
    expect(credentialStore.tencentSecretId, isNull);
    expect(credentialStore.workerApiKey, isNull);
  });

  test('AC5 旧备份兼容：无 credentials 节恢复正常', () async {
    await seedProgress('poem_1');
    final legacy = await backupService.exportToJson();
    await HiveBoxes.poemProgress.clear();

    final count = await backupService.restoreFromJson(legacy);

    expect(count, greaterThan(0));
    expect(HiveBoxes.poemProgress.values.single.poemId, 'poem_1');
  });

  test('AC6 明文不泄露：导出 JSON 不含任何明文凭据', () async {
    await seedCredentials();
    final json = await backupService.exportToJson(passphrase: '同步口令');

    expect(json, isNot(contains('AKID-private-secret-id')));
    expect(json, isNot(contains('SK-private-secret-key')));
    expect(json, isNot(contains('worker-tts-private-key')));
  });

  test('凭据节结构：kdf/cipher 参数写入备份', () async {
    await credentialStore.saveWorkerTtsApiKey('worker-tts-private-key');
    final json = await backupService.exportToJson(passphrase: '同步口令');
    final node =
        (jsonDecode(json) as Map<String, dynamic>)['credentials'] as Map<String, dynamic>;

    final kdf = node['kdf'] as Map<String, dynamic>;
    expect(kdf['algorithm'], 'pbkdf2-sha256');
    expect(kdf['iterations'], 120000);
    final cipherNode = node['cipher'] as Map<String, dynamic>;
    expect(cipherNode['algorithm'], 'aes-256-gcm');
  });

  test('部分凭据：只存在 TTS Key 时也进备份并恢复', () async {
    await credentialStore.saveWorkerTtsApiKey('worker-tts-private-key');
    final json = await backupService.exportToJson(passphrase: '同步口令');

    await credentialStore.deleteWorkerTtsApiKey();
    await backupService.restoreFromJson(json, passphrase: '同步口令');

    expect(credentialStore.workerApiKey, 'worker-tts-private-key');
    expect(credentialStore.tencentSecretId, isNull);
  });

  test('jsonHasCredentials：坏 JSON 返回 false', () {
    expect(BackupService.jsonHasCredentials('not valid json'), isFalse);
    expect(BackupService.jsonHasCredentials('[]'), isFalse);
  });

  test('安全存储读取失败：抛 BackupCredentialExportException 而非静默丢密钥', () async {
    // 回归点：旧实现 `on Object { return null; }` 会把读取失败伪装成
    // 「这份备份本来就没有凭据」，用户换机恢复后才发现 Key 全丢。
    await seedCredentials();
    await seedProgress('poem_1');
    credentialStore.throwOnRead = true;

    await expectLater(
      backupService.exportToJson(passphrase: '同步口令'),
      throwsA(isA<BackupCredentialExportException>()),
    );
  });

  test('无口令导出不受读取失败影响（合法路径仍然静默省略凭据节）', () async {
    await seedCredentials();
    credentialStore.throwOnRead = true;

    // 用户没设口令 = 本来就不打算带密钥走，这不是失败。
    final json = await backupService.exportToJson();
    expect(BackupService.jsonHasCredentials(json), isFalse);
  });

  test('凭据读取失败且用户接受降级：不带口令重导得到完整数据、无凭据节', () async {
    await seedCredentials();
    await seedProgress('poem_1');
    credentialStore.throwOnRead = true;

    // UI 降级路径：捕获异常 → 用户点「仍然导出（不含密钥）」→ 无口令重试。
    final json = await backupService.exportToJson();
    final node = jsonDecode(json) as Map<String, dynamic>;
    expect(node.containsKey('credentials'), isFalse);
    expect(
      (node['poemProgress'] as List<dynamic>),
      hasLength(1),
      reason: '除密钥外的学习数据必须照常导出',
    );
  });

  test('凭据为空但读取成功：仍是合法省略，不抛异常', () async {
    // 已设口令但一个凭据都没存过 → payload 为空 → 合法返回 null。
    expect(
      await backupService.exportToJson(passphrase: '同步口令'),
      isNot(contains('credentials')),
    );
  });

  test('credentials 节非对象时校验拒绝', () async {
    final json = await backupService.exportToJson();
    final node = jsonDecode(json) as Map<String, dynamic>;
    node['credentials'] = 'not-an-object';
    final tampered = jsonEncode(node);

    await expectLater(
      backupService.restoreFromJson(tampered),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('credentials'),
        ),
      ),
    );
  });
}
