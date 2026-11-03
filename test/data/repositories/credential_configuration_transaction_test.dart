import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

class _Credentials extends SecureCredentialStore {
  final llm = <String, String>{};
  final dav = <String, ({String username, String password})>{};
  final failLlmValues = <String>{};
  Completer<void>? entered;
  Completer<void>? proceed;
  bool failAfterWrite = false;

  Future<void> _afterWrite() async {
    final gate = proceed;
    if (gate != null) {
      proceed = null;
      entered!.complete();
      await gate.future;
    }
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('synthetic partial secure-storage failure');
    }
  }

  @override
  Future<String?> readLlmApiKey() async => null;
  @override
  Future<void> deleteLlmApiKey() async {}
  @override
  Future<String?> readLlmApiKeyFor(String id) async => llm[id];
  @override
  Future<void> saveLlmApiKeyFor(String id, String key) async {
    if (failLlmValues.contains(key)) {
      throw StateError('synthetic rollback failure');
    }
    llm[id] = key;
    await _afterWrite();
  }

  @override
  Future<void> deleteLlmApiKeyFor(String id) async {
    llm.remove(id);
  }

  @override
  Future<({String username, String password})?> readWebDavCredentials(
    String id,
  ) async =>
      dav[id];
  @override
  Future<void> saveWebDavCredentials({
    required String configId,
    required String username,
    required String password,
  }) async {
    dav[configId] = (username: username, password: password);
    await _afterWrite();
  }

  @override
  Future<void> deleteWebDavCredentials(String id) async {
    dav.remove(id);
  }
}

class _FailingSettings extends Fake implements Box<dynamic> {
  _FailingSettings(this.real, this.failedKey, {this.afterWrite = false});
  final Box<dynamic> real;
  final String failedKey;
  final bool afterWrite;
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
    if (key == failedKey && !failed) {
      failed = true;
      if (afterWrite) await real.put(key, value);
      throw const FileSystemException('synthetic disk full');
    }
    await real.put(key, value);
  }
}

