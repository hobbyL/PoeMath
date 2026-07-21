import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

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
    webDavCredentials[configId] = (
      username: username,
      password: password,
    );
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
  Future<void> saveTencentAsrCredentials(
    TencentAsrCredentials value,
  ) async {
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
    credentialStore = _MemoryCredentialStore();
    repository = SettingsRepository(credentialStore: credentialStore);
  });

  tearDown(() async {
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
    expect(state.highAccuracyEnabled, isFalse);
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
    final json = backup.exportToJson();

    expect(json, isNot(contains('AKID-private')));
    expect(json, isNot(contains('SK-private')));
    expect(json, isNot(contains('dav-private-user')));
    expect(json, isNot(contains('dav-private-password')));

    await backup.restoreFromJson(json);

    final tencent = await repository.readTencentAsrCredentials();
    expect(tencent?.secretId, 'AKID-private');
    expect(tencent?.secretKey, 'SK-private');
    final restoredConfig = repository.webDavConfigs.single;
    final fullConfig =
        await repository.loadWebDavConfigWithCredentials(restoredConfig);
    expect(fullConfig.username, 'dav-private-user');
    expect(fullConfig.password, 'dav-private-password');
  });

  test('未完成真实测试不能开启高精度', () async {
    await repository.saveTencentAsrCredentials(
      secretId: 'AKID',
      secretKey: 'SK',
    );

    await expectLater(
      repository.setTencentAsrHighAccuracyEnabled(true),
      throwsStateError,
    );
    expect(repository.tencentAsrHighAccuracyEnabled, isFalse);
  });

  test('测试成功后可开启，修改凭据立即撤销验证', () async {
    const first = TencentAsrCredentials(secretId: 'AKID-1', secretKey: 'SK-1');
    await repository.saveTencentAsrCredentials(
      secretId: first.secretId,
      secretKey: first.secretKey,
    );
    await repository.markTencentAsrCredentialsVerified(
      testedCredentials: first,
      verifiedAt: DateTime.utc(2026, 7, 21),
    );
    await repository.setTencentAsrHighAccuracyEnabled(true);

    var state = await repository.loadSpeechRecognitionSettings();
    expect(state.isVerified, isTrue);
    expect(state.highAccuracyEnabled, isTrue);

    await repository.saveTencentAsrCredentials(
      secretId: 'AKID-2',
      secretKey: 'SK-2',
    );
    state = await repository.loadSpeechRecognitionSettings();
    expect(state.isVerified, isFalse);
    expect(state.highAccuracyEnabled, isFalse);
    expect(repository.tencentAsrVerifiedAt, isNull);
  });

  test('删除凭据会关闭高精度并清除验证状态', () async {
    const credentials =
        TencentAsrCredentials(secretId: 'AKID', secretKey: 'SK');
    await repository.saveTencentAsrCredentials(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
    );
    await repository.markTencentAsrCredentialsVerified(
      testedCredentials: credentials,
    );
    await repository.setTencentAsrHighAccuracyEnabled(true);

    await repository.deleteTencentAsrCredentials();

    expect(credentialStore.credentials, isNull);
    final state = await repository.loadSpeechRecognitionSettings();
    expect(state.hasCredentials, isFalse);
    expect(state.isVerified, isFalse);
    expect(state.highAccuracyEnabled, isFalse);
  });
}
