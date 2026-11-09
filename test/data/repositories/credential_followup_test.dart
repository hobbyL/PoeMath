import 'dart:async';

import 'package:hive/hive.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/core/services/tts/tts_models.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _Store extends SecureCredentialStore {
  String? workerKey;
  String? failWorkerValue;
  bool failDelete = false;
  Completer<void>? workerEntered;
  Completer<void>? workerProceed;
  String? imageKey;
  VoidCallback? afterWorkerWrite;
  @override
  Future<String?> readWorkerTtsApiKey() async => workerKey;
  @override
  Future<void> saveWorkerTtsApiKey(String value) async {
    if (failWorkerValue == value) {
      throw StateError('synthetic rollback failure');
    }
    workerKey = value;
    final gate = workerProceed;
    if (gate != null) {
      workerProceed = null;
      workerEntered!.complete();
      await gate.future;
    }
    afterWorkerWrite?.call();
  }

  @override
  Future<void> deleteWorkerTtsApiKey() async {
    workerKey = null;
    if (failDelete) throw StateError('synthetic partial delete failure');
  }

  @override
  Future<String?> readImageGenerationApiKeyFor(String id) async => imageKey;
  @override
  Future<void> saveImageGenerationApiKeyFor(String id, String value) async =>
      imageKey = value;
  @override
  Future<void> deleteImageGenerationApiKeyFor(String id) async =>
      imageKey = null;
}

typedef VoidCallback = void Function();

