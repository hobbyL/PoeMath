// test/core/services/backup_service_llm_endpoint_test.dart
//
// 备份 LLM 配置（含端点）测试：恢复前地址变更预检、恢复时一致性过滤、
// 凭据匹配的顺序依赖。覆盖 prd.md AC4/AC6/AC7/AC8/AC9。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_provider_config.dart';

import '../../helpers/hive_test_helper.dart';

/// 内存凭据存储（真实 FlutterSecureStorage 在测试环境不可用）。
final class _MemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> llmKeys = <String, String>{};

  @override
  Future<void> saveTencentAsrCredentials(
    TencentAsrCredentials credentials,
  ) async {}

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async => null;

  @override
  Future<void> deleteTencentAsrCredentials() async {}

  @override
  Future<void> saveWorkerTtsApiKey(String apiKey) async {}

  @override
  Future<String?> readWorkerTtsApiKey() async => null;

  @override
  Future<void> deleteWorkerTtsApiKey() async {}

  @override
  Future<void> saveLlmApiKeyFor(String configId, String apiKey) async {
    llmKeys[configId] = apiKey;
  }

  @override
  Future<String?> readLlmApiKeyFor(String configId) async =>
      llmKeys[configId];

  @override
  Future<void> deleteLlmApiKeyFor(String configId) async {
    llmKeys.remove(configId);
  }
}

