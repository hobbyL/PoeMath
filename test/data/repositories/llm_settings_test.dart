// test/data/repositories/llm_settings_test.dart
//
// LLM 配置存储测试：Key 只进安全存储、地址/模型入 Hive、
// readLlmConfig 组装、deleteLlmConfig 清理与备份导出不含 Key。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

final class _MemoryCredentialStore extends SecureCredentialStore {
  String? workerApiKey;
  String? llmApiKey;

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

  @override
  Future<void> saveLlmApiKey(String apiKey) async {
    llmApiKey = apiKey;
  }

  @override
  Future<String?> readLlmApiKey() => Future.value(llmApiKey);

  @override
  Future<void> deleteLlmApiKey() async {
    llmApiKey = null;
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

  test('saveLlmConfig：Key 进安全存储、地址/模型/供应商名称进 Hive，'
      '备份导出含 llm_provider_name、不含 Key', () async {
    await repository.saveLlmConfig(
      baseUrl: 'https://api.example.com',
      model: 'gpt-4o-mini',
      apiKey: 'llm-key-private',
      providerName: 'DeepSeek',
    );

    expect(credentialStore.llmApiKey, 'llm-key-private');
    expect(repository.llmBaseUrl, 'https://api.example.com');
    expect(repository.llmModel, 'gpt-4o-mini');
    expect(repository.llmProviderName, 'DeepSeek');

    // Hive 任何值不得包含 Key。
    for (final value in HiveBoxes.settings.values) {
      expect('$value', isNot(contains('llm-key-private')));
    }
    // 备份导出：供应商名称随白名单迁移，Key 明文不外泄。
    final backup = BackupService();
    final exported = await backup.exportToJson();
    expect(exported, isNot(contains('llm-key-private')));
    expect(exported, contains('llm_provider_name'));
    expect(exported, contains('DeepSeek'));
  });

  test('readLlmConfig 组装完整配置；空 Key 保留空串（Ollama）', () async {
    await repository.saveLlmConfig(
      baseUrl: 'http://localhost:11434',
      model: 'qwen2.5:7b',
      apiKey: '',
    );

    final config = await repository.readLlmConfig();
    expect(config, isNotNull);
    expect(config!.baseUrl, 'http://localhost:11434');
    expect(config.model, 'qwen2.5:7b');
    expect(config.hasApiKey, isFalse);
  });

  test('未配置地址或模型时 readLlmConfig 返回 null', () async {
    expect(await repository.readLlmConfig(), isNull);

    await repository.setLlmBaseUrl('https://api.example.com');
    expect(await repository.readLlmConfig(), isNull); // 缺模型

    await repository.setLlmModel('gpt-4o-mini');
    expect(await repository.readLlmConfig(), isNotNull);
  });

  test('saveLlmConfig 非法地址抛 FormatException 且不落盘', () async {
    expect(
      () => repository.saveLlmConfig(
        baseUrl: 'not a url',
        model: 'gpt-4o-mini',
        apiKey: 'k',
      ),
      throwsFormatException,
    );
    expect(repository.llmBaseUrl, '');
    expect(credentialStore.llmApiKey, isNull);
  });

  test('deleteLlmConfig 清空地址/模型/供应商名称与 Key', () async {
    await repository.saveLlmConfig(
      baseUrl: 'https://api.example.com',
      model: 'gpt-4o-mini',
      apiKey: 'llm-key-private',
      providerName: 'DeepSeek',
    );

    await repository.deleteLlmConfig();

    expect(repository.llmBaseUrl, '');
    expect(repository.llmModel, '');
    expect(repository.llmProviderName, '');
    expect(credentialStore.llmApiKey, isNull);
    expect(await repository.readLlmConfig(), isNull);
  });

  test('旧备份恢复兼容：无 llm_provider_name 的 settings 节不报错，'
      '有则随白名单还原', () async {
    final backup = BackupService();
    // 模拟旧版本备份：settings 节只有既有 key，无 llm_provider_name。
    final legacyJson = jsonEncode(<String, dynamic>{
      'version': 1,
      'settings': <String, dynamic>{'theme_mode': 'light'},
    });
    await backup.restoreFromJson(legacyJson);
    expect(repository.llmProviderName, '');

    // 新版本备份：llm_provider_name 随白名单还原。
    final newJson = jsonEncode(<String, dynamic>{
      'version': 1,
      'settings': <String, dynamic>{
        'theme_mode': 'dark',
        'llm_provider_name': '通义千问',
      },
    });
    await backup.restoreFromJson(newJson);
    expect(repository.llmProviderName, '通义千问');
  });

  test('备份凭据白名单包含 llm_api_key（随口令加密同步）', () {
    expect(kBackupCredentialKeys, contains('llm_api_key'));
  });
}
