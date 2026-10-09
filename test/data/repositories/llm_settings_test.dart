// test/data/repositories/llm_settings_test.dart
//
// LLM 多厂商配置存储测试：多配置 CRUD、生效切换、Key 按配置独立
// 存取与空串保留、旧单配置迁移、readLlmConfig 组装、场景级厂商绑定、
// 删除清理与备份导出不含配置列表/Key 明文。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

/// 测试环境无平台安全存储通道，覆写为内存实现。
/// 按 configId 存 Key（对齐真实存储键 `llm_api_key_{configId}`）；
/// 旧单键 llmApiKey 保留，供迁移用例与真实迁移逻辑读写。
/// Tencent / Worker 读方法覆写为内存（返回 null）：BackupService 导出
/// 链先读这两类凭据，不覆写会落到平台通道抛异常，使凭据节整体降级为空。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> llmApiKeysByConfigId = {};
  String? llmApiKey;

  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {
    llmApiKeysByConfigId[configId] = apiKey;
  }

  @override
  Future<String?> readLlmApiKeyFor(String configId) =>
      Future.value(llmApiKeysByConfigId[configId]);

  @override
  Future<void> deleteLlmApiKeyFor(String configId) async {
    llmApiKeysByConfigId.remove(configId);
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

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async => null;

  @override
  Future<String?> readWorkerTtsApiKey() async => null;
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

  Future<void> saveTwo() async {
    await repository.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1/',
      model: 'deepseek-chat',
      apiKey: 'key-p1',
    );
    await repository.saveLlmProviderConfig(
      id: 'p2',
      name: '通义千问',
      baseUrl: 'https://dashscope.example.com',
      model: 'qwen-plus',
      apiKey: 'key-p2',
    );
  }

  test('新增两条配置：列表顺序持久化、Key 按配置独立、第一条自动生效', () async {
    await saveTwo();

    final providers = repository.llmProviders;
    expect(providers.length, 2);
    expect(providers[0].id, 'p1');
    expect(providers[0].name, 'DeepSeek');
    // 末尾斜杠被 normalize 去掉。
    expect(providers[0].baseUrl, 'https://api.deepseek.com/v1');
    expect(providers[0].model, 'deepseek-chat');
    expect(providers[1].id, 'p2');
    expect(providers[1].model, 'qwen-plus');

    // Key 按配置独立存安全存储，互不覆盖。
    expect(credentialStore.llmApiKeysByConfigId['p1'], 'key-p1');
    expect(credentialStore.llmApiKeysByConfigId['p2'], 'key-p2');
    expect(await repository.readLlmApiKeyFor('p1'), 'key-p1');
    expect(await repository.readLlmApiKeyFor('p2'), 'key-p2');

    // 第一条追加时无 active，自动生效。
    expect(repository.llmActiveProviderId, 'p1');

    // Hive 任何值不得包含 Key 明文。
    for (final value in HiveBoxes.settings.values) {
      expect('$value', isNot(contains('key-p1')));
      expect('$value', isNot(contains('key-p2')));
    }
  });

  test('setLlmActiveProvider 切换生效并持久化；未知 id 抛 ArgumentError', () async {
    await saveTwo();

    await repository.setLlmActiveProvider('p2');
    expect(repository.llmActiveProviderId, 'p2');

    // 持久化：新仓储实例重读同一 Hive box。
    final repo2 = SettingsRepository(credentialStore: credentialStore);
    expect(repo2.llmActiveProviderId, 'p2');

    expect(
      () => repository.setLlmActiveProvider('nope'),
      throwsArgumentError,
    );
    // 失败的切换不破坏原值。
    expect(repository.llmActiveProviderId, 'p2');
  });

  test('readLlmConfig 返回当前生效配置；切换生效后随 active 组装', () async {
    await saveTwo();
    // saveTwo 后 active 为 p1。
    var config = await repository.readLlmConfig();
    expect(config, isNotNull);
    expect(config!.baseUrl, 'https://api.deepseek.com/v1');
    expect(config.model, 'deepseek-chat');
    expect(config.apiKey, 'key-p1');

    await repository.setLlmActiveProvider('p2');
    config = await repository.readLlmConfig();
    expect(config!.model, 'qwen-plus');
    expect(config.apiKey, 'key-p2');
  });

  test('空 Key 配置（Ollama）：保存与组装均为空串 Key', () async {
    await repository.saveLlmProviderConfig(
      id: 'local',
      name: 'Ollama',
      baseUrl: 'http://localhost:11434',
      model: 'qwen2.5:7b',
      apiKey: '',
    );

    expect(await repository.readLlmApiKeyFor('local'), isNull);
    final config = await repository.readLlmConfig();
    expect(config, isNotNull);
    expect(config!.hasApiKey, isFalse);
  });

  test('编辑已有配置：Key 留空保留旧 Key；非空覆盖；其他字段更新', () async {
    await saveTwo();

    // Key 留空 = 保留 p1 旧 Key。
    await repository.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek V3',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-reasoner',
      apiKey: '',
    );
    expect(await repository.readLlmApiKeyFor('p1'), 'key-p1');
    final providers = repository.llmProviders;
    expect(providers.length, 2); // 更新不追加。
    expect(providers[0].name, 'DeepSeek V3');
    expect(providers[0].model, 'deepseek-reasoner');

    // Key 非空 = 覆盖。
    await repository.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek V3',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-reasoner',
      apiKey: 'key-p1-new',
    );
    expect(await repository.readLlmApiKeyFor('p1'), 'key-p1-new');
  });

  test('编辑追加不改变 active：仅新增且无有效 active 时自动生效', () async {
    await saveTwo();
    await repository.setLlmActiveProvider('p2');

    // 更新 p1 不改变 active。
    await repository.saveLlmProviderConfig(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
      apiKey: 'key-p1',
    );
    expect(repository.llmActiveProviderId, 'p2');

    // 新增 p3：已有有效 active（p2），不抢占生效。
    await repository.saveLlmProviderConfig(
      id: 'p3',
      name: '',
      baseUrl: 'https://third.example.com/v1',
      model: 'm3',
      apiKey: 'key-p3',
    );
    expect(repository.llmActiveProviderId, 'p2');
    // 空名保存为空串（展示层兜底「配置 N」）。
    expect(repository.llmProviders[2].name, '');
  });

  test(
      '删除非生效配置：active 不变；删除生效配置：切到剩余第一条；'
      '全删后 active 清空、readLlmConfig 返回 null', () async {
    await saveTwo();
    await repository.setLlmActiveProvider('p2');

    // 删除非生效 p1。
    await repository.deleteLlmProviderConfig('p1');
    expect(repository.llmProviders.length, 1);
    expect(repository.llmActiveProviderId, 'p2');
    expect(await repository.readLlmApiKeyFor('p1'), isNull);

    // 删除生效 p2：无剩余 → active 清空。
    await repository.deleteLlmProviderConfig('p2');
    expect(repository.llmProviders, isEmpty);
    expect(HiveBoxes.settings.get('llm_active_provider_id'), isNull);
    expect(credentialStore.llmApiKeysByConfigId, isEmpty);
    expect(await repository.readLlmConfig(), isNull);

    // 删光后重新新增第一条 → 自动生效（active 已清空分支）。
    await repository.saveLlmProviderConfig(
      id: 'p4',
      name: '',
      baseUrl: 'https://fourth.example.com',
      model: 'm4',
      apiKey: '',
    );
    expect(repository.llmActiveProviderId, 'p4');
  });

  test('删除生效配置后切到剩余第一条（三条场景）', () async {
    await saveTwo();
    await repository.saveLlmProviderConfig(
      id: 'p3',
      name: '',
      baseUrl: 'https://third.example.com',
      model: 'm3',
      apiKey: 'key-p3',
    );
    await repository.setLlmActiveProvider('p1');

    await repository.deleteLlmProviderConfig('p1');
    expect(repository.llmActiveProviderId, 'p2');
    final config = await repository.readLlmConfig();
    expect(config!.model, 'qwen-plus');
  });

  test('非法地址抛 FormatException 且不落盘', () async {
    expect(
      () => repository.saveLlmProviderConfig(
        id: 'bad',
        name: '',
        baseUrl: 'not a url',
        model: 'm',
        apiKey: 'k',
      ),
      throwsFormatException,
    );
    expect(repository.llmProviders, isEmpty);
    expect(await repository.readLlmApiKeyFor('bad'), isNull);
  });

  test('llmActiveProviderId 自愈：悬空 active 回落第一条并写回', () async {
    await saveTwo();
    // 手工注入悬空 active（模拟手工删 Hive key 后的残留）。
    await HiveBoxes.settings.put('llm_active_provider_id', 'gone');
    // getter 触发自愈：回落 p1 并写回 Hive。
    expect(repository.llmActiveProviderId, 'p1');
    expect(HiveBoxes.settings.get('llm_active_provider_id'), 'p1');
    // 新实例重读自愈后的值。
    final repo2 = SettingsRepository(credentialStore: credentialStore);
    expect(repo2.llmActiveProviderId, 'p1');
  });

  test('坏 JSON 列表解码为空（decodeList 防御）', () async {
    await HiveBoxes.settings.put('llm_providers', 'not-json');
    expect(repository.llmProviders, isEmpty);
    expect(repository.llmActiveProviderId, isNull);
  });

  test(
    '追加时 active 判断走原始存储值：首条追加设 active、'
    '有效 active 下追加不变、悬空 active 被修复',
    () async {
      // 首条追加：原始存储无 active → 新配置设为生效。
      await repository.saveLlmProviderConfig(
        id: 'first',
        name: 'First',
        baseUrl: 'https://first.example.com',
        model: 'm1',
        apiKey: 'key-first',
      );
      expect(
        HiveBoxes.settings.get('llm_active_provider_id'),
        'first',
        reason: '首条追加应直接写原始存储 active',
      );

      // 已有有效 active 下追加：保持不变。
      await repository.saveLlmProviderConfig(
        id: 'second',
        name: 'Second',
        baseUrl: 'https://second.example.com',
        model: 'm2',
        apiKey: 'key-second',
      );
      expect(HiveBoxes.settings.get('llm_active_provider_id'), 'first');

      // 悬空 active（配置被删后残留）下追加：新配置接管生效。
      await HiveBoxes.settings.put('llm_active_provider_id', 'gone');
      await repository.saveLlmProviderConfig(
        id: 'third',
        name: 'Third',
        baseUrl: 'https://third.example.com',
        model: 'm3',
        apiKey: '',
      );
      expect(HiveBoxes.settings.get('llm_active_provider_id'), 'third');
    },
  );

  test(
    'clearLlmApiKey：删除指定配置的 Key，配置本身与 active 不受影响；'
    '无已存 Key 时调用无副作用',
    () async {
      await saveTwo();

      // 清除 p1 的 Key。
      await repository.clearLlmApiKey('p1');
      expect(await repository.readLlmApiKeyFor('p1'), isNull);
      // 其他配置的 Key 不受影响。
      expect(await repository.readLlmApiKeyFor('p2'), 'key-p2');
      // 配置本身保留，active 不受影响。
      expect(repository.llmProviders.length, 2);
      expect(repository.llmActiveProviderId, 'p1');

      // 无已存 Key 时调用无副作用（不抛、不产生任何变化）。
      await repository.clearLlmApiKey('p1');
      await repository.clearLlmApiKey('never-saved');
      expect(await repository.readLlmApiKeyFor('p1'), isNull);
      expect(repository.llmProviders.length, 2);
    },
  );

  group('旧单配置迁移 migrateLegacyLlmConfigIfNeeded', () {
    test('旧三 key + llm_api_key → 第一条配置：Key 复制、旧 key 清除、幂等', () async {
      // 模拟旧版落盘状态。
      await HiveBoxes.settings.put('llm_base_url', 'https://old.example.com');
      await HiveBoxes.settings.put('llm_model', 'old-model');
      await HiveBoxes.settings.put('llm_provider_name', '旧厂商');
      credentialStore.llmApiKey = 'legacy-key';

      await repository.migrateLegacyLlmConfigIfNeeded();

      final providers = repository.llmProviders;
      expect(providers.length, 1);
      expect(providers[0].baseUrl, 'https://old.example.com');
      expect(providers[0].model, 'old-model');
      expect(providers[0].name, '旧厂商');
      expect(repository.llmActiveProviderId, providers[0].id);
      // 旧 Key 复制到新键位，旧单 Key 删除。
      expect(
        await repository.readLlmApiKeyFor(providers[0].id),
        'legacy-key',
      );
      expect(credentialStore.llmApiKey, isNull);
      // 旧三 key 清除。
      expect(HiveBoxes.settings.get('llm_base_url'), isNull);
      expect(HiveBoxes.settings.get('llm_model'), isNull);
      expect(HiveBoxes.settings.get('llm_provider_name'), isNull);

      // 幂等：再跑一次不产生第二条配置。
      await repository.migrateLegacyLlmConfigIfNeeded();
      expect(repository.llmProviders.length, 1);

      // readLlmConfig 迁移后组装成功。
      final config = await repository.readLlmConfig();
      expect(config!.apiKey, 'legacy-key');
      expect(config.model, 'old-model');
    });

    test('旧配置无 Key（Ollama）：迁移不写 Key、旧 key 仍被清除', () async {
      await HiveBoxes.settings.put('llm_base_url', 'http://localhost:11434');
      await HiveBoxes.settings.put('llm_model', 'qwen2.5:7b');

      await repository.migrateLegacyLlmConfigIfNeeded();

      final providers = repository.llmProviders;
      expect(providers.length, 1);
      expect(await repository.readLlmApiKeyFor(providers[0].id), isNull);
      expect(HiveBoxes.settings.get('llm_base_url'), isNull);
      final config = await repository.readLlmConfig();
      expect(config!.hasApiKey, isFalse);
    });

    test('未配置旧地址：迁移为空操作，不生成配置', () async {
      await repository.migrateLegacyLlmConfigIfNeeded();
      expect(repository.llmProviders, isEmpty);
      expect(HiveBoxes.settings.get('llm_providers'), isNull);
    });

    test(
      '并发去重：Future.wait 两次迁移只跑一遍，无孤儿 llm_api_key_{id}',
      () async {
        // 模拟旧版落盘状态。
        await HiveBoxes.settings.put('llm_base_url', 'https://old.example.com');
        await HiveBoxes.settings.put('llm_model', 'old-model');
        await HiveBoxes.settings.put('llm_provider_name', '旧厂商');
        credentialStore.llmApiKey = 'legacy-key';

        // 两场景并发首启（如 readLlmConfig 与设置页 initState 同时
        // 调用）：共享同一 in-flight Future，只执行一次迁移。
        await Future.wait([
          repository.migrateLegacyLlmConfigIfNeeded(),
          repository.migrateLegacyLlmConfigIfNeeded(),
        ]);

        // 配置列表只写一份。
        final providers = repository.llmProviders;
        expect(providers.length, 1);
        expect(providers[0].baseUrl, 'https://old.example.com');
        // 安全存储只留一个配置键位（无第一份孤儿 Key）。
        expect(credentialStore.llmApiKeysByConfigId.length, 1);
        expect(
          credentialStore.llmApiKeysByConfigId[providers[0].id],
          'legacy-key',
        );
        // 旧单 Key 已被清除（迁移完成语义不因去重打折）。
        expect(credentialStore.llmApiKey, isNull);
        // active 指向迁移出的唯一配置。
        expect(repository.llmActiveProviderId, providers[0].id);

        // in-flight 已清空：后续再调用是幂等空操作（非复用旧 Future）。
        await repository.migrateLegacyLlmConfigIfNeeded();
        expect(repository.llmProviders.length, 1);
      },
    );

    test('已有列表：即使残留旧三 key 也不迁移（列表优先）', () async {
      await saveTwo();
      await HiveBoxes.settings.put('llm_base_url', 'https://old.example.com');

      await repository.migrateLegacyLlmConfigIfNeeded();
      expect(repository.llmProviders.length, 2);
      expect(HiveBoxes.settings.get('llm_base_url'), 'https://old.example.com');
    });
  });

  group('场景级厂商绑定', () {
    test('三场景默认 null（跟随默认 active）', () async {
      await saveTwo();
      for (final scenario in LlmScenario.values) {
        expect(repository.providerIdForScenario(scenario), isNull);
      }
      // 未绑定时按 active 组装。
      final config =
          await repository.readLlmConfigForScenario(LlmScenario.poemExplain);
      expect(config!.model, 'deepseek-chat');
    });

    test('set/get 往返并持久化；各场景互不干扰', () async {
      await saveTwo();

      await repository.setProviderIdForScenario(LlmScenario.poemExplain, 'p2');
      expect(repository.providerIdForScenario(LlmScenario.poemExplain), 'p2');
      // 其他场景不受影响。
      expect(repository.providerIdForScenario(LlmScenario.mathExplain), isNull);
      expect(repository.providerIdForScenario(LlmScenario.wordProblem), isNull);

      // 持久化：新仓储实例重读同一 Hive box。
      final repo2 = SettingsRepository(credentialStore: credentialStore);
      expect(repo2.providerIdForScenario(LlmScenario.poemExplain), 'p2');

      // 场景配置参与组装：诗词走 p2，默认 active 仍是 p1。
      final poemConfig =
          await repository.readLlmConfigForScenario(LlmScenario.poemExplain);
      expect(poemConfig!.model, 'qwen-plus');
      expect(poemConfig.apiKey, 'key-p2');
      final mathConfig =
          await repository.readLlmConfigForScenario(LlmScenario.mathExplain);
      expect(mathConfig!.model, 'deepseek-chat');
      expect((await repository.readLlmConfig())!.model, 'deepseek-chat');
    });

    test('null 清除绑定 → 回落跟随默认', () async {
      await saveTwo();
      await repository.setProviderIdForScenario(LlmScenario.mathExplain, 'p2');
      expect(repository.providerIdForScenario(LlmScenario.mathExplain), 'p2');

      await repository.setProviderIdForScenario(LlmScenario.mathExplain, null);
      expect(repository.providerIdForScenario(LlmScenario.mathExplain), isNull);
      expect(
        HiveBoxes.settings.get('llm_provider_math_explain'),
        isNull,
      );
      final config =
          await repository.readLlmConfigForScenario(LlmScenario.mathExplain);
      expect(config!.model, 'deepseek-chat');
    });

    test('悬空绑定读时回落 null 且不写回 Hive', () async {
      await saveTwo();
      // 手工注入悬空绑定（模拟手工删 Hive key 后的残留）。
      await HiveBoxes.settings.put('llm_provider_poem_explain', 'gone');

      expect(repository.providerIdForScenario(LlmScenario.poemExplain), isNull);
      // 读时不自愈写回（与 active 的自愈策略不同）。
      expect(HiveBoxes.settings.get('llm_provider_poem_explain'), 'gone');
      // 组装回落到默认 active。
      final config =
          await repository.readLlmConfigForScenario(LlmScenario.poemExplain);
      expect(config!.model, 'deepseek-chat');
    });

    test('非法 id set 抛 ArgumentError 且不落盘', () async {
      await saveTwo();
      expect(
        () => repository.setProviderIdForScenario(
          LlmScenario.wordProblem,
          'nope',
        ),
        throwsArgumentError,
      );
      expect(HiveBoxes.settings.get('llm_provider_word_problem'), isNull);
      expect(repository.providerIdForScenario(LlmScenario.wordProblem), isNull);
    });

    test('删除配置联动清理指向它的场景绑定；其他场景绑定保留', () async {
      await saveTwo();
      await repository.setProviderIdForScenario(LlmScenario.poemExplain, 'p1');
      await repository.setProviderIdForScenario(LlmScenario.mathExplain, 'p2');

      await repository.deleteLlmProviderConfig('p1');

      // 指向被删 id 的绑定 key 被物理清理（不只是读时回落）。
      expect(HiveBoxes.settings.get('llm_provider_poem_explain'), isNull);
      expect(repository.providerIdForScenario(LlmScenario.poemExplain), isNull);
      // 未受影响的绑定保留。
      expect(repository.providerIdForScenario(LlmScenario.mathExplain), 'p2');
      // 诗词场景回落到剩余 active（p2）。
      final config =
          await repository.readLlmConfigForScenario(LlmScenario.poemExplain);
      expect(config!.model, 'qwen-plus');
    });

    test('无任何配置时场景组装返回 null', () async {
      final config =
          await repository.readLlmConfigForScenario(LlmScenario.mathExplain);
      expect(config, isNull);
    });

    test('场景绑定不随备份导出（设备绑定）', () async {
      await saveTwo();
      await repository.setProviderIdForScenario(LlmScenario.poemExplain, 'p2');
      await repository.setProviderIdForScenario(LlmScenario.mathExplain, 'p1');
      await repository.setProviderIdForScenario(LlmScenario.wordProblem, 'p1');

      final exported =
          await BackupService(secureStore: credentialStore).exportToJson();
      final settingsNode = (jsonDecode(exported)
          as Map<String, dynamic>)['settings'] as Map<String, dynamic>;
      for (final scenario in LlmScenario.values) {
        expect(
          settingsNode.containsKey(scenario.settingsKey),
          isFalse,
          reason: '场景 key 不应导出: ${scenario.settingsKey}',
        );
      }
    });

    test('readLlmConfig 委托 word_problem 场景：绑定后返回绑定配置（非 active）', () async {
      await saveTwo();
      await repository.setProviderIdForScenario(LlmScenario.wordProblem, 'p2');

      final config = await repository.readLlmConfig();
      expect(config!.model, 'qwen-plus');
      expect(config.apiKey, 'key-p2');
      // 默认 active 不因场景绑定而改变。
      expect(repository.llmActiveProviderId, 'p1');
    });

    test('readLlmConfig 无绑定时仍读默认 active（委托等价回归）', () async {
      await saveTwo();

      // 默认 active = p1。
      expect((await repository.readLlmConfig())!.model, 'deepseek-chat');

      // 切换 active 后随 active 组装（无场景绑定不改变该行为）。
      await repository.setLlmActiveProvider('p2');
      expect((await repository.readLlmConfig())!.model, 'qwen-plus');
    });
  });

  test(
      '备份导出：不含 llm_providers / active id / Key 明文；'
      '凭据白名单维持单 llm_api_key', () async {
    await saveTwo();

    final backup = BackupService(secureStore: credentialStore);
    final exported = await backup.exportToJson(passphrase: 'pw');

    expect(exported, isNot(contains('key-p1')));
    expect(exported, isNot(contains('key-p2')));
    final settingsNode = (jsonDecode(exported)
        as Map<String, dynamic>)['settings'] as Map<String, dynamic>;
    expect(settingsNode.containsKey('llm_providers'), isFalse);
    expect(settingsNode.containsKey('llm_active_provider_id'), isFalse);

    // 凭据加密节维持单 llm_api_key 条目语义。
    expect(kBackupCredentialKeys, contains('llm_api_key'));
    // 归属提示（host|model，非敏感）只进加密节。
    expect(kBackupCredentialKeys, contains('llm_api_key_hint'));
  });

  test(
      '备份恢复凭据：llm_api_key 写入本机 active 配置位；'
      '无 active 则丢弃不报错', () async {
    // 本机已有 active=p1。
    await saveTwo();

    // 无凭据节旧备份：不报错、Key 不变。
    final legacyJson = jsonEncode(<String, dynamic>{
      'version': 1,
      'settings': <String, dynamic>{'theme_mode': 'light'},
    });
    await BackupService(secureStore: credentialStore)
        .restoreFromJson(legacyJson);
    expect(await repository.readLlmApiKeyFor('p1'), 'key-p1');

    // 含 llm_api_key 的备份：恢复写入本机 active 位置（覆盖）。
    final cipher = BackupService(secureStore: credentialStore);
    final restoredJson = await _buildBackupWithLlmKey('pw', 'key-from-backup');
    await cipher.restoreFromJson(restoredJson, passphrase: 'pw');
    expect(await repository.readLlmApiKeyFor('p1'), 'key-from-backup');

    // 无 active 机器恢复含 Key 备份：丢弃、不报错（全新 Hive + 全新
    // 凭据 Store，避免上面恢复写入的条目残留干扰断言）。
    await tearDownHiveForTesting();
    await setUpHiveForTesting();
    final freshStore = _MemoryCredentialStore();
    final fresh = BackupService(secureStore: freshStore);
    await fresh.restoreFromJson(
      await _buildBackupWithLlmKey('pw', 'key-again'),
      passphrase: 'pw',
    );
    expect(freshStore.llmApiKeysByConfigId, isEmpty);
  });

  test('备份导出：active key 伴随 llm_api_key_hint（host|model）', () async {
    await saveTwo();

    final exported = await BackupService(secureStore: credentialStore)
        .exportToJson(passphrase: 'pw');
    final credentialsNode = (jsonDecode(exported)
        as Map<String, dynamic>)['credentials'] as Map<String, dynamic>?;
    // p1 带 Key：凭据节必存在。
    expect(credentialsNode, isNotNull);
    final payload = await decryptCredentials(credentialsNode!, 'pw');

    // p1 为 active：host|model 对应 p1（末尾斜杠已 normalize）。
    expect(payload['llm_api_key'], 'key-p1');
    expect(payload['llm_api_key_hint'], 'api.deepseek.com|deepseek-chat');
  });

  test(
    '备份恢复（hint 匹配）：key 写回匹配配置槽位；'
    '换 active 后恢复不错位（A 的 key 不进 B 槽位）', () async {
    // 导出机：p1（DeepSeek）为 active 且带 key。
    await saveTwo();
    final exported = await BackupService(secureStore: credentialStore)
        .exportToJson(passphrase: 'pw');

    // 本机导出后切 active 到 p2（错位场景的触发条件）。
    await repository.setLlmActiveProvider('p2');
    expect(await repository.readLlmApiKeyFor('p1'), 'key-p1');
    expect(await repository.readLlmApiKeyFor('p2'), 'key-p2');

    await BackupService(secureStore: credentialStore)
        .restoreFromJson(exported, passphrase: 'pw');

    // hint 匹配 p1：key 写回 p1 槽位（而非当时 active 的 p2）。
    expect(await repository.readLlmApiKeyFor('p1'), 'key-p1');
    expect(await repository.readLlmApiKeyFor('p2'), 'key-p2');
  });

  test('备份恢复（hint 匹配）：本机无匹配配置时 key 丢弃', () async {
    // 导出机：p1（DeepSeek）为 active 且带 key。
    await saveTwo();
    final exported = await BackupService(secureStore: credentialStore)
        .exportToJson(passphrase: 'pw');

    // 恢复到「无匹配配置」机：只有地址/模型不同的 p9，active 指向它。
    await tearDownHiveForTesting();
    await setUpHiveForTesting();
    final freshStore = _MemoryCredentialStore();
    final freshRepo = SettingsRepository(credentialStore: freshStore);
    await freshRepo.saveLlmProviderConfig(
      id: 'p9',
      name: 'Other',
      baseUrl: 'https://other.example.com',
      model: 'other-model',
      apiKey: '',
    );

    await BackupService(secureStore: freshStore)
        .restoreFromJson(exported, passphrase: 'pw');

    // hint 匹配不到任何本机配置：key 丢弃，p9 的 Key 不被污染。
    expect(freshStore.llmApiKeysByConfigId['p9'], isNull);
    expect(freshStore.llmApiKeysByConfigId.length, 0);
  });

  test(
    '备份恢复（旧备份无 hint）：维持现行为写本机 active 槽位',
    () async {
      // 本机已有 p1/p2，active = p2。
      await saveTwo();
      await repository.setLlmActiveProvider('p2');

      // 旧备份：加密节只含 llm_api_key、无 hint。
      final legacyJson = await _buildBackupWithLlmKey('pw', 'key-legacy');
      await BackupService(secureStore: credentialStore)
          .restoreFromJson(legacyJson, passphrase: 'pw');

      // 无 hint → 写本机 active（p2）槽位。
      expect(await repository.readLlmApiKeyFor('p2'), 'key-legacy');
      expect(await repository.readLlmApiKeyFor('p1'), 'key-p1');
    },
  );
}

/// 构造带加密 llm_api_key 凭据节的备份 JSON。
Future<String> _buildBackupWithLlmKey(
  String passphrase,
  String llmApiKey,
) async {
  final credentials = await encryptCredentials(
    <String, String>{'llm_api_key': llmApiKey},
    passphrase,
  );
  return jsonEncode(<String, dynamic>{
    'version': 1,
    'settings': <String, dynamic>{'theme_mode': 'light'},
    'credentials': credentials,
  });
}
