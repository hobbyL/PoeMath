import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

final class _MemoryCredentialStore extends SecureCredentialStore {
  TencentAsrCredentials? credentials;
  final Map<String, ({String username, String password})> webDavCredentials =
      <String, ({String username, String password})>{};
  int readCalls = 0;

  @override
  Future<void> saveWebDavCredentials({
    required String configId,
    required String username,
    required String password,
  }) async {
    webDavCredentials[configId] = (username: username, password: password);
  }

  @override
  Future<({String username, String password})?> readWebDavCredentials(
    String configId,
  ) async {
    return webDavCredentials[configId];
  }

  @override
  Future<void> deleteWebDavCredentials(String configId) async {
    webDavCredentials.remove(configId);
  }

  @override
  Future<void> saveTencentAsrCredentials(TencentAsrCredentials value) async {
    credentials = value;
  }

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async {
    readCalls++;
    return credentials;
  }

  @override
  Future<void> deleteTencentAsrCredentials() async {
    credentials = null;
  }
}

void main() {
  late _MemoryCredentialStore credentialStore;
  late SettingsRepository repository;

  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    credentialStore = _MemoryCredentialStore();
    repository = SettingsRepository(credentialStore: credentialStore);
  });

  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('AK/SK 只进安全存储，Hive 只保存非敏感门禁状态', () async {
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID-secret',
      secretKey: 'SK-secret',
    );

    expect(credentialStore.credentials?.secretId, 'AKID-secret');
    expect(credentialStore.credentials?.secretKey, 'SK-secret');
    for (final value in HiveBoxes.settings.values) {
      expect('$value', isNot(contains('AKID-secret')));
      expect('$value', isNot(contains('SK-secret')));
    }
    final state = await repository.loadSpeechRecognitionSettings();
    expect(state.hasCredentials, isTrue);
    expect(state.isVerified, isFalse);
    expect(state.preferRealtime, isFalse);
  });

  test('未配置 APPID 时无法开启实时优先，旧偏好也不能绕过', () async {
    await repository.setTencentAsrPreferRealtime(true);
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );
    await HiveBoxes.settings.put('tencent_asr_prefer_realtime', true);
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
    await repository.setTencentAsrPreferRealtime(true);
    expect(HiveBoxes.settings.get('tencent_asr_prefer_realtime'), isFalse);
  });

  test('新配置 APPID 后可开启实时优先，开关选择跨仓储实例保留', () async {
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );
    await repository.saveTencentAsrAppId('1250000000');
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
    await repository.setTencentAsrPreferRealtime(true);
    var reloaded = SettingsRepository(credentialStore: credentialStore);
    expect(
      (await reloaded.loadSpeechRecognitionSettings()).preferRealtime,
      isTrue,
    );

    await reloaded.setTencentAsrPreferRealtime(false);
    reloaded = SettingsRepository(credentialStore: credentialStore);
    expect(
      (await reloaded.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
    expect((await reloaded.readTencentAsrCredentials())?.appId, '1250000000');
  });

  test('已有 APPID 的旧配置保留实时优先，可手动关闭', () async {
    credentialStore.credentials = const TencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
      appId: '1250000000',
    );
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isTrue,
    );
    await repository.setTencentAsrPreferRealtime(false);
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
  });

  test('清空 APPID 后开关持久关闭，重新填写也不会自动开启', () async {
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );
    await repository.saveTencentAsrAppId('1250000000');
    await repository.setTencentAsrPreferRealtime(true);
    await repository.markTencentAsrCredentialsVerified(
      testedCredentials: credentialStore.credentials!,
    );

    await repository.saveTencentAsrAppId('   ');
    final reloaded = SettingsRepository(credentialStore: credentialStore);
    final snapshot = await reloaded.loadSpeechRecognitionSettingsSnapshot();
    expect(snapshot.credentials?.appId, '');
    expect(snapshot.credentials?.secretId, 'AKID');
    expect(snapshot.credentials?.secretKey, 'SK');
    expect(snapshot.settings.preferRealtime, isFalse);
    expect(snapshot.settings.isVerified, isFalse);

    await reloaded.saveTencentAsrAppId('1250000000');
    expect(
      (await reloaded.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
  });

  test('替换或删除密钥同时关闭实时优先', () async {
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );
    await repository.saveTencentAsrAppId('1250000000');
    await repository.setTencentAsrPreferRealtime(true);
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID-2',
      secretKey: 'SK-2',
    );
    expect((await repository.readTencentAsrCredentials())?.appId, '');
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
    await repository.saveTencentAsrAppId('1250000001');
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );

    await repository.setTencentAsrPreferRealtime(true);
    await repository.deleteTencentAsrCredentials();
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isFalse,
    );
    expect(HiveBoxes.settings.get('tencent_asr_prefer_realtime'), isFalse);
  });

  test('设置快照只读取一次安全存储', () async {
    credentialStore.credentials = const TencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );
    credentialStore.readCalls = 0;

    final snapshot = await repository.loadSpeechRecognitionSettingsSnapshot();

    expect(snapshot.credentials?.secretId, 'AKID');
    expect(snapshot.settings.hasCredentials, isTrue);
    expect(credentialStore.readCalls, 1);
  });

  test('备份不含敏感凭据且恢复不覆盖设备安全存储', () async {
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID-private',
      secretKey: 'SK-private',
    );
    await repository.saveWebDavConfig(
      WebDavConfig(
        id: 'dav-1',
        name: '家庭云盘',
        url: 'https://dav.example.com',
        username: 'dav-private-user',
        password: 'dav-private-password',
        remotePath: '/poemath',
      ),
    );
    final backup = BackupService();
    await repository.saveTencentAsrAppId('1250000000');
    await repository.setTencentAsrPreferRealtime(true);
    final json = await backup.exportToJson();

    expect(json, isNot(contains('AKID-private')));
    expect(json, isNot(contains('SK-private')));
    expect(json, isNot(contains('dav-private-user')));
    expect(json, isNot(contains('dav-private-password')));
    expect(json, isNot(contains('tencent_asr_prefer_realtime')));

    await backup.restoreFromJson(json);

    final tencent = await repository.readTencentAsrCredentials();
    expect(tencent?.secretId, 'AKID-private');
    expect(tencent?.secretKey, 'SK-private');
    expect(
      (await repository.loadSpeechRecognitionSettings()).preferRealtime,
      isTrue,
    );
    final restoredConfig = repository.webDavConfigs.single;
    final fullConfig = await repository.loadWebDavConfigWithCredentials(
      restoredConfig,
    );
    expect(fullConfig.username, 'dav-private-user');
    expect(fullConfig.password, 'dav-private-password');
  });

  test('测试通过后即视为已配置，修改凭据立即撤销验证', () async {
    const first = TencentAsrCredentials(secretId: 'AKID-1', secretKey: 'SK-1');
    await repository.saveTencentAsrCredentials(
      secretId: first.secretId,
      secretKey: first.secretKey,
    );
    await repository.markTencentAsrCredentialsVerified(
      testedCredentials: first,
      verifiedAt: DateTime.utc(2026, 7, 21),
    );

    var state = await repository.loadSpeechRecognitionSettings();
    expect(state.isVerified, isTrue);
    expect(
      state.verifiedAt?.millisecondsSinceEpoch,
      DateTime.utc(2026, 7, 21).millisecondsSinceEpoch,
    );

    await repository.saveTencentAsrCredentials(
      secretId: 'AKID-2',
      secretKey: 'SK-2',
    );
    state = await repository.loadSpeechRecognitionSettings();
    expect(state.isVerified, isFalse);
    expect(state.verifiedAt, isNull);
    expect(repository.tencentAsrVerifiedAt, isNull);
  });

  test('删除凭据清除验证状态', () async {
    const credentials = TencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );
    await repository.saveTencentAsrCredentials(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
    );
    await repository.markTencentAsrCredentialsVerified(
      testedCredentials: credentials,
    );

    await repository.deleteTencentAsrCredentials();

    expect(credentialStore.credentials, isNull);
    final state = await repository.loadSpeechRecognitionSettings();
    expect(state.hasCredentials, isFalse);
    expect(state.isVerified, isFalse);
  });

  test('重新保存相同 AK/SK 保留手动 APPID 和已通过的录音验证', () async {
    const credentials = TencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
      appId: '1250000000',
    );
    await repository.saveTencentAsrCredentials(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
    );
    await repository.saveTencentAsrAppId(credentials.appId);
    final verifiedAt = DateTime.utc(2026, 11, 1);
    await repository.markTencentAsrCredentialsVerified(
      testedCredentials: credentials,
      verifiedAt: verifiedAt,
    );
    await repository.saveTencentAsrCredentials(
      secretId: ' ${credentials.secretId} ',
      secretKey: ' ${credentials.secretKey} ',
    );
    expect(
      (await repository.readTencentAsrCredentials())?.appId,
      credentials.appId,
    );
    final state = await repository.loadSpeechRecognitionSettings();
    expect(state.isVerified, isTrue);
    expect(state.verifiedAt, verifiedAt.toLocal());
  });
}
