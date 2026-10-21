// test/core/services/backup_service_settings_guard_test.dart
//
// BackupService settings 白名单防护测试：
// 排除 key（webdav_configs / tts_cloud_* / 凭据指纹类）不落盘、类型不符跳过、
// 导出不含排除 key、正常旧备份兼容。
//
// 注：LLM 端点类 key（llm_providers / llm_active_provider_id / llm_base_url /
// llm_model / 场景绑定）**已纳入**白名单（换机可用性），改由「恢复前地址变更
// 确认框」承担 P1 补偿控制。其行为测试见
// backup_service_llm_endpoint_test.dart，本文件只锁定仍被排除的 key。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/diagnostics/diagnostic_buffer.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

import '../../helpers/hive_test_helper.dart';

/// 恶意备份中的注入 settings 节：外部服务端点 + 凭据绑定状态 key。
///
/// 本机预置同名 key 时，恢复后必须原样保留（这些仍是排除项）。
Map<String, dynamic> _maliciousSettings() => <String, dynamic>{
      'theme_mode': 'dark',
      // 仍被排除：不应落盘。
      'webdav_configs': jsonEncode([
        <String, dynamic>{
          'id': 'evil-1',
          'name': '攻击者云盘',
          'url': 'https://attacker.example.com',
          'username': 'user',
          'password': 'injected-password',
          'remotePath': '/steal',
        },
      ]),
      'tts_cloud_base_url': 'http://attacker-tts.example.com',
      'tts_cloud_enabled': true,
      'tencent_asr_verified_at': DateTime(2030, 1, 1).toIso8601String(),
      'worker_tts_verified_fingerprint': 'evil-fingerprint',
    };

/// 备份中的 LLM 端点 key（现纳入白名单）。
///
/// 恢复后会覆盖本机值 —— 这正是「恢复前确认框」要拦截的场景，
/// 服务层本身照写（确认发生在 UI 层调用 recover 之前）。
Map<String, dynamic> _llmEndpointSettings() => <String, dynamic>{
      'llm_base_url': 'https://attacker-llm.example.com',
      'llm_model': 'evil-model',
      'llm_providers': jsonEncode([
        <String, dynamic>{
          'id': 'evil-p1',
          'name': '攻击者LLM',
          'baseUrl': 'https://attacker-llm.example.com',
          'model': 'evil-model',
        },
      ]),
      'llm_active_provider_id': 'evil-p1',
      'llm_provider_word_problem': 'evil-p1',
      'llm_provider_poem_explain': 'evil-p1',
      'llm_provider_math_explain': 'evil-p1',
    };

/// 全量白名单 key 的合法 settings 节（正常旧备份）。
Map<String, dynamic> _fullWhitelistSettings() => <String, dynamic>{
      'theme_mode': 'light',
      'active_subject': 'math',
      'sound_enabled': false,
      'completion_sound': 'pizzicato',
      'haptic_enabled': true,
      'selected_grade': 3,
      'tts_speed': 0.8,
      'tts_voice': '{"name":"Xiaoxiao","locale":"zh-CN"}',
      'daily_poem_goal': 5,
      'daily_math_goal': 30,
      'math_batch_size': 20,
      'math_difficulty': 'hard',
      'math_practice_mode': 'findResult',
      'llm_provider_name': 'DeepSeek', // LLM 供应商名称（纯展示，非敏感）
      'has_onboarded': true,
      // 通知设置（notification_service 直读写，随备份迁移）。
      'reminder_enabled': true,
      'reminder_hour': 7,
      'reminder_minute': 30,
      'weekly_report_enabled': true,
      // AI 讲解提示词覆盖（随备份迁移的个性化内容）。
      'llm_poem_explain_prompt': '自定义诗词讲解提示词',
      'llm_math_explain_prompt': '自定义口算解析提示词',
      // AI 助手开关与悬浮球位置（坐标消费端会按当前屏幕夹取）。
      'assistant_enabled': true,
      'assistant_bubble_dx': 240.0,
      'assistant_bubble_dy': 520.0,
      // 家长保护开关（经确认：随备份迁移，不加恢复前确认框）。
      'parent_protection_enabled': true,
      'parent_protection_reset_notice': false,
      // 云每日额度上限（家长设定；与 meta 里的 cloud_usage 计数分开搬运）。
      'cloud_daily_limit_llm': 25,
      'cloud_daily_limit_asr': 40,
      'cloud_daily_limit_tts': 80,
      // 备份策略偏好。
      'daily_snapshot_enabled': true,
      'external_backup_reminder': false,
    };

