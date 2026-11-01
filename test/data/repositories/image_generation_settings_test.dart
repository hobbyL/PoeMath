import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

const _config = ImageGenerationProviderConfig(
  name: '生图',
  baseUrl: 'https://image.example.com/v1',
  model: 'image-model',
);

class _Store extends SecureCredentialStore {
  String? key;
  final providerKeys = <String, String>{};
  bool failNext = false;
  Completer<void>? entered;
  Completer<void>? waitWrite;
  Completer<void>? llmEntered;
  Completer<void>? llmProceed;
  bool failLlmWrite = false;

  @override
  Future<void> saveLlmApiKeyFor(String id, String apiKey) async {
    llmEntered?.complete();
    await llmProceed?.future;
    if (failLlmWrite) throw StateError('synthetic LLM write failure');
  }

  @override
  Future<String?> readImageGenerationApiKey() async => key;
  @override
  Future<void> saveImageGenerationApiKey(String apiKey) async {
    key = apiKey;
    await _afterWrite();
  }

  Future<void> _afterWrite() async {
    if (failNext) {
      failNext = false;
      throw StateError('synthetic write failure');
    }
    final wait = waitWrite;
    if (wait != null) {
      waitWrite = null;
      entered!.complete();
      await wait.future;
    }
  }

  @override
  Future<void> deleteImageGenerationApiKey() async {
    key = null;
  }

  @override
  Future<String?> readImageGenerationApiKeyFor(String id) async =>
      id == SecureCredentialStore.legacyImageGenerationProviderId
          ? key
          : providerKeys[id];

  @override
  Future<void> saveImageGenerationApiKeyFor(String id, String apiKey) async {
    if (id == SecureCredentialStore.legacyImageGenerationProviderId) {
      await saveImageGenerationApiKey(apiKey);
    } else {
      providerKeys[id] = apiKey;
      await _afterWrite();
    }
  }

  @override
  Future<void> deleteImageGenerationApiKeyFor(String id) async {
    if (id == SecureCredentialStore.legacyImageGenerationProviderId) {
      await deleteImageGenerationApiKey();
    } else {
      providerKeys.remove(id);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late SettingsRepository settings;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    store = _Store();
    settings = SettingsRepository(credentialStore: store);
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('保存配置与密钥，留空沿用，明确清除；密钥从不进入 Hive 或普通导出', () async {
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'image-private-secret',
    );
    expect(
      (await settings.readImageGenerationConfig())!.apiKey,
      'image-private-secret',
    );
    expect(
      jsonDecode(
        HiveBoxes.settings
            .get(ImageGenerationProviderConfig.providersSettingsKey) as String,
      ),
      [
        {
          'id': 'image-legacy',
          'name': '生图',
          'baseUrl': 'https://image.example.com/v1',
          'model': 'image-model',
          'models': ['image-model'],
        },
      ],
    );
    expect(
      HiveBoxes.settings.containsKey(ImageGenerationProviderConfig.settingsKey),
      isFalse,
    );
    expect(
      HiveBoxes.settings.values.toString(),
      isNot(contains('image-private-secret')),
    );
    final backup = BackupService(secureStore: store);
    expect(
      await backup.exportToJson(),
      isNot(contains('image-private-secret')),
    );
    await settings.saveImageGenerationConfig(provider: _config, apiKey: '');
    expect(store.key, 'image-private-secret');
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: '',
      clearApiKey: true,
    );
    expect(store.key, isNull);
    expect(settings.imageGenerationProvider!.model, 'image-model');
  });