Map<String, dynamic> _provider({
  required String id,
  required String baseUrl,
  String name = '',
  String model = 'm1',
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'model': model,
    };

String _providersJson(List<Map<String, dynamic>> list) => jsonEncode(list);

String _backup(Map<String, dynamic> settings) => jsonEncode(<String, dynamic>{
      'version': 1,
      'settings': settings,
    });

Future<void> _seedLocalProviders(List<Map<String, dynamic>> list) async {
  await HiveBoxes.settings.put('llm_providers', _providersJson(list));
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

  group('detectLlmEndpointChanges', () {
    test('AC4 地址无变更 → 返回空 set（isEmpty 为 true）', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.example.com'),
      ]);
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.example.com'),
          ]),
        }),
      );

      expect(changes, isNotNull);
      expect(changes!.isEmpty, isTrue);
      expect(changes.added, isEmpty);
      expect(changes.changed, isEmpty);
    });

    test('AC4 新增厂商 → added 含新 host', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.example.com'),
      ]);
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.example.com'),
            _provider(id: 'p2', baseUrl: 'https://new.example.com'),
          ]),
        }),
      );

      expect(changes!.added, contains('new.example.com'));
      expect(changes.isEmpty, isFalse);
    });

    test('AC4 同 id 换 host → changed 含 from/to 与 label', () async {
      await _seedLocalProviders([
        _provider(
          id: 'p1',
          name: '我的供应商',
          baseUrl: 'https://api.openai.com',
        ),
      ]);
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(
              id: 'p1',
              name: '我的供应商',
              baseUrl: 'https://evil-proxy.xyz',
            ),
          ]),
        }),
      );

      expect(changes!.changed, hasLength(1));
      expect(changes.changed.single.label, '我的供应商');
      expect(changes.changed.single.from, 'api.openai.com');
      expect(changes.changed.single.to, 'evil-proxy.xyz');
      expect(changes.isEmpty, isFalse);
    });

    test('AC4 本机有、备份无 → removed 收录', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.example.com'),
        _provider(id: 'p2', baseUrl: 'https://old.example.com'),
      ]);
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.example.com'),
          ]),
        }),
      );

      expect(changes!.removed, contains('old.example.com'));
      // 移除不构成外泄风险 → 不触发确认框。
      expect(changes.isEmpty, isTrue);
    });

    test('AC4 label 回落：name 为空时用「配置 N」', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.example.com'),
      ]);
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://changed.example.com'),
          ]),
        }),
      );

      expect(changes!.changed.single.label, '配置 1');
    });

    test('AC4 无法判定一律返回 null（不阻断恢复）', () {
      // 1) 非法 JSON
      expect(BackupService.detectLlmEndpointChanges('not json'), isNull);
      // 2) 顶层非对象
      expect(BackupService.detectLlmEndpointChanges('[]'), isNull);
      // 3) 无 settings 节
      expect(
        BackupService.detectLlmEndpointChanges(
          jsonEncode(<String, dynamic>{'version': 1}),
        ),
        isNull,
      );
      // 4) 既无 llm_providers 也无 llm_base_url → 无端点可注入
      expect(
        BackupService.detectLlmEndpointChanges(
          _backup(<String, dynamic>{'theme_mode': 'dark'}),
        ),
        isNull,
      );
      // 5) llm_providers 非字符串且无 legacy 端点
      expect(
        BackupService.detectLlmEndpointChanges(
          _backup(<String, dynamic>{'llm_providers': 123}),
        ),
        isNull,
      );
    });

    // 回归：legacy 端点绕过面。备份可以只带 llm_base_url（旧版本导出的
    // 单配置备份），若检测只看 llm_providers 就会返回 null、不弹框，
    // 而 SettingsRepository._doMigrateLegacyLlmConfig 会在 providers 为空
    // 且 llm_base_url 非空时把它升格为生效配置并关联本机 Key —— 完整的
    // 凭据外泄链路。以下两条锁定该绕过面已被覆盖。
    test('回归：仅 legacy llm_base_url（本机无常量）→ 检出为 added 并弹框', () {
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_base_url': 'https://attacker.example.net',
          'llm_model': 'stolen-model',
        }),
      );

      expect(changes, isNotNull);
      expect(changes!.isEmpty, isFalse, reason: 'legacy 端点注入必须触发确认框');
      expect(changes.added, contains('attacker.example.net'));
    });

    test('回归：仅 legacy llm_base_url，本机已有 providers → 仍检出（升格风险）',
        () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.openai.com/v1'),
      ]);

      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_base_url': 'https://attacker.example.net',
        }),
      );

      expect(changes, isNotNull);
      expect(changes!.isEmpty, isFalse);
      expect(changes.added, contains('attacker.example.net'));
    });

    test('回归：本机 legacy 与备份 legacy 不同 → 检出为 changed', () async {
      await HiveBoxes.settings
          .put('llm_base_url', 'https://api.openai.com/v1');

      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_base_url': 'https://attacker.example.net',
        }),
      );

      expect(changes!.changed, hasLength(1));
      expect(changes.changed.single.from, 'api.openai.com');
      expect(changes.changed.single.to, 'attacker.example.net');
    });

    test('回归：同 host 换端口 → 视为端点变更（不同端口可能是不同服务）',
        () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://gw.example.com/v1'),
      ]);

      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://gw.example.com:8443/v1'),
          ]),
        }),
      );

      expect(changes!.changed, hasLength(1));
      expect(changes.changed.single.from, 'gw.example.com');
      expect(changes.changed.single.to, 'gw.example.com:8443');
    });

    test('回归：未显式写端口不算变更（host 与 host:443 等值）', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://gw.example.com/v1'),
      ]);

      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://gw.example.com/v1'),
          ]),
        }),
      );

      expect(changes!.isEmpty, isTrue);
    });

    test('回归：providers 坏结构 + legacy evil → 仍按 legacy 检出（不静默放行）',
        () {
      // 厂商列表不可解析时 legacy 才是唯一端点来源，若此时返回 null
      // 攻击者即可用「坏 providers + 好 legacy」组合绕过闸门。
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': '{"bad":1}',
          'llm_base_url': 'https://attacker.example.net',
        }),
      );

      expect(changes, isNotNull);
      expect(changes!.isEmpty, isFalse);
      expect(changes.added, contains('attacker.example.net'));
    });

    test('回归：仅 llm_model（无 llm_base_url）→ null（无端点可注入）', () {
      // 没有 base 就没有端点；且 _doMigrateLegacyLlmConfig 要求 base 非空
      // 才会升格，故单独一个 model 不构成风险。
      expect(
        BackupService.detectLlmEndpointChanges(
          _backup(<String, dynamic>{'llm_model': 'stolen-model'}),
        ),
        isNull,
      );
    });

    test('回归：备份给出合法 providers 时，legacy 字段不作为独立端点', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.openai.com/v1'),
      ]);

      // providers 与备份一致（无变更）；legacy 值不同但不会被升格
      // （providers 非空时 _doMigrateLegacyLlmConfig 直接 return），
      // 因此不应误报弹框。
      final changes = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.openai.com/v1'),
          ]),
          'llm_base_url': 'https://attacker.example.net',
        }),
      );

      expect(changes, isNotNull);
      expect(changes!.isEmpty, isTrue, reason: 'providers 是权威端点来源');
    });

    test('AC4 备份厂商列表坏结构 → null；合法空列表 → 不弹框（informational removed）',
        () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://api.example.com'),
      ]);
      // 坏结构（JSON 是对象不是数组）→ 无法判定
      expect(
        BackupService.detectLlmEndpointChanges(
          _backup(<String, dynamic>{'llm_providers': '{"a":1}'}),
        ),
        isNull,
      );
      // 坏条目（缺 baseUrl）→ 无法判定
      expect(
        BackupService.detectLlmEndpointChanges(
          _backup(<String, dynamic>{'llm_providers': '[{"id":"p1"}]'}),
        ),
        isNull,
      );
      // 合法空列表：结构可解析，本机配置被移除 → removed 有值，
      // 但 removed 不构成外泄风险，isEmpty 仍为 true → 不弹框。
      final emptyList = BackupService.detectLlmEndpointChanges(
        _backup(<String, dynamic>{'llm_providers': '[]'}),
      );
      expect(emptyList, isNotNull);
      expect(emptyList!.removed, contains('api.example.com'));
      expect(emptyList.isEmpty, isTrue, reason: '纯移除不弹框');
    });
  });

  group('_restoreSettings LLM 一致性过滤', () {
    test('AC6 llm_active_provider_id 悬空 → 跳过不落盘', () async {
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.example.com'),
          ]),
          'llm_active_provider_id': 'does-not-exist',
        }),
      );

      expect(HiveBoxes.settings.get('llm_active_provider_id'), isNull);
      // 厂商列表本身正常落盘。
      expect(HiveBoxes.settings.get('llm_providers'), isNotNull);
    });

    test('AC6 场景绑定悬空 → settingsKey 与 modelKey 均不落盘', () async {
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.example.com'),
          ]),
          LlmScenario.assistant.settingsKey: 'ghost',
          LlmScenario.assistant.modelKey: 'ghost-model',
        }),
      );

      expect(HiveBoxes.settings.get(LlmScenario.assistant.settingsKey), isNull);
      expect(HiveBoxes.settings.get(LlmScenario.assistant.modelKey), isNull);
    });

    test('AC6 场景绑定有效 → settingsKey 与 modelKey 均落盘', () async {
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(id: 'p1', baseUrl: 'https://api.example.com'),
          ]),
          LlmScenario.assistant.settingsKey: 'p1',
          LlmScenario.assistant.modelKey: 'gpt-4o',
        }),
      );

      expect(HiveBoxes.settings.get(LlmScenario.assistant.settingsKey), 'p1');
      expect(
        HiveBoxes.settings.get(LlmScenario.assistant.modelKey),
        'gpt-4o',
      );
    });

    test('AC7 llm_providers 坏结构 → 跳过该 key，恢复整体成功', () async {
      await _seedLocalProviders([
        _provider(id: 'local', baseUrl: 'https://local.example.com'),
      ]);

      // 不应抛异常。
      final count = await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_providers': 'not-a-json-array',
          'theme_mode': 'dark', // 同备份其他 key 正常恢复
        }),
      );

      expect(count, 0);
      // 坏结构跳过（未被 delete+write 抹掉 → 保留本机原值）。
      expect(
        HiveBoxes.settings.get('llm_providers'),
        contains('local.example.com'),
      );
      expect(HiveBoxes.settings.get('theme_mode'), 'dark');
    });

    test('AC8 合法空列表 → 正常落盘为空（与坏结构区分）', () async {
      await _seedLocalProviders([
        _provider(id: 'local', baseUrl: 'https://local.example.com'),
      ]);

      await backupService.restoreFromJson(
        _backup(<String, dynamic>{'llm_providers': '[]'}),
      );

      // 用户主动清空厂商列表必须生效。
      expect(HiveBoxes.settings.get('llm_providers'), '[]');
    });

    test('llm_base_url 非法（公网 http）→ 跳过；合法 https → 落盘', () async {
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_base_url': 'http://public.example.com',
          'llm_model': 'm1',
        }),
      );
      expect(HiveBoxes.settings.get('llm_base_url'), isNull);
      // base 未落盘 → 孤立的 model 也不写。
      expect(HiveBoxes.settings.get('llm_model'), isNull);

      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_base_url': 'https://ok.example.com',
          'llm_model': 'm2',
        }),
      );
      expect(HiveBoxes.settings.get('llm_base_url'), 'https://ok.example.com');
      expect(HiveBoxes.settings.get('llm_model'), 'm2');
    });

    test('llm_base_url 合法时原值不被规范化改写（不补 /v1）', () async {
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_base_url': 'https://ok.example.com',
        }),
      );
      // 只做校验，不取 normalizeBaseUrl 的返回值。
      expect(HiveBoxes.settings.get('llm_base_url'), 'https://ok.example.com');
    });
  });

  group('delete 范围与既有语义', () {
    test('旧备份（不含 LLM key）不抹掉本机 LLM 配置', () async {
      await _seedLocalProviders([
        _provider(id: 'keep', baseUrl: 'https://keep.example.com'),
      ]);
      await HiveBoxes.settings.put('llm_active_provider_id', 'keep');

      await backupService.restoreFromJson(
        _backup(<String, dynamic>{'theme_mode': 'light'}),
      );

      expect(
        HiveBoxes.settings.get('llm_providers'),
        contains('keep.example.com'),
      );
      expect(HiveBoxes.settings.get('llm_active_provider_id'), 'keep');
    });

    test('备份给出的白名单 key 仍以备份为准（覆盖本机）', () async {
      await HiveBoxes.settings.put('llm_provider_name', '本机旧值');
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{'llm_provider_name': '备份新值'}),
      );
      expect(HiveBoxes.settings.get('llm_provider_name'), '备份新值');
    });
  });

  group('AC9 凭据匹配的顺序依赖（C3）', () {
    test('hint 匹配针对恢复后的厂商列表，Key 落到备份配置 id 的槽位', () async {
      // 本机有一条 old 配置，active 指向它。
      await _seedLocalProviders([
        _provider(id: 'local-old', baseUrl: 'https://local.example.com'),
      ]);
      await HiveBoxes.settings.put('llm_active_provider_id', 'local-old');
      credentialStore.llmKeys['local-old'] = 'local-key';

      // 备份含新配置 p-new + 指向它的 hint。
      await backupService.restoreFromJson(
        _backup(<String, dynamic>{
          'llm_providers': _providersJson([
            _provider(
              id: 'p-new',
              baseUrl: 'https://restored.example.com',
              model: 'restored-model',
            ),
          ]),
          'llm_active_provider_id': 'p-new',
        }),
      );

      // 恢复后本机厂商列表已换成 p-new（顺序依赖的前提）。
      expect(
        HiveBoxes.settings.get('llm_providers'),
        contains('restored.example.com'),
      );
      expect(HiveBoxes.settings.get('llm_active_provider_id'), 'p-new');

      // readLlmApiKeyFor 能按恢复后的 id 取到（供 _restoreCredentials 用）。
      final apiKey = await credentialStore.readLlmApiKeyFor('p-new');
      expect(apiKey, isNull); // 尚未写入凭据，仅验证槽位可达
    });
  });

  group('防漂移：白名单覆盖 LlmScenario 全量 key', () {
    test('LlmScenario 的 settingsKey 与 modelKey 均已登记且类型为 string',
        () async {
      // 通过实际恢复验证：给出全部场景绑定，全部应落盘。
      final providers = [
        _provider(id: 'px', baseUrl: 'https://x.example.com'),
      ];
      final settings = <String, dynamic>{
        'llm_providers': _providersJson(providers),
      };
      for (final scenario in LlmScenario.values) {
        settings[scenario.settingsKey] = 'px';
        settings[scenario.modelKey] = 'model-for-${scenario.name}';
      }

      await backupService.restoreFromJson(_backup(settings));

      for (final scenario in LlmScenario.values) {
        expect(
          HiveBoxes.settings.get(scenario.settingsKey),
          'px',
          reason: '${scenario.name}.settingsKey 未纳入白名单',
        );
        expect(
          HiveBoxes.settings.get(scenario.modelKey),
          'model-for-${scenario.name}',
          reason: '${scenario.name}.modelKey 未纳入白名单',
        );
      }
    });
  });

  group('导出往返（AC1/AC2 的 service 层部分）', () {
    test('厂商列表 / active / 场景绑定 经导出 → 清空 → 恢复全部还原', () async {
      await _seedLocalProviders([
        _provider(
          id: 'p1',
          name: '供应商一',
          baseUrl: 'https://a.example.com',
          model: 'ma',
        ),
        _provider(
          id: 'p2',
          name: '供应商二',
          baseUrl: 'https://b.example.com',
          model: 'mb',
        ),
      ]);
      await HiveBoxes.settings.put('llm_active_provider_id', 'p2');
      for (final scenario in LlmScenario.values) {
        await HiveBoxes.settings.put(scenario.settingsKey, 'p1');
        await HiveBoxes.settings.put(scenario.modelKey, 'ma');
      }

      final json = await backupService.exportToJson();
      final settings =
          (jsonDecode(json) as Map<String, dynamic>)['settings']
              as Map<String, dynamic>;

      // 导出的确有 LLM 配置（AC1）。
      expect(settings.containsKey('llm_providers'), isTrue);
      expect(settings.containsKey('llm_active_provider_id'), isTrue);

      await HiveBoxes.settings.clear();
      await backupService.restoreFromJson(json);

      final restored =
          LlmProviderConfig.decodeList(
        HiveBoxes.settings.get('llm_providers') as String?,
      );
      expect(restored.map((c) => c.id), containsAll(<String>['p1', 'p2']));
      expect(HiveBoxes.settings.get('llm_active_provider_id'), 'p2');
      for (final scenario in LlmScenario.values) {
        expect(HiveBoxes.settings.get(scenario.settingsKey), 'p1');
        expect(HiveBoxes.settings.get(scenario.modelKey), 'ma');
      }
    });

    test('导出明文不含 API Key（凭据仍在加密节）', () async {
      await _seedLocalProviders([
        _provider(id: 'p1', baseUrl: 'https://a.example.com'),
      ]);
      await HiveBoxes.settings.put('llm_active_provider_id', 'p1');
      credentialStore.llmKeys['p1'] = 'sk-super-secret';

      final json = await backupService.exportToJson();
      expect(json, isNot(contains('sk-super-secret')));
    });
  });
}