void main() {
  late BackupService backupService;

  setUp(() async {
    await setUpHiveForTesting();
    backupService = BackupService();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  Future<String> backupWithSettings(Map<String, dynamic> settings) async {
    return jsonEncode(<String, dynamic>{
      'version': 1,
      'settings': settings,
    });
  }

  test('AC1 注入测试：排除 key 不落盘且本机原值保留', () async {
    // 本机已有真实值，恢复后必须原样保留（这些仍是排除项）。
    await HiveBoxes.settings.put(
      'webdav_configs',
      jsonEncode([
        <String, dynamic>{
          'id': 'local-1',
          'name': '家庭云盘',
          'url': 'https://dav.example.com',
          'username': '',
          'password': '',
          'remotePath': '/poemath',
        },
      ]),
    );
    await HiveBoxes.settings.put(
      'tts_cloud_base_url',
      'https://tts.cloudm.cc',
    );
    await HiveBoxes.settings.put('tencent_asr_verified_at', '2026-01-01');

    final before = {
      'webdav_configs': HiveBoxes.settings.get('webdav_configs'),
      'tts_cloud_base_url': HiveBoxes.settings.get('tts_cloud_base_url'),
      'tencent_asr_verified_at':
          HiveBoxes.settings.get('tencent_asr_verified_at'),
    };

    await backupService.restoreFromJson(
      await backupWithSettings(_maliciousSettings()),
    );

    // 本机原值保留，恶意注入未生效。
    expect(HiveBoxes.settings.get('webdav_configs'), before['webdav_configs']);
    expect(
      jsonEncode(HiveBoxes.settings.get('webdav_configs') ?? ''),
      isNot(contains('attacker.example.com')),
    );
    expect(
      jsonEncode(HiveBoxes.settings.get('webdav_configs') ?? ''),
      isNot(contains('injected-password')),
    );
    expect(
      HiveBoxes.settings.get('tts_cloud_base_url'),
      before['tts_cloud_base_url'],
    );
    expect(
      HiveBoxes.settings.get('tencent_asr_verified_at'),
      before['tencent_asr_verified_at'],
    );
    expect(
      HiveBoxes.settings.get('tts_cloud_enabled'),
      isNull,
    );
    // 白名单内 key 正常恢复。
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
  });

  test('LLM 端点 key：现纳入白名单，服务层照写（UI 层确认框负责拦截）', () async {
    // 本机先有一条本地配置。
    await HiveBoxes.settings.put(
      'llm_providers',
      jsonEncode([
        <String, dynamic>{
          'id': 'local-p1',
          'name': '本地LLM',
          'baseUrl': 'https://llm.local.example.com',
          'model': 'local-model',
        },
      ]),
    );
    await HiveBoxes.settings.put('llm_active_provider_id', 'local-p1');

    final maliciousJson = await backupWithSettings(_llmEndpointSettings());

    // 预检须在恢复**之前**调用（与 UI 层调用顺序一致）：此时本机仍是
    // 本地配置，备份的端点构成变更，确认框会弹出。
    final changes = BackupService.detectLlmEndpointChanges(maliciousJson);
    expect(changes, isNotNull);
    expect(changes!.isEmpty, isFalse, reason: '恢复前应检出端点变更');
    // 本机 id=local-p1、备份 id=evil-p1 —— id 不同，归入 added。
    expect(changes.added, contains('attacker-llm.example.com'));

    await backupService.restoreFromJson(maliciousJson);

    // 备份值覆盖本机 —— 这是刻意的行为变更：P1 防护由恢复前确认框承担，
    // 服务层不再静默拒绝（否则换机恢复 LLM 配置将不可用）。
    expect(
      HiveBoxes.settings.get('llm_providers'),
      contains('attacker-llm.example.com'),
    );
    expect(HiveBoxes.settings.get('llm_active_provider_id'), 'evil-p1');
    expect(
      HiveBoxes.settings.get('llm_provider_word_problem'),
      'evil-p1',
    );
    // legacy 字段仅在校验通过时落盘（合法 https）。
    expect(
      HiveBoxes.settings.get('llm_base_url'),
      'https://attacker-llm.example.com',
    );
    expect(HiveBoxes.settings.get('llm_model'), 'evil-model');
  });

  test('AC2 类型测试：类型不符的 key 跳过，int 语速规范化为 double', () async {
    final count = await backupService.restoreFromJson(
      await backupWithSettings(<String, dynamic>{
        'haptic_enabled': 'boom', // String 冒充 bool → 跳过
        'selected_grade': 1.5, // JSON double 冒充 int → 跳过
        'tts_speed': 1, // JSON int 合法化为 1.0
        'sound_enabled': false, // 正常 bool，应恢复
      }),
    );

    // 恢复本身成功（不毁整个恢复；settings 节不计入记录数）。
    expect(count, 0);
    // 类型不符的 key 被跳过：不写入坏值。
    expect(HiveBoxes.settings.get('haptic_enabled'), isNull);
    expect(HiveBoxes.settings.get('selected_grade'), isNull);
    // tts_speed int 1 规范化为 double 1.0。
    expect(
      HiveBoxes.settings.get('tts_speed'),
      isA<double>().having(
        (v) => v,
        'value',
        1.0,
      ),
    );
    expect(HiveBoxes.settings.get('sound_enabled'), isFalse);
  });

  test('AC2 补充：本机无原值时，类型不符 key 恢复后不落盘', () async {
    await backupService.restoreFromJson(
      await backupWithSettings(<String, dynamic>{
        'sound_enabled': 'boom',
        'selected_grade': 1.5,
        'haptic_enabled': 'not-a-bool',
      }),
    );

    expect(HiveBoxes.settings.get('sound_enabled'), isNull);
    expect(HiveBoxes.settings.get('selected_grade'), isNull);
    expect(HiveBoxes.settings.get('haptic_enabled'), isNull);
  });

  test('AC3 导出测试：导出 JSON 的 settings 节不含任何排除 key', () async {
    await HiveBoxes.settings.put(
      'webdav_configs',
      jsonEncode([
        <String, dynamic>{
          'id': 'local-1',
          'name': '家庭云盘',
          'url': 'https://dav.example.com',
          'username': '',
          'password': '',
          'remotePath': '/poemath',
        },
      ]),
    );
    await HiveBoxes.settings
        .put('llm_base_url', 'https://llm.local.example.com');
    await HiveBoxes.settings.put('llm_model', 'gpt-test');
    await HiveBoxes.settings.put('tts_cloud_base_url', 'https://tts.cloudm.cc');
    await HiveBoxes.settings.put('tts_cloud_enabled', true);
    await HiveBoxes.settings.put('tts_cloud_voice', 'zh-CN-XiaoxiaoNeural');
    await HiveBoxes.settings.put('tts_cloud_style', 'poetry-reading');
    await HiveBoxes.settings
        .put('tencent_asr_credential_fingerprint', 'fp-local');
    await HiveBoxes.settings.put('tencent_asr_verified_at', '2026-01-01');
    await HiveBoxes.settings
        .put('worker_tts_verified_fingerprint', 'fp-worker');
    await HiveBoxes.settings.put('theme_mode', 'light');
    await HiveBoxes.settings.put(
      'llm_providers',
      jsonEncode([
        <String, dynamic>{
          'id': 'p1',
          'name': '本地LLM',
          'baseUrl': 'https://llm.local.example.com',
          'model': 'gpt-test',
        },
      ]),
    );
    await HiveBoxes.settings.put('llm_active_provider_id', 'p1');
    await HiveBoxes.settings.put('llm_provider_word_problem', 'p1');
    await HiveBoxes.settings.put('llm_provider_poem_explain', 'p1');
    await HiveBoxes.settings.put('llm_provider_math_explain', 'p1');

    final json = await backupService.exportToJson();
    final settings = (jsonDecode(json) as Map<String, dynamic>)['settings']
        as Map<String, dynamic>;

    expect(settings.keys, contains('theme_mode'));
    const excluded = <String>{
      'webdav_configs',
      'tts_cloud_base_url',
      'tts_cloud_enabled',
      'tts_cloud_voice',
      'tts_cloud_style',
      'tencent_asr_credential_fingerprint',
      'tencent_asr_verified_at',
      'worker_tts_verified_fingerprint',
    };
    for (final key in excluded) {
      expect(settings.containsKey(key), isFalse, reason: '排除 key 不应导出: $key');
    }

    // LLM 端点 key 现**应**导出（换机可用性），P1 由恢复前确认框承担。
    const included = <String>{
      'llm_providers',
      'llm_active_provider_id',
      'llm_base_url',
      'llm_model',
      'llm_provider_word_problem',
      'llm_provider_poem_explain',
      'llm_provider_math_explain',
    };
    for (final key in included) {
      expect(settings.containsKey(key), isTrue, reason: 'LLM key 应导出: $key');
    }
  });

  test('AC3 补充：导出 JSON 明文任何位置不含 llm_api_key_hint', () async {
    // 预置带 Key 的 LLM 配置（导出端写 hint 的前提条件）。
    await HiveBoxes.settings.put(
      'llm_providers',
      jsonEncode([
        <String, dynamic>{
          'id': 'p1',
          'name': '本地LLM',
          'baseUrl': 'https://llm.local.example.com',
          'model': 'gpt-test',
        },
      ]),
    );
    await HiveBoxes.settings.put('llm_active_provider_id', 'p1');

    // 该测试的 BackupService 用真实 SecureCredentialStore（测试环境无
    // 平台通道），读取必定抛异常 —— 这正是「安全存储不可用」的真实形态。
    // 契约变更后导出不再静默降级，而是抛 BackupCredentialExportException；
    // 这里走用户的降级路径（无口令重导），继续断言明文 JSON 层：
    // llm_api_key_hint 作为凭据白名单键只允许出现在加密载荷内，
    // 明文 JSON 文本不得含该键名（settings 白名单外的 key 不导出，
    // 顶层亦无此键）。
    await expectLater(
      backupService.exportToJson(passphrase: 'pw'),
      throwsA(isA<BackupCredentialExportException>()),
    );
    final json = await backupService.exportToJson();
    final node = jsonDecode(json) as Map<String, dynamic>;

    // 顶层无此键。
    expect(node.containsKey('llm_api_key_hint'), isFalse);
    // settings 白名单外 key 不导出。
    final settings = node['settings'] as Map<String, dynamic>?;
    expect(settings?.containsKey('llm_api_key_hint') ?? false, isFalse);
    // 明文序列化文本（缩进美化后字段名均可见）不含该键名。
    expect(json, isNot(contains('llm_api_key_hint')));
    // 降级导出确实不含凭据节。
    expect(node.containsKey('credentials'), isFalse);
  });

  test('last_synced_at 属设备绑定 key：不导出、也不被备份恢复覆盖', () async {
    // 它是「本机与云端的相对时间线」，随备份迁到另一台设备会继承一台机器
    // 的时点、制造冲突误报，因此刻意排除在白名单外。
    await HiveBoxes.settings.put('last_synced_at', '2026-10-13T09:30:00.000');
    await HiveBoxes.settings.put('theme_mode', 'light');

    final json = await backupService.exportToJson();
    final settings = (jsonDecode(json) as Map<String, dynamic>)['settings']
        as Map<String, dynamic>;
    expect(
      settings.containsKey('last_synced_at'),
      isFalse,
      reason: '设备绑定 key 不应随备份导出',
    );

    // 反向：备份里塞入该 key 也不得覆盖本机值。
    final before = HiveBoxes.settings.get('last_synced_at');
    await backupService.restoreFromJson(
      await backupWithSettings(<String, dynamic>{
        'last_synced_at': '2030-01-01T00:00:00.000',
        'theme_mode': 'dark',
      }),
    );
    expect(HiveBoxes.settings.get('last_synced_at'), before);
    // 同备份内的白名单 key 正常恢复，证明不是整体跳过。
    expect(HiveBoxes.settings.get('theme_mode'), 'dark');
  });

  test('AC4 兼容测试：含排除 key 的正常旧备份恢复成功，白名单 key 全部还原', () async {
    // 模拟旧版本导出的备份：白名单 key 与排除 key 混杂。
    final legacySettings = _fullWhitelistSettings()
      ..['webdav_configs'] = jsonEncode([
        <String, dynamic>{
          'id': 'old-1',
          'name': '旧云盘',
          'url': 'https://old.example.com',
          'username': '',
          'password': '',
          'remotePath': '/old',
        },
      ])
      ..['llm_base_url'] = 'https://old-llm.example.com';

    await backupService.restoreFromJson(
      await backupWithSettings(legacySettings),
    );

    // 白名单 key 全部还原。
    expect(HiveBoxes.settings.get('theme_mode'), 'light');
    expect(HiveBoxes.settings.get('active_subject'), 'math');
    expect(HiveBoxes.settings.get('sound_enabled'), isFalse);
    expect(HiveBoxes.settings.get('haptic_enabled'), isTrue);
    expect(HiveBoxes.settings.get('selected_grade'), 3);
    expect(HiveBoxes.settings.get('tts_speed'), 0.8);
    expect(
      HiveBoxes.settings.get('tts_voice'),
      '{"name":"Xiaoxiao","locale":"zh-CN"}',
    );
    expect(HiveBoxes.settings.get('daily_poem_goal'), 5);
    expect(HiveBoxes.settings.get('daily_math_goal'), 30);
    expect(HiveBoxes.settings.get('math_batch_size'), 20);
    expect(HiveBoxes.settings.get('math_difficulty'), 'hard');
    expect(HiveBoxes.settings.get('math_practice_mode'), 'findResult');
    expect(HiveBoxes.settings.get('llm_provider_name'), 'DeepSeek');
    expect(HiveBoxes.settings.get('has_onboarded'), isTrue);
    // 通知设置 4 个白名单 key 还原（AC7 round-trip）。
    expect(HiveBoxes.settings.get('reminder_enabled'), isTrue);
    expect(HiveBoxes.settings.get('reminder_hour'), 7);
    expect(HiveBoxes.settings.get('reminder_minute'), 30);
    expect(HiveBoxes.settings.get('weekly_report_enabled'), isTrue);
    // 仍被排除的 key 跳过。
    expect(HiveBoxes.settings.get('webdav_configs'), isNull);
    // LLM 端点 key 现随备份还原（legacy 字段合法 https → 落盘）。
    expect(
      HiveBoxes.settings.get('llm_base_url'),
      'https://old-llm.example.com',
    );
  });

  test('导出往返：白名单 key 经导出 → 清空 → 恢复全部还原', () async {
    for (final entry in _fullWhitelistSettings().entries) {
      await HiveBoxes.settings.put(entry.key, entry.value);
    }
    final json = await backupService.exportToJson();

    await HiveBoxes.settings.clear();
    await backupService.restoreFromJson(json);

    final settings = _fullWhitelistSettings();
    for (final entry in settings.entries) {
      if (entry.key == 'tts_speed') {
        // double 经 JSON 往返仍为 double。
        expect(
          HiveBoxes.settings.get(entry.key),
          isA<double>().having((v) => v, 'value', entry.value),
        );
      } else {
        expect(HiveBoxes.settings.get(entry.key), entry.value);
      }
    }
  });

  test('完成音效备份缺键或坏值保留本机选择，有效值覆盖', () async {
    await HiveBoxes.settings.put('completion_sound', 'steel_drum');
    for (final settings in <Map<String, dynamic>>[
      {},
      {'completion_sound': 'unknown'},
      {'completion_sound': 123},
    ]) {
      await backupService.restoreFromJson(await backupWithSettings(settings));
      expect(HiveBoxes.settings.get('completion_sound'), 'steel_drum');
    }
    await backupService.restoreFromJson(
      await backupWithSettings({'completion_sound': 'arcade'}),
    );
    expect(HiveBoxes.settings.get('completion_sound'), 'arcade');
  });

  test('AC7 类型测试：通知 key 类型不符时跳过不落盘', () async {
    final poisoned = _fullWhitelistSettings()
      // hour/minute 期望 int，double 应跳过（防 JSON 数值漂移注入）。
      ..['reminder_hour'] = 7.5
      ..['reminder_minute'] = 30.0
      // reminder_enabled 期望 bool，字符串应跳过。
      ..['reminder_enabled'] = 'yes';

    await backupService.restoreFromJson(
      await backupWithSettings(poisoned),
    );

    expect(HiveBoxes.settings.get('reminder_hour'), isNull);
    expect(HiveBoxes.settings.get('reminder_minute'), isNull);
    expect(HiveBoxes.settings.get('reminder_enabled'), isNull);
    // 同备份中类型正确的通知 key 正常还原。
    expect(HiveBoxes.settings.get('weekly_report_enabled'), isTrue);
  });

  // ── 诊断缓冲排除（10-18-security-hardening 问题 5）──────────────
  //
  // 诊断缓冲是**纯内存**结构，根本不在 Hive 里，因此「不登记进
  // `_settingsValueType`」即自动排除于备份。本组测试锁定这一点，
  // 防止后人把缓冲改成落盘/落 settings 后随备份跨设备传播。
  group('诊断缓冲不随备份迁移', () {
    test('缓冲中的哨兵文本不出现在导出 JSON 中', () async {
      const sentinel = 'sentinel-诊断哨兵-9f3c1a';
      DiagnosticBuffer.instance = DiagnosticBuffer();
      DiagnosticBuffer.instance.record(
        level: 'E',
        tag: 'Unit',
        message: '$sentinel password=hunter2',
      );

      final json = await backupService.exportToJson();

      expect(json.contains(sentinel), isFalse);
      expect(json.contains('hunter2'), isFalse);
      // 缓冲确实有内容 —— 断言不是因为缓冲为空而「碰巧」不出现。
      expect(DiagnosticBuffer.instance.length, 1);
    });

    test('恶意备份注入诊断类 settings key 时被跳过', () async {
      await HiveBoxes.settings.put('local_setting', 'keep-me');

      await backupService.restoreFromJson(
        await backupWithSettings(<String, dynamic>{
          'theme_mode': 'dark',
          'diagnostic_buffer': 'injected-from-hostile-backup',
          'diagnostics': 'injected-from-hostile-backup',
        }),
      );

      // 未登记的 key 一律跳过，本机不被写入。
      expect(HiveBoxes.settings.get('diagnostic_buffer'), isNull);
      expect(HiveBoxes.settings.get('diagnostics'), isNull);
      // 同备份里合法的白名单 key 照常恢复，证明跳过是「逐 key」而非整体失败。
      expect(HiveBoxes.settings.get('theme_mode'), 'dark');
      expect(HiveBoxes.settings.get('local_setting'), 'keep-me');
    });
  });
}