  test('写密钥期间家长锁定，原始配置和密钥都补偿；重新解锁可以再保存', () async {
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'old-key',
    );
    final entered = Completer<void>();
    final proceed = Completer<void>();
    store.entered = entered;
    store.waitWrite = proceed;
    final work = settings.saveImageGenerationConfig(
      provider: const ImageGenerationProviderConfig(
        name: '另一个',
        baseUrl: 'https://other.example.com',
        model: 'other-image',
      ),
      apiKey: 'new-key',
    );
    final expectation = expectLater(work, throwsA(isA<ParentAccessDenied>()));
    await entered.future;
    lockParentForTesting();
    proceed.complete();
    await expectation;
    expect(store.key, 'old-key');
    expect(settings.imageGenerationProvider!.encode(), _config.encode());
    await unlockParentForTesting();
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'retry-key',
    );
    expect(store.key, 'retry-key');
  });

  test('读取生图配置等待完整保存，不能混用旧地址和新密钥', () async {
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'old-key',
    );
    const next = ImageGenerationProviderConfig(
      name: '新生图服务',
      baseUrl: 'https://new-image.example.com/v1',
      model: 'new-image-model',
    );
    final entered = Completer<void>();
    final proceed = Completer<void>();
    store.entered = entered;
    store.waitWrite = proceed;
    final saving = settings.saveImageGenerationConfig(
      provider: next,
      apiKey: 'new-key',
    );
    await entered.future;
    var readCompleted = false;
    final reading = settings.readImageGenerationConfig().then((value) {
      readCompleted = true;
      return value;
    });
    try {
      await Future<void>.delayed(Duration.zero);
      expect(readCompleted, isFalse);
    } finally {
      proceed.complete();
    }
    await saving;
    final config = (await reading)!;
    expect(config.provider.encode(), next.encode());
    expect(config.apiKey, 'new-key');
  });

  test('LLM 密钥保存期间阻止出题，成功或失败后都释放等待状态', () async {
    for (final fail in [false, true]) {
      store.llmEntered = Completer<void>();
      store.llmProceed = Completer<void>();
      store.failLlmWrite = fail;
      final saving = settings.saveLlmProviderConfig(
        id: 'vision',
        name: '看图模型',
        baseUrl: 'https://vision.example.com/v1',
        model: 'gpt-4o-mini',
        apiKey: 'test-llm-key',
      );
      final result = fail
          ? expectLater(saving, throwsStateError)
          : expectLater(saving, completes);
      await store.llmEntered!.future;
      try {
        expect(settings.hasPendingLlmSave, isTrue);
        expect(SettingsRepository().hasPendingLlmSave, isTrue);
      } finally {
        store.llmProceed!.complete();
      }
      await result;
      expect(settings.hasPendingLlmSave, isFalse);
    }
  });

  test('安全存储部分写入失败补偿旧密钥，坏地址及未验证请求零写入', () async {
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'old-key',
    );
    store.failNext = true;
    await expectLater(
      settings.saveImageGenerationConfig(
        provider: _config,
        apiKey: 'new-key',
      ),
      throwsStateError,
    );
    expect(store.key, 'old-key');
    expect(
      () => settings.saveImageGenerationConfig(
        provider: const ImageGenerationProviderConfig(
          name: '',
          baseUrl: 'http://public.example.com',
          model: 'image',
        ),
        apiKey: 'bad',
      ),
      throwsFormatException,
    );
    lockParentForTesting();
    expect(
      () => settings.saveImageGenerationConfig(
        provider: _config,
        apiKey: 'bad',
      ),
      throwsA(isA<ParentAccessDenied>()),
    );
    expect(store.key, 'old-key');
  });

  test('只含生图配置的备份也预检地址：新增、换域名与端口都需要确认，路径变化不触发', () async {
    String backup(ImageGenerationProviderConfig c) => jsonEncode({
          'version': 1,
          'settings': {ImageGenerationProviderConfig.settingsKey: c.encode()},
        });
    expect(
      BackupService.detectLlmEndpointChanges(backup(_config))!.added,
      ['image.example.com'],
    );
    await settings.saveImageGenerationConfig(provider: _config, apiKey: '');
    expect(BackupService.detectLlmEndpointChanges(backup(_config)), isNull);
    expect(
      BackupService.detectLlmEndpointChanges(
        backup(
          const ImageGenerationProviderConfig(
            name: '',
            baseUrl: 'https://image.example.com/compatible/v1',
            model: 'new-image',
          ),
        ),
      ),
      isNull,
    );
    final port = BackupService.detectLlmEndpointChanges(
      backup(
        const ImageGenerationProviderConfig(
          name: '',
          baseUrl: 'https://image.example.com:8443/v1',
          model: 'image',
        ),
      ),
    )!;
    expect(port.changed.single.to, 'image.example.com:8443');
    final host = BackupService.detectLlmEndpointChanges(
      backup(
        const ImageGenerationProviderConfig(
          name: '',
          baseUrl: 'https://other.example.com/v1',
          model: 'image',
        ),
      ),
    )!;
    expect(host.changed.single.label, '图片生成');
    expect(host.changed.single.to, 'other.example.com');
  });

  test('恢复过滤生图配置中的未知密钥，错误凭据归属不覆盖本机密钥', () async {
    final backup = BackupService(secureStore: store);
    final base =
        jsonDecode(await backup.exportToJson(includeCredentials: false))
            as Map<String, dynamic>;
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'local-key',
    );
    base['settings'] = {
      ImageGenerationProviderConfig.settingsKey:
          jsonEncode({..._config.toJson(), 'apiKey': 'must-not-land'}),
    };
    base['credentials'] = await encryptCredentials(
      {
        kCredKeyImageGenerationApiKey: 'wrong-provider-key',
        kCredKeyImageGenerationHint: 'https://wrong.example.com|image',
      },
      'test-passphrase',
    );
    await backup.restoreFromJson(
      jsonEncode(base),
      passphrase: 'test-passphrase',
    );
    expect(store.key, 'local-key');
    expect(
      HiveBoxes.settings.get(ImageGenerationProviderConfig.settingsKey),
      _config.encode(),
    );
    expect(await backup.exportToJson(), isNot(contains('must-not-land')));
  });

  test('多供应商各自保存候选模型和密钥，切换、清除、删除不修改普通供应商', () async {
    await settings.saveLlmProviderConfig(
      id: 'chat',
      name: '普通服务',
      baseUrl: 'https://chat.example.com',
      model: 'chat-model',
      apiKey: '',
    );
    final chatBefore = HiveBoxes.settings.get('llm_providers');
    await settings.saveImageGenerationProviderConfig(
      id: 'first',
      name: '第一个',
      baseUrl: 'https://first.example.com/v1',
      model: 'image-a',
      models: ['image-b', 'image-a', 'image-b'],
      apiKey: 'first-key',
    );
    await settings.saveImageGenerationProviderConfig(
      id: 'second',
      name: '',
      baseUrl: 'https://second.example.com/v1/images/generations',
      model: 'image-c',
      apiKey: 'second-key',
    );
    expect(settings.imageGenerationActiveProviderId, 'first');
    expect(
      settings.imageGenerationProviders.first.models,
      ['image-a', 'image-b'],
    );
    await settings.setImageGenerationActiveProvider('second');
    final runtime = (await SettingsRepository(credentialStore: store)
        .readImageGenerationConfig())!;
    expect(runtime.provider.baseUrl, 'https://second.example.com/v1');
    expect(runtime.apiKey, 'second-key');
    await settings.saveImageGenerationProviderConfig(
      id: 'second',
      name: '',
      baseUrl: 'https://second.example.com/v1',
      model: 'image-c',
      apiKey: '',
    );
    expect(await settings.readImageGenerationApiKeyFor('second'), 'second-key');
    await settings.clearImageGenerationApiKey('second');
    expect(await settings.readImageGenerationApiKeyFor('second'), isNull);
    expect(settings.imageGenerationActiveProviderId, 'second');
    await settings.deleteImageGenerationProviderConfig('second');
    expect(settings.imageGenerationActiveProviderId, 'first');
    expect(store.providerKeys, {'first': 'first-key'});
    expect(HiveBoxes.settings.get('llm_providers'), chatBefore);
    expect(HiveBoxes.settings.get('llm_active_provider_id'), 'chat');
    expect(HiveBoxes.settings.values.toString(), isNot(contains('first-key')));
  });

  test('旧单供应商迁移保留密钥和模型，重复迁移不新增配置', () async {
    await HiveBoxes.settings
        .put(ImageGenerationProviderConfig.settingsKey, _config.encode());
    store.key = 'legacy-key';
    await settings.migrateLegacyImageGenerationConfigIfNeeded();
    await settings.migrateLegacyImageGenerationConfigIfNeeded();
    expect(settings.imageGenerationProviders.single.id, 'image-legacy');
    expect(settings.imageGenerationProviders.single.models, ['image-model']);
    expect((await settings.readImageGenerationConfig())!.apiKey, 'legacy-key');
    expect(
      HiveBoxes.settings.containsKey(ImageGenerationProviderConfig.settingsKey),
      isFalse,
    );
    await settings.saveImageGenerationProviderConfig(
      id: 'other',
      name: '',
      baseUrl: 'https://other.example.com/v1',
      model: 'other-image',
      apiKey: 'other-key',
    );
    await settings.setImageGenerationActiveProvider('other');
    await settings.deleteImageGenerationProviderConfig('image-legacy');
    expect(store.key, isNull);
    expect((await settings.readImageGenerationConfig())!.apiKey, 'other-key');
  });

  test('多供应商与各自加密密钥完整备份恢复，所有供应商地址都参与预检', () async {
    for (final id in ['one', 'two']) {
      await settings.saveImageGenerationProviderConfig(
        id: id,
        name: id,
        baseUrl: 'https://$id.example.com/v1',
        model: 'image-$id',
        models: ['image-$id', 'alternate-$id'],
        apiKey: '$id-private-key',
      );
    }
    await settings.setImageGenerationActiveProvider('two');
    final before = HiveBoxes.settings
        .get(ImageGenerationProviderConfig.providersSettingsKey);
    final backup = BackupService(secureStore: store);
    final data = await backup.exportToJson(passphrase: 'test-passphrase');
    expect(data, isNot(contains('one-private-key')));
    expect(data, isNot(contains('two-private-key')));
    await HiveBoxes.settings.clear();
    await unlockParentForTesting();
    store.providerKeys.clear();
    store.key = null;
    expect(
      BackupService.detectLlmEndpointChanges(data)!.added,
      ['one.example.com', 'two.example.com'],
    );
    await backup.restoreFromJson(data, passphrase: 'test-passphrase');
    expect(
      HiveBoxes.settings
          .get(ImageGenerationProviderConfig.providersSettingsKey),
      before,
    );
    expect(settings.imageGenerationActiveProviderId, 'two');
    expect(
      store.providerKeys,
      {'one': 'one-private-key', 'two': 'two-private-key'},
    );
    expect(
      (await settings.readImageGenerationConfig())!.apiKey,
      'two-private-key',
    );
  });

  test('坏供应商列表不会回退旧配置覆盖本机，明确空列表保持停用', () async {
    await settings.saveImageGenerationProviderConfig(
      id: 'good',
      name: '当前',
      baseUrl: 'https://current.example.com/v1',
      model: 'image',
      apiKey: 'current-key',
    );
    final backup = BackupService(secureStore: store);
    await backup.restoreFromJson(
      jsonEncode({
        'version': 1,
        'settings': {
          ImageGenerationProviderConfig.providersSettingsKey: '[{"id":"bad"}]',
          ImageGenerationProviderConfig.activeProviderSettingsKey: 'bad',
          ImageGenerationProviderConfig.settingsKey: _config.encode(),
        },
      }),
    );
    expect(settings.imageGenerationProviders.single.id, 'good');
    expect((await settings.readImageGenerationConfig())!.apiKey, 'current-key');
    await backup.restoreFromJson(
      jsonEncode({
        'version': 1,
        'settings': {ImageGenerationProviderConfig.providersSettingsKey: '[]'},
      }),
    );
    expect(settings.imageGenerationActiveProviderId, isNull);
    expect(await settings.readImageGenerationConfig(), isNull);
    await settings.migrateLegacyImageGenerationConfigIfNeeded();
    expect(settings.imageGenerationProviders, isEmpty);
  });

  test('恢复过程中生图密钥部分写失败，补偿原密钥及原服务地址', () async {
    await settings.saveImageGenerationConfig(
      provider: _config,
      apiKey: 'backup-key',
    );
    final backup = BackupService(secureStore: store);
    final data = await backup.exportToJson(passphrase: 'test-passphrase');
    final other = const ImageGenerationProviderConfig(
      name: '',
      baseUrl: 'https://other.example.com/v1',
      model: 'other-image',
    );
    await settings.saveImageGenerationConfig(
      provider: other,
      apiKey: 'local-key',
    );
    store.failNext = true;
    await expectLater(
      backup.restoreFromJson(data, passphrase: 'test-passphrase'),
      throwsStateError,
    );
    expect(store.key, 'local-key');
    expect(settings.imageGenerationProvider!.encode(), other.encode());
  });
}