WebDavConfig _dav(String server) => WebDavConfig(
      id: 'dav',
      name: server,
      url: 'https://$server.example',
      username: 'user-$server',
      password: 'synthetic-pass-$server',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Box<dynamic> originalSettings;
  late _Credentials store;
  late SettingsRepository settings;
  Future<void> saveLlm(String server, {String? key}) =>
      settings.saveLlmProviderConfig(
        id: 'provider',
        name: server,
        baseUrl: 'https://$server.example/v1',
        model: 'model',
        apiKey: key ?? 'synthetic-key-$server',
      );

  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    originalSettings = HiveBoxes.settings;
    store = _Credentials();
    settings = SettingsRepository(credentialStore: store);
  });
  tearDown(() async {
    HiveBoxes.settings = originalSettings;
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  for (final afterWrite in [false, true]) {
    test(
        'LLM metadata failure restores endpoint and key (partial write: $afterWrite)',
        () async {
      await saveLlm('a');
      HiveBoxes.settings = _FailingSettings(
        originalSettings,
        'llm_providers',
        afterWrite: afterWrite,
      );
      await expectLater(saveLlm('b'), throwsA(isA<FileSystemException>()));
      HiveBoxes.settings = originalSettings;
      final config =
          (await settings.readLlmConfigForScenario(LlmScenario.assistant))!;
      final transport = MockClient((request) async {
        expect(request.url.host, 'a.example');
        expect(request.headers['Authorization'], 'Bearer synthetic-key-a');
        return http.Response('{"data":[{"id":"model"}]}', 200);
      });
      final client = LlmClient(httpClient: transport);
      addTearDown(client.close);
      await client.listModels(config);
    });
  }

  test('WebDAV metadata failure restores credentials before next request',
      () async {
    await settings.saveWebDavConfig(_dav('a'));
    HiveBoxes.settings = _FailingSettings(originalSettings, 'webdav_configs');
    await expectLater(
      settings.saveWebDavConfig(_dav('b')),
      throwsA(isA<FileSystemException>()),
    );
    HiveBoxes.settings = originalSettings;
    final config = await settings
        .loadWebDavConfigWithCredentials(settings.webDavConfigs.single);
    final transport = MockClient((request) async {
      expect(request.url.host, 'a.example');
      expect(
        request.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('user-a:synthetic-pass-a'))}',
      );
      return http.Response('{"version":1}', 200);
    });
    final client = WebDavService(client: transport);
    addTearDown(client.dispose);
    await client.download(config);
  });

  test(
      'partial secure write is compensated even when it throws after changing data',
      () async {
    await settings.saveWebDavConfig(_dav('a'));
    store.failAfterWrite = true;
    await expectLater(settings.saveWebDavConfig(_dav('b')), throwsStateError);
    final config = await settings
        .loadWebDavConfigWithCredentials(settings.webDavConfigs.single);
    expect(config.url, 'https://a.example');
    expect(config.password, 'synthetic-pass-a');
  });

  test('LLM reader waits for a complete save across repository instances',
      () async {
    await saveLlm('a');
    store.entered = Completer<void>();
    final gate = store.proceed = Completer<void>();
    final saving = saveLlm('b');
    await store.entered!.future;
    var readFinished = false;
    final reading = SettingsRepository(credentialStore: store)
        .readLlmConfigForScenario(LlmScenario.assistant)
        .then((config) {
      readFinished = true;
      return config;
    });
    await Future<void>.delayed(Duration.zero);
    expect(readFinished, isFalse);
    gate.complete();
    await saving;
    final config = (await reading)!;
    expect(Uri.parse(config.baseUrl).host, 'b.example');
    expect(config.apiKey, 'synthetic-key-b');
  });

  test(
      'WebDAV loads current metadata instead of injecting a new password into a stale URL',
      () async {
    await settings.saveWebDavConfig(_dav('a'));
    final old = settings.webDavConfigs.single;
    await settings.saveWebDavConfig(_dav('b'));
    final config = await settings.loadWebDavConfigWithCredentials(old);
    expect(config.url, 'https://b.example');
    expect(config.password, 'synthetic-pass-b');
  });

  test(
      'rollback failure blocks credentials persistently until an explicit replacement',
      () async {
    await saveLlm('a');
    store.failLlmValues.add('synthetic-key-a');
    HiveBoxes.settings = _FailingSettings(originalSettings, 'llm_providers');
    await expectLater(saveLlm('b'), throwsFormatException);
    HiveBoxes.settings = originalSettings;
    await HiveBoxes.meta.close();
    HiveBoxes.meta = await Hive.openBox<dynamic>(
      HiveKeys.metaBox,
      crashRecovery: false,
    );
    final restarted = SettingsRepository(credentialStore: store);
    await expectLater(
      restarted.readLlmConfigForScenario(LlmScenario.assistant),
      throwsFormatException,
    );
    await expectLater(
      restarted.readLlmApiKeyFor('provider'),
      throwsFormatException,
    );
    await expectLater(saveLlm('c', key: ''), throwsFormatException);
    await saveLlm('c');
    final config =
        (await restarted.readLlmConfigForScenario(LlmScenario.assistant))!;
    expect(Uri.parse(config.baseUrl).host, 'c.example');
    expect(config.apiKey, 'synthetic-key-c');
  });

  test('locking and unlocking during save revokes the original operation',
      () async {
    await saveLlm('a');
    store.entered = Completer<void>();
    final gate = store.proceed = Completer<void>();
    final failure =
        expectLater(saveLlm('b'), throwsA(isA<ParentAccessDenied>()));
    await store.entered!.future;
    lockParentForTesting();
    await unlockParentForTesting();
    gate.complete();
    await failure;
    expect(store.llm['provider'], 'synthetic-key-a');
    expect(settings.llmProviders.single.name, 'a');
  });
}
