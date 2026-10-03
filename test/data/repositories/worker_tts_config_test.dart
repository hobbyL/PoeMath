// test/data/repositories/worker_tts_config_test.dart
//
// 自建 Worker TTS 配置存储测试：Key 隔离（AC12）、验证指纹生命周期（R2）。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

final class _MemoryCredentialStore extends SecureCredentialStore {
  String? workerApiKey;

  @override
  Future<void> saveWorkerTtsApiKey(String apiKey) async {
    workerApiKey = apiKey;
  }

  @override
  Future<String?> readWorkerTtsApiKey() => Future.value(workerApiKey);

  @override
  Future<void> deleteWorkerTtsApiKey() async {
    workerApiKey = null;
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

  test('API Key 只进安全存储，Hive 与备份导出均不含 Key（AC12）', () async {
    await repository.saveWorkerTtsConfig(
      baseUrl: 'https://tts.cloudm.cc',
      apiKey: 'worker-key-private',
    );

    expect(credentialStore.workerApiKey, 'worker-key-private');
    expect(repository.ttsCloudBaseUrl, 'https://tts.cloudm.cc');

    // Hive 设置任何值都不得包含 Key。
    for (final value in HiveBoxes.settings.values) {
      expect('$value', isNot(contains('worker-key-private')));
    }
    // JSON 备份导出同样不得包含 Key。
    final backup = BackupService();
    expect(backup.exportToJson(), isNot(contains('worker-key-private')));
  });

  test('保存配置规范化地址并强制重新验证', () async {
    await repository.saveWorkerTtsConfig(
      baseUrl: 'tts.cloudm.cc/',
      apiKey: 'key-1',
    );

    expect(repository.ttsCloudBaseUrl, 'https://tts.cloudm.cc');
    expect(await repository.isWorkerTtsVerified(), isFalse);
    expect((await repository.readWorkerTtsConfig())?.apiKey, 'key-1');
  });

  test('验证通过后指纹匹配，更换 Key 或地址立即失效', () async {
    await repository.saveWorkerTtsConfig(
      baseUrl: 'https://tts.cloudm.cc',
      apiKey: 'key-1',
    );
    await repository.markWorkerTtsVerified();
    expect(await repository.isWorkerTtsVerified(), isTrue);

    // 更换 Key → 指纹清除，需重新验证。
    await repository.saveWorkerTtsConfig(
      baseUrl: 'https://tts.cloudm.cc',
      apiKey: 'key-2',
    );
    expect(await repository.isWorkerTtsVerified(), isFalse);

    // 重新验证后仅改地址（Key 不变）同样失效。
    await repository.markWorkerTtsVerified();
    expect(await repository.isWorkerTtsVerified(), isTrue);
    await repository.setTtsCloudBaseUrl('https://tts2.cloudm.cc');
    expect(await repository.isWorkerTtsVerified(), isFalse);
  });

  test('未保存 Key 时视为未验证且配置读取为 null', () async {
    expect(await repository.readWorkerTtsConfig(), isNull);
    expect(await repository.isWorkerTtsVerified(), isFalse);
  });

  test('删除配置清除 Key 与设置并关闭云端开关', () async {
    await repository.saveWorkerTtsConfig(
      baseUrl: 'https://tts.cloudm.cc',
      apiKey: 'key-1',
    );
    await repository.markWorkerTtsVerified();
    await repository.setTtsCloudEnabled(true);
    await repository.setTtsCloudVoice('zh-CN-YunxiNeural');
    await repository.setTtsCloudStyle('narration-relaxed');

    await repository.deleteWorkerTtsConfig();

    expect(credentialStore.workerApiKey, isNull);
    expect(repository.ttsCloudEnabled, isFalse);
    expect(repository.ttsCloudVoice, 'zh-CN-XiaoxiaoNeural');
    expect(repository.ttsCloudStyle, 'poetry-reading');
    expect(repository.ttsCloudBaseUrl, 'https://tts.cloudm.cc');
    expect(await repository.isWorkerTtsVerified(), isFalse);
    expect(await repository.readWorkerTtsConfig(), isNull);
  });

  test('恢复备份不写入 API Key 到安全存储', () async {
    await repository.saveWorkerTtsConfig(
      baseUrl: 'https://tts.cloudm.cc',
      apiKey: 'worker-key-private',
    );
    final backup = BackupService();
    final json = backup.exportToJson();

    credentialStore.workerApiKey = null;
    await backup.restoreFromJson(json);

    // 备份不含 Key，恢复后安全存储保持为空。
    expect(credentialStore.workerApiKey, isNull);
    expect(await repository.readWorkerTtsConfig(), isNull);
  });
}