class _FailingSettings extends Fake implements Box<dynamic> {
  _FailingSettings(this.real);
  final Box<dynamic> real;
  bool failed = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      real.get(key, defaultValue: defaultValue);
  @override
  bool containsKey(dynamic key) => real.containsKey(key);
  @override
  Future<void> delete(dynamic key) => real.delete(key);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    await real.put(key, value);
    if (key == 'tts_cloud_base_url' && !failed) {
      failed = true;
      throw StateError('synthetic partial settings write failure');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Box<dynamic> originalSettings;
  late _Store store;
  late SettingsRepository settings;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    originalSettings = HiveBoxes.settings;
    store = _Store();
    settings = SettingsRepository(credentialStore: store);
  });
  tearDown(() async {
    HiveBoxes.settings = originalSettings;
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('云朗读保存中锁定补偿旧地址、密钥和验证状态', () async {
    await settings.saveWorkerTtsConfig(
      baseUrl: 'https://old.example.com',
      apiKey: 'old-fixture-key',
    );
    await settings.markWorkerTtsVerified();
    store.afterWorkerWrite = lockParentForTesting;
    await expectLater(
      settings.saveWorkerTtsConfig(
        baseUrl: 'https://new.example.com',
        apiKey: 'new-fixture-key',
      ),
      throwsA(isA<ParentAccessDenied>()),
    );
    expect(settings.ttsCloudBaseUrl, 'https://old.example.com');
    expect(store.workerKey, 'old-fixture-key');
    expect(await settings.isWorkerTtsVerified(), isTrue);
  });

  test('排队生图保存锁定后重新解锁仍失效，新请求可以保存', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final queue = PictureStoryRepository.exclusive(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final saving = settings.saveImageGenerationConfig(
      provider: const ImageGenerationProviderConfig(
        name: '待废弃的旧操作',
        baseUrl: 'https://image.example.com',
        model: 'image-test',
      ),
      apiKey: 'fixture-image-key',
    );
    final rejected = expectLater(saving, throwsA(isA<ParentAccessDenied>()));
    lockParentForTesting();
    await unlockParentForTesting();
    release.complete();
    await queue;
    await rejected;
    expect(settings.imageGenerationProvider, isNull);
    expect(store.imageKey, isNull);
    await settings.saveImageGenerationConfig(
      provider: const ImageGenerationProviderConfig(
        name: '新操作',
        baseUrl: 'https://image.example.com',
        model: 'image-test',
      ),
      apiKey: 'fixture-new-key',
    );
    expect(settings.imageGenerationProvider!.name, '新操作');
    expect(store.imageKey, 'fixture-new-key');
  });
  Future<void> seedWorker() async {
    await settings.saveWorkerTtsConfig(
      baseUrl: 'https://old.example.com',
      apiKey: 'old-fixture-key',
    );
    await settings.markWorkerTtsVerified();
    await settings.setTtsCloudEnabled(true);
  }

  test('云朗读地址部分写入失败，完整补偿旧配置', () async {
    await seedWorker();
    HiveBoxes.settings = _FailingSettings(originalSettings);
    await expectLater(
      settings.saveWorkerTtsConfig(
        baseUrl: 'https://new.example.com',
        apiKey: 'new-fixture-key',
      ),
      throwsStateError,
    );
    expect(settings.ttsCloudBaseUrl, 'https://old.example.com');
    expect(store.workerKey, 'old-fixture-key');
    expect(await settings.isWorkerTtsVerified(), isTrue);
    expect(settings.ttsCloudEnabled, isTrue);
  });

  test('云朗读补偿失败留下持久标记，重新保存后才允许读取', () async {
    await seedWorker();
    HiveBoxes.settings = _FailingSettings(originalSettings);
    store.failWorkerValue = 'old-fixture-key';
    await expectLater(
      settings.saveWorkerTtsConfig(
        baseUrl: 'https://new.example.com',
        apiKey: 'new-fixture-key',
      ),
      throwsFormatException,
    );
    final reopened = SettingsRepository(credentialStore: store);
    await expectLater(reopened.readWorkerTtsConfig(), throwsFormatException);
    await expectLater(reopened.markWorkerTtsVerified(), throwsFormatException);
    store.failWorkerValue = null;
    HiveBoxes.settings = originalSettings;
    await reopened.saveWorkerTtsConfig(
      baseUrl: 'https://fixed.example.com',
      apiKey: 'fixed-fixture-key',
    );
    expect((await reopened.readWorkerTtsConfig())!.apiKey, 'fixed-fixture-key');
    expect(await reopened.isWorkerTtsVerified(), isFalse);
  });

  test('云朗读删除密钥后异常恢复原配置和开关', () async {
    await seedWorker();
    store.failDelete = true;
    await expectLater(settings.deleteWorkerTtsConfig(), throwsStateError);
    expect(store.workerKey, 'old-fixture-key');
    expect(settings.ttsCloudEnabled, isTrue);
    expect(await settings.isWorkerTtsVerified(), isTrue);
  });

  test('验证A后配置变为B，不能把B标记已验证', () async {
    await seedWorker();
    final verified = (await settings.readWorkerTtsConfig())!;
    await settings.saveWorkerTtsConfig(
      baseUrl: 'https://new.example.com',
      apiKey: 'new-fixture-key',
    );
    await expectLater(
      settings.markWorkerTtsVerified(expectedConfig: verified),
      throwsFormatException,
    );
    expect(await settings.isWorkerTtsVerified(), isFalse);
    final current = (await settings.readWorkerTtsConfig())!;
    await settings.markWorkerTtsVerified(expectedConfig: current);
    expect(await settings.isWorkerTtsVerified(), isTrue);
  });

  test('跨仓储读取等待完整云朗读保存，不读取中间态', () async {
    await seedWorker();
    store.workerEntered = Completer<void>();
    final gate = store.workerProceed = Completer<void>();
    final saving = settings.saveWorkerTtsConfig(
      baseUrl: 'https://new.example.com',
      apiKey: 'new-fixture-key',
    );
    await store.workerEntered!.future;
    WorkerTtsConfig? observed;
    final reading = SettingsRepository(credentialStore: store)
        .readWorkerTtsConfig()
        .then((value) => observed = value);
    await Future<void>.delayed(Duration.zero);
    expect(observed, isNull);
    gate.complete();
    await saving;
    await reading;
    expect(observed!.base.toString(), 'https://new.example.com');
    expect(observed!.apiKey, 'new-fixture-key');
  });
}
