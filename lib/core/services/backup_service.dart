// lib/core/services/backup_service.dart
//
// 层级：core/services
// 职责：数据备份与恢复服务。
//       导出所有用户动态数据为 JSON，或从 JSON 恢复。
//       静态数据（诗词、作者、公式）由 asset 加载，不参与备份。

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:poemath/data/poem_identity.dart';
import 'package:poemath/data/hive/migrations/poem_identity_migration.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/settings_constraints.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/models/assistant_message.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/formula_favorite.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/repositories/activity_settlement_ledger.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

/// 备份数据版本号，用于兼容性检查。
const int _backupVersion = 1;

/// 允许随备份迁移的 settings key 及其类型契约（key → 期望类型标签）。
///
/// 导出只写白名单内的 key；恢复只删/写白名单内的 key，白名单外一律跳过、
/// 类型不符跳过该 key（不毁整个恢复）。恢复不再 `box.clear()`：本机的
/// 排除 key（如 webdav_configs）原值保留，防止攻击者借恶意备份清空设备配置。
///
/// **LLM 端点类 key 的纳入前提（P1 补偿控制）**：
/// llm_providers（含 baseUrl/model）、llm_active_provider_id、llm_base_url /
/// llm_model、四个场景绑定（LlmScenario.settingsKey / modelKey）**已纳入**
/// —— 这些 key 指向外部服务，注入即成为凭据外泄端点（P1）。纳入原因是
/// 换机可用性：API Key 本身已随加密凭据节迁移，若地址不迁移则 Key 无处投递，
/// AI 全链路不可用。
///
/// 补偿控制：`detectLlmEndpointChanges` + 恢复前地址变更确认框
/// （features/profile/widgets/llm_endpoint_confirm_dialog.dart）。两个恢复
/// 入口（cloud_sync_page / backup_restore_page）在写入前比对并弹框，用户取消
/// 即中止恢复、数据零变更，把 P1 从「静默生效」降级为「知情同意」。
///
/// **纪律**：新增端点类 key 一律必须先有恢复前确认闸门，不得静默纳入。
///
/// 仍排除的 key 及理由：
/// - webdav_configs：其 url 与凭据是同一份数据的两半，拆不开；凭据不随备份
///   明文迁移的既有设计下无法只迁 url（与 llm_providers 不同类）；
/// - tts_cloud_base_url / tts_cloud_enabled / tts_cloud_voice / tts_cloud_style：
///   TTS 云端端点与开关，当前无对应确认闸门；
/// - tencent_asr_credential_fingerprint / tencent_asr_verified_at /
///   worker_tts_verified_fingerprint：与凭据绑定的验证状态，凭据不随备份
///   走，指纹/时间戳单独迁移会误导验证状态。
///
/// 新增 settings key 时必须同步登记本白名单（并注明类型），否则不会随备份迁移。
const Map<String, String> _settingsValueType = <String, String>{
  'theme_mode': 'string', // 外观模式 system/light/dark
  'active_subject': 'string', // 当前主题 poem/math
  'sound_enabled': 'bool', // 音效开关
  'haptic_enabled': 'bool', // 触觉反馈开关
  'selected_grade': 'int', // 选中年级
  'selected_semester': 'string', // 学习背景学期 上/下
  'tts_speed': 'double', // TTS 语速
  'tts_voice': 'string', // TTS 音色 JSON 字符串
  'pinyin_visible': 'bool', // 拼音显示开关
  'daily_poem_goal': 'int', // 每日诗词背诵目标
  'daily_math_goal': 'int', // 每日口算做题目标
  'math_batch_size': 'int', // 每组题目数量
  'math_difficulty': 'string', // 练习难度 easy/medium/hard
  'math_practice_mode': 'string', // 练习模式（综合或 ProblemMode.name）
  'llm_provider_name': 'string', // LLM 供应商名称（纯展示，非敏感）
  // LLM 厂商配置与场景绑定（含端点，受恢复前确认闸门约束，见上方说明）。
  'llm_providers': 'string', // LlmProviderConfig.encodeList 的 JSON 字符串
  'llm_active_provider_id': 'string', // 当前生效配置 id
  'llm_base_url': 'string', // 旧单配置残留（legacy 往返）
  'llm_model': 'string', // 旧单配置残留
  'llm_provider_assistant': 'string', // AI 助手绑定的配置 id
  'llm_model_assistant': 'string', // AI 助手选中的模型名
  'llm_provider_word_problem': 'string', // AI 出题绑定的配置 id
  'llm_model_word_problem': 'string', // AI 出题选中的模型名
  'llm_provider_poem_explain': 'string', // 诗词讲解绑定的配置 id
  'llm_model_poem_explain': 'string', // 诗词讲解选中的模型名
  'llm_provider_math_explain': 'string', // 口算解析绑定的配置 id
  'llm_model_math_explain': 'string', // 口算解析选中的模型名
  'has_onboarded': 'bool', // 是否完成引导
  // 通知设置（notification_service 直读写，随备份迁移，见其 key 常量区）。
  'reminder_enabled': 'bool', // 每日提醒开关
  'reminder_hour': 'int', // 每日提醒小时（24h 制）
  'reminder_minute': 'int', // 每日提醒分钟
  'weekly_report_enabled': 'bool', // 周报开关
  // AI 讲解提示词用户覆盖（纯文本、非凭据、不指向外部服务，随备份迁移
  // 换机不丢；与设备绑定的 llm_providers / 场景绑定 key 不同类）。
  'llm_poem_explain_prompt': 'string', // 诗词讲解 system prompt 覆盖
  'llm_math_explain_prompt': 'string', // 口算解析 system prompt 覆盖
  'llm_assistant_prompt': 'string', // AI 助手 system prompt 覆盖
  'assistant_enabled': 'bool', // AI 助手悬浮气泡开关（默认关闭）
};

/// 导出口令非空、但安全存储读取失败时抛出。
///
/// 旧实现把读取失败静默降级成「不含凭据的备份」：用户以为备份完整，
/// 换机恢复后才发现 Key 全丢了，且拿不到任何线索。这里改为显式抛错，
/// 由 UI 让用户决定「仍然导出（不含密钥）」还是「取消」。
class BackupCredentialExportException implements Exception {
  const BackupCredentialExportException(this.cause);

  /// 原始错误（安全存储 / 平台通道异常），仅供日志，不得展示给用户。
  final Object cause;

  @override
  String toString() => 'BackupCredentialExportException: $cause';
}

class BackupService {
  BackupService({SecureCredentialStore? secureStore})
      : _secureStore = secureStore ?? SecureCredentialStore();

  final SecureCredentialStore _secureStore;

  /// 导出所有用户数据为 JSON 字符串。
  ///
  /// [passphrase] 非空且安全存储中存在凭据时，凭据以
  /// PBKDF2 + AES-256-GCM 加密写入 `credentials` 节；否则省略该节。
  ///
  /// 口令非空但读取凭据失败时抛 [BackupCredentialExportException]，
  /// **不再**静默产出缺凭据的备份（见该类文档）。
  Future<String> exportToJson({String? passphrase}) async {
    final data = <String, dynamic>{
      'version': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'poemProgress': _exportPoemProgress(),
      'poemFavorites': _exportPoemFavorites(),
      'reviewSchedules': _exportReviewSchedules(),
      'mathMistakes': _exportMathMistakes(),
      'mathSessions': _exportMathSessions(),
      'formulaFavorites': _exportFormulaFavorites(),
      'achievements': _exportAchievements(),
      'checkIns': _exportCheckIns(),
      'userStats': _exportUserStats(),
      'challengeRecords': _exportChallengeRecords(),
      'learningActivities': _exportLearningActivities(),
      'llmProblems': _exportLlmProblems(),
      'conversations': [
        for (final c in HiveBoxes.conversations.values)
          {
            'id': c.id,
            'profileId': c.profileId,
            'title': c.title,
            'createdAt': c.createdAt.toIso8601String(),
            'updatedAt': c.updatedAt.toIso8601String(),
            'contextBaseIndex': c.contextBaseIndex,
          },
      ],
      'messages': [
        for (final m in HiveBoxes.messages.values)
          {
            'id': m.id,
            'profileId': m.profileId,
            'conversationId': m.conversationId,
            'role': m.role.name,
            'content': m.content,
            'createdAt': m.createdAt.toIso8601String(),
            'toolName': m.toolName,
            'toolCallId': m.toolCallId,
          },
      ],
      'activitySettlements': ActivitySettlementLedger.completedKeys,
      'settings': _exportSettings(),
    };
    final credentials = await _exportCredentials(passphrase);
    if (credentials != null) {
      data['credentials'] = credentials;
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 读取安全存储凭据并加密。
  ///
  /// 两种「没有凭据」是合法的，返回 `null` 让调用方省略 `credentials` 节：
  /// ① 没填口令（用户本来就没打算带走密钥）；② 各项凭据都为空。
  ///
  /// 读取**失败**不是合法状态：抛 [BackupCredentialExportException]，
  /// 由 UI 决定降级导出还是取消。
  Future<Map<String, dynamic>?> _exportCredentials(String? passphrase) async {
    final normalized = passphrase?.trim() ?? '';
    if (normalized.isEmpty) return null;
    try {
      final payload = <String, String>{};
      final tencent = await _secureStore.readTencentAsrCredentials();
      if (tencent != null) {
        payload[kCredKeyTencentSecretId] = tencent.secretId;
        payload[kCredKeyTencentSecretKey] = tencent.secretKey;
      }
      final workerApiKey = await _secureStore.readWorkerTtsApiKey();
      if (workerApiKey != null && workerApiKey.isNotEmpty) {
        payload[kCredKeyWorkerTtsApiKey] = workerApiKey;
      }
      final llmApiKey = await _readActiveLlmApiKey();
      if (llmApiKey != null && llmApiKey.isNotEmpty) {
        payload[kCredKeyLlmApiKey] = llmApiKey;
        // 归属提示（host|model，非敏感）：恢复端凭它在本机 llm_providers
        // 中找回 key 的归属配置，防止导出后本机切换 active 导致 key 写
        // 进错误槽位。只进加密凭据节，明文备份任何位置不得出现。
        payload[kCredKeyLlmApiKeyHint] = _activeLlmKeyHint();
      }
      final providerKeys = <String, String>{};
      for (final config in LlmProviderConfig.decodeList(
        HiveBoxes.settings.get('llm_providers') as String?,
      )) {
        final key = await _secureStore.readLlmApiKeyFor(config.id);
        if (key != null && key.isNotEmpty) providerKeys[config.id] = key;
      }
      if (providerKeys.isNotEmpty) {
        payload[kCredKeyLlmProviderKeys] = jsonEncode(providerKeys);
      }
      if (payload.isEmpty) return null;
      return await encryptCredentials(payload, normalized);
    } on Object catch (error, stackTrace) {
      // 不得记录 payload：只记异常本身。
      AppLogger.e(
        '导出凭据失败',
        tag: 'Backup',
        error: error,
        stackTrace: stackTrace,
      );
      throw BackupCredentialExportException(error);
    }
  }

  /// 导出并保存到临时文件，返回文件路径。
  Future<String> exportToFile({String? passphrase}) async {
    final json = await exportToJson(passphrase: passphrase);
    final dir = await getTemporaryDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/poemath_backup_$timestamp.json');
    await file.writeAsString(json);
    return file.path;
  }

  /// 探测备份 JSON 是否含 `credentials` 节（决定导入/下载前是否弹口令框）。
  static bool jsonHasCredentials(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      return decoded is Map && decoded.containsKey('credentials');
    } on FormatException {
      return false;
    }
  }

  /// 读取备份顶层 `exportedAt`（导出时刻），供跨设备冲突检测比对。
  ///
  /// 返回 null 表示**无法判定**：JSON 非法、顶层不是对象、字段缺失或不是
  /// 合法 ISO 字符串。老版本备份没有该字段，旧备份与新备份混用时也会落到
  /// null —— 调用方应把 null 当作「无时间线可比」，**不得**据此判定冲突，
  /// 否则换机首次恢复会被无谓拦截。
  static DateTime? exportedAt(String jsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final value = decoded['exportedAt'];
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  /// 比对备份与本机的 LLM 端点差异，供恢复前确认框展示（P1 补偿控制）。
  ///
  /// 返回 null 表示**无法判定或无需确认**：JSON 非法、无 `settings` 节、
  /// 备份既无 `llm_providers` 也无 `llm_base_url`、厂商列表结构损坏或为空
  /// 且无 legacy 端点。调用方应把 null 与 `isEmpty` 一样对待 —— 直接继续
  /// 恢复，不弹框（不因预检失败阻断恢复）。
  ///
  /// 只有 `added` / `changed` 触发弹框；`removed`（本机有、备份无）不构成
  /// 外泄风险，仅为信息性字段。
  ///
  /// **必须同时覆盖 legacy 端点**：备份可以只带 `llm_base_url`
  /// （旧版本导出的单配置备份），此时若不比对即返回 null，攻击者只需给出
  /// `{'settings': {'llm_base_url': 'https://attacker.example.net'}}` 就能
  /// 绕过确认闸门 —— `SettingsRepository._doMigrateLegacyLlmConfig` 会在
  /// `llm_providers` 为空且 `llm_base_url` 非空时把它**升格为生效配置**并
  /// 关联本机 Key，构成完整的凭据外泄链路。
  static LlmEndpointChangeSet? detectLlmEndpointChanges(String jsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final settings = decoded['settings'];
    if (settings is! Map) return null;

    // 本机侧：数据可信，坏数据退化为空列表即「无本地端点」，语义正确。
    final local = LlmProviderConfig.decodeList(
      HiveBoxes.settings.get('llm_providers') as String?,
    );
    final localById = <String, LlmProviderConfig>{
      for (final config in local) config.id: config,
    };

    final added = <String>[];
    final changed = <LlmEndpointChange>[];

    // ---- 来源一：备份的 llm_providers ----
    final rawProviders = settings['llm_providers'];
    List<LlmProviderConfig>? incoming;
    if (rawProviders is String && rawProviders.isNotEmpty) {
      // 备份侧：结构损坏返回 null（区分「坏结构」与「合法空列表」，见
      // _tryParseProviderList 注释）。
      incoming = _tryParseProviderList(rawProviders);
      if (incoming != null) {
        for (var index = 0; index < incoming.length; index++) {
          final config = incoming[index];
          final host = _endpointOf(config.baseUrl);
          final existing = localById[config.id];
          if (existing == null) {
            added.add(host);
            continue;
          }
          final localHost = _endpointOf(existing.baseUrl);
          if (localHost != host) {
            changed.add(
              LlmEndpointChange(
                label: config.name.trim().isEmpty
                    ? '配置 ${index + 1}'
                    : config.name.trim(),
                from: localHost,
                to: host,
              ),
            );
          }
        }
      }
    }

    // ---- 来源二：备份的 legacy llm_base_url（绕过面，见方法注释）----
    // 仅当备份未给出可解析的厂商列表时才纳入：厂商列表存在时它是权威端点
    // 来源，且 `_doMigrateLegacyLlmConfig` 不会在 providers 非空时升格
    // legacy 值，此时 legacy 字段不构成独立端点。
    final backupProvidersUsable = incoming != null && incoming.isNotEmpty;
    if (!backupProvidersUsable) {
      final legacy = settings['llm_base_url'];
      if (legacy is String && legacy.trim().isNotEmpty) {
        final localLegacy =
            (HiveBoxes.settings.get('llm_base_url') as String?) ?? '';
        final host = _endpointOf(legacy);
        // 本机 legacy 值可能是「已被升格过」= providers 非空，此时本机
        // 真正生效的是 providers，legacy 残留不作为对比基准（避免误报）。
        if (local.isEmpty) {
          if (localLegacy.trim().isEmpty) {
            added.add(host);
          } else {
            final localHost = _endpointOf(localLegacy);
            if (localHost != host) {
              changed.add(
                LlmEndpointChange(
                  label: '默认服务地址',
                  from: localHost,
                  to: host,
                ),
              );
            }
          }
        } else {
          // 本机已有厂商列表 → legacy 注入会被升格为新配置，仍属端点新增。
          added.add(host);
        }
      }
    }

    // 既无厂商列表也无 legacy 端点 → 无端点可注入，不弹框。
    if (incoming == null && added.isEmpty && changed.isEmpty) return null;

    final incomingIds = incoming?.map((c) => c.id).toSet() ?? const <String>{};
    final removed = <String>[
      for (final config in local)
        if (!incomingIds.contains(config.id)) _endpointOf(config.baseUrl),
    ];

    return LlmEndpointChangeSet(
      added: added,
      changed: changed,
      removed: removed,
    );
  }

  /// 从 JSON 字符串恢复数据。
  ///
  /// 返回恢复的记录总数。
  /// 如果版本不兼容，抛出 [FormatException]。
  /// 备份含 `credentials` 节时：口令留空跳过凭据、口令错误在写入前
  /// 抛 [FormatException]，均不影响其余数据；口令正确则在末尾把凭据
  /// 写入安全存储。
  /// 恢复失败时分别补偿 Hive 数据、设置键的存在状态及已写入凭据。
  /// 补偿失败会通过 [BackupRestoreException.rollbackFailed] 显式报告。
  Future<int> restoreFromJson(String jsonString, {String? passphrase}) async {
    final data = _decodeAndValidate(jsonString);

    // 凭据解密在快照与任何写入之前完成：口令错误时数据零变更。
    Map<String, String>? plainCredentials;
    if (data.containsKey('credentials')) {
      final normalized = passphrase?.trim() ?? '';
      if (normalized.isNotEmpty) {
        plainCredentials = await decryptCredentials(
          data['credentials'] as Map<String, dynamic>,
          normalized,
        );
        if (plainCredentials.containsKey(kCredKeyLlmProviderKeys)) {
          _decodeProviderKeys(plainCredentials[kCredKeyLlmProviderKeys]!);
        }
      }
    }

    // 恢复前先快照当前数据（不含凭据节），失败时用于回滚
    final snapshot = await exportToJson();
    final settingsSnapshot = <String, dynamic>{
      for (final key in _settingsValueType.keys)
        if (HiveBoxes.settings.containsKey(key))
          key: HiveBoxes.settings.get(key),
    };
    final credentialUndo = <Future<void> Function()>[];

    try {
      final count = await _doRestore(data);
      if (plainCredentials != null) {
        await _restoreCredentials(plainCredentials, undo: credentialUndo);
      }
      return count;
    } on Object catch (error, stackTrace) {
      // 恢复失败，回滚到快照
      final rollbackErrors = <Object>[];
      try {
        final rollback = _decodeAndValidate(snapshot);
        await _doRestore(rollback, canonicalize: false);
      } on Object catch (rollbackError) {
        rollbackErrors.add(rollbackError);
      }
      // Hive 数据恢复失败也继续补偿设置和凭据；各存储独立尽力回滚。
      try {
        for (final key in _settingsValueType.keys) {
          if (!settingsSnapshot.containsKey(key)) {
            await HiveBoxes.settings.delete(key);
          }
        }
        await HiveBoxes.settings.putAll(settingsSnapshot);
      } on Object catch (rollbackError) {
        rollbackErrors.add(rollbackError);
      }
      for (final undo in credentialUndo.reversed) {
        try {
          await undo();
        } on Object catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
      }
      if (rollbackErrors.isNotEmpty) {
        throw BackupRestoreException(
          '恢复失败，且回滚失败，请检查数据完整性',
          cause: error,
          rollbackError: rollbackErrors,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 把解密后的凭据写入安全存储（覆盖式）。
  Future<void> _restoreCredentials(
    Map<String, String> credentials, {
    required List<Future<void> Function()> undo,
  }) async {
    final secretId = credentials[kCredKeyTencentSecretId];
    final secretKey = credentials[kCredKeyTencentSecretKey];
    if (secretId != null && secretKey != null) {
      final old = await _secureStore.readTencentAsrCredentials();
      undo.add(
        () => old == null
            ? _secureStore.deleteTencentAsrCredentials()
            : _secureStore.saveTencentAsrCredentials(old),
      );
      await _secureStore.saveTencentAsrCredentials(
        TencentAsrCredentials(secretId: secretId, secretKey: secretKey),
      );
    }
    final apiKey = credentials[kCredKeyWorkerTtsApiKey];
    if (apiKey != null && apiKey.isNotEmpty) {
      final old = await _secureStore.readWorkerTtsApiKey();
      undo.add(
        () => old == null
            ? _secureStore.deleteWorkerTtsApiKey()
            : _secureStore.saveWorkerTtsApiKey(old),
      );
      await _secureStore.saveWorkerTtsApiKey(apiKey);
    }
    final providerPayload = credentials[kCredKeyLlmProviderKeys];
    if (providerPayload != null) {
      final keys = _decodeProviderKeys(providerPayload);
      final ids = LlmProviderConfig.decodeList(
        HiveBoxes.settings.get('llm_providers') as String?,
      ).map((c) => c.id).toSet();
      for (final entry in keys.entries) {
        if (ids.contains(entry.key)) {
          await _writeLlmKey(entry.key, entry.value, undo);
        }
      }
      return;
    }
    // legacy 备份无 llm_api_key 字段 → null，跳过（不覆盖现有值）。
    // LLM 配置设备绑定（url/model 不随备份迁移），key 必须找到本机的
    // 归属配置才能落到正确槽位（llm_api_key_{configId}）：
    // - 有 llm_api_key_hint（新备份）：按 host|model 在本机 llm_providers
    //   中匹配，key 写回**匹配配置**的槽位——防止导出后本机切换 active
    //   造成「A 的 key 写进 B 槽位」；本机无匹配配置则丢弃（与
    //   url/model 不迁移纪律一致）。
    // - 无 hint（旧备份）：维持现行为——写本机当前生效配置的键位；
    //   本机无生效配置则丢弃（兼容不倒退）。
    final llmApiKey = credentials[kCredKeyLlmApiKey];
    if (llmApiKey != null && llmApiKey.isNotEmpty) {
      final hint = credentials[kCredKeyLlmApiKeyHint];
      if (hint != null && hint.isNotEmpty) {
        final matchedId = _matchLlmProviderByHint(hint);
        if (matchedId != null) {
          await _writeLlmKey(matchedId, llmApiKey, undo);
        }
      } else {
        final activeId =
            HiveBoxes.settings.get('llm_active_provider_id') as String?;
        if (activeId != null && activeId.isNotEmpty) {
          await _writeLlmKey(activeId, llmApiKey, undo);
        }
      }
    }
  }

  Future<void> _writeLlmKey(
    String id,
    String value,
    List<Future<void> Function()> undo,
  ) async {
    final old = await _secureStore.readLlmApiKeyFor(id);
    undo.add(
      () => old == null
          ? _secureStore.deleteLlmApiKeyFor(id)
          : _secureStore.saveLlmApiKeyFor(id, old),
    );
    await _secureStore.saveLlmApiKeyFor(id, value);
  }

  static Map<String, String> _decodeProviderKeys(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value.entries.any((e) => e.key.isEmpty || e.value is! String)) {
      throw const FormatException('备份厂商凭据格式无效');
    }
    return value.cast<String, String>();
  }

  /// 在本机 llm_providers 中按 hint（host|model）匹配配置；
  /// 找不到返回 null（恢复时丢弃该 key）。同 host+model 多条取第一条
  /// （同址同模型的 key 可互换，无实害）。
  String? _matchLlmProviderByHint(String hint) {
    final providers = LlmProviderConfig.decodeList(
      HiveBoxes.settings.get('llm_providers') as String?,
    );
    for (final config in providers) {
      if (_llmKeyHintOf(config.baseUrl, config.model) == hint) {
        return config.id;
      }
    }
    return null;
  }

  /// 当前生效 LLM 配置的 key 归属提示（host|model）；无生效配置返回
  /// 空串（导出端与 active key 同时判断，空串不会写入凭据节）。
  String _activeLlmKeyHint() {
    final activeId =
        HiveBoxes.settings.get('llm_active_provider_id') as String?;
    if (activeId == null || activeId.isEmpty) return '';
    final providers = LlmProviderConfig.decodeList(
      HiveBoxes.settings.get('llm_providers') as String?,
    );
    for (final config in providers) {
      if (config.id == activeId) {
        return _llmKeyHintOf(config.baseUrl, config.model);
      }
    }
    return '';
  }

  /// 配置的归属提示：host 取 baseUrl 解析出的 host（解析失败回退原串），
  /// 与 model 以「|」连接。非敏感（加密节内已含各 API key，host|model
  /// 不新增暴露面）。
  static String _llmKeyHintOf(String baseUrl, String model) =>
      '${_hostOf(baseUrl)}|$model';

  /// 端点比对键：host + 显式端口。
  ///
  /// 与 [_hostOf] 分开是刻意的：`_hostOf` 是 `llm_api_key_hint` 的组成
  /// 部分，属跨版本兼容字段，**不得改动**；而端点比对必须把「同 host 换了
  /// 端口」视为变更 —— 不同端口可能是完全不同的服务，Key 一样会被发过去。
  /// 未显式写端口时不含冒号，避免 `host` 与 `host:443` 误判为不同端点。
  static String _endpointOf(String baseUrl) {
    final trimmed = baseUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return trimmed;
    }
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// 从 baseUrl 解析 host；解析失败回退原串（保持 [_llmKeyHintOf] 的既有
  /// 语义逐字符不变 —— hint 是跨版本兼容字段）。
  static String _hostOf(String baseUrl) {
    final trimmed = baseUrl.trim();
    final host = Uri.tryParse(trimmed)?.host ?? '';
    return host.isEmpty ? trimmed : host;
  }

  /// 读取当前生效 LLM 配置的 API Key（llm_api_key_{activeId}）；
  /// 无生效配置返回 null。
  Future<String?> _readActiveLlmApiKey() async {
    final activeId =
        HiveBoxes.settings.get('llm_active_provider_id') as String?;
    if (activeId == null || activeId.isEmpty) return null;
    return _secureStore.readLlmApiKeyFor(activeId);
  }

  /// 执行实际的数据恢复，返回记录总数。
  Future<int> _doRestore(
    Map<String, dynamic> data, {
    bool canonicalize = true,
  }) async {
    var count = 0;
    final hasAliases = canonicalize &&
        (data['poemProgress'] as List? ?? [])
            .any((m) => PoemIdentity.aliases.containsKey((m as Map)['poemId']));

    if (canonicalize) {
      data = Map<String, dynamic>.from(data);
      for (final entry in {
        'poemProgress': 'progress',
        'poemFavorites': 'favorite',
        'reviewSchedules': 'review',
      }.entries) {
        data[entry.key] =
            PoemIdentity.merge(entry.value, data[entry.key] as List? ?? []);
      }
    }

    count += await _restorePoemProgress(
      data['poemProgress'] as List<dynamic>? ?? [],
    );
    count += await _restorePoemFavorites(
      data['poemFavorites'] as List<dynamic>? ?? [],
    );
    count += await _restoreReviewSchedules(
      data['reviewSchedules'] as List<dynamic>? ?? [],
    );
    count += await _restoreMathMistakes(
      data['mathMistakes'] as List<dynamic>? ?? [],
    );
    count += await _restoreMathSessions(
      data['mathSessions'] as List<dynamic>? ?? [],
    );
    count += await _restoreFormulaFavorites(
      data['formulaFavorites'] as List<dynamic>? ?? [],
    );
    count += await _restoreAchievements(
      data['achievements'] as List<dynamic>? ?? [],
    );
    count += await _restoreCheckIns(
      data['checkIns'] as List<dynamic>? ?? [],
    );
    count += await _restoreUserStats(
      data['userStats'] as List<dynamic>? ?? [],
    );
    count += await _restoreChallengeRecords(
      data['challengeRecords'] as List<dynamic>? ?? [],
    );
    count += await _restoreLearningActivities(
      data['learningActivities'] as List<dynamic>? ?? [],
      canonicalize: canonicalize,
    );
    count += await _restoreLlmProblems(
      data['llmProblems'] as List<dynamic>? ?? [],
    );
    // 旧备份未覆盖聊天数据，不能因恢复旧文件清掉本机新增会话。
    if (data.containsKey('conversations')) {
      await HiveBoxes.messages.clear();
      await HiveBoxes.conversations.clear();
      for (final m
          in (data['conversations'] as List).cast<Map<String, dynamic>>()) {
        final c = Conversation(
          id: m['id'] as String,
          profileId: m['profileId'] as String,
          title: m['title'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          updatedAt: DateTime.parse(m['updatedAt'] as String),
          contextBaseIndex: m['contextBaseIndex'] as int? ?? 0,
        );
        await HiveBoxes.conversations.put('${c.profileId}_${c.id}', c);
        count++;
      }
      for (final m in (data['messages'] as List).cast<Map<String, dynamic>>()) {
        final message = Message(
          id: m['id'] as String,
          profileId: m['profileId'] as String,
          conversationId: m['conversationId'] as String,
          role: MessageRole.values.byName(m['role'] as String),
          content: m['content'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          toolName: m['toolName'] as String?,
          toolCallId: m['toolCallId'] as String?,
        );
        await HiveBoxes.messages
            .put('${message.profileId}_${message.id}', message);
        count++;
      }
    }
    if (data.containsKey('activitySettlements')) {
      await ActivitySettlementLedger.replaceCompletedKeys(
        (data['activitySettlements'] as List<dynamic>).cast<String>(),
      );
    }
    if (data.containsKey('settings')) {
      await _restoreSettings(data['settings'] as Map<String, dynamic>);
    }

    if (hasAliases) await PoemIdentityMigration.refreshCounts();
    return count;
  }

  /// 从文件路径恢复。
  Future<int> restoreFromFile(String filePath, {String? passphrase}) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const FormatException('备份文件不存在');
    }
    final json = await file.readAsString();
    return restoreFromJson(json, passphrase: passphrase);
  }

  // ============ 导出 ============

  List<Map<String, dynamic>> _exportPoemProgress() {
    return HiveBoxes.poemProgress.values.map((p) {
      return <String, dynamic>{
        'poemId': p.poemId,
        'profileId': p.profileId,
        'status': p.status.index,
        'masteryLevel': p.masteryLevel,
        'studyCount': p.studyCount,
        'lastStudiedAt': p.lastStudiedAt?.toIso8601String(),
        'firstStudiedAt': p.firstStudiedAt?.toIso8601String(),
        'stars': p.stars,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportPoemFavorites() {
    return HiveBoxes.poemFavorites.values.map((f) {
      return <String, dynamic>{
        'poemId': f.poemId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportReviewSchedules() {
    return HiveBoxes.reviewSchedules.values.map((r) {
      return <String, dynamic>{
        'poemId': r.poemId,
        'profileId': r.profileId,
        'currentRound': r.currentRound,
        'nextReviewDate': r.nextReviewDate.toIso8601String(),
        'lastReviewedAt': r.lastReviewedAt?.toIso8601String(),
        'isCompleted': r.isCompleted,
        'lastScore': r.lastScore,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportMathMistakes() {
    return HiveBoxes.mathMistakes.values.map((m) {
      return <String, dynamic>{
        'id': m.id,
        'profileId': m.profileId,
        'problemText': m.problemText,
        'correctAnswer': m.correctAnswer,
        'userAnswer': m.userAnswer,
        'problemType': m.problemType,
        'grade': m.grade,
        'errorType': m.errorType,
        'solutionStepsJson': m.solutionStepsJson,
        'createdAt': m.createdAt.toIso8601String(),
        'isResolved': m.isResolved,
        'retryCount': m.retryCount,
        'wrongCount': m.wrongCount,
        'lastWrongAt': m.lastWrongAt?.toIso8601String(),
        'consolidationRound': m.consolidationRound,
        'nextConsolidationDate': m.nextConsolidationDate?.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportMathSessions() {
    return HiveBoxes.mathSessions.values.map((s) {
      return <String, dynamic>{
        'id': s.id,
        'profileId': s.profileId,
        'grade': s.grade,
        'problemType': s.problemType,
        'totalProblems': s.totalProblems,
        'correctCount': s.correctCount,
        'durationSeconds': s.durationSeconds,
        'starsEarned': s.starsEarned,
        'startedAt': s.startedAt.toIso8601String(),
        'finishedAt': s.finishedAt?.toIso8601String(),
        'semester': s.semester,
        'difficulty': s.difficulty,
        'problemsJson': s.problemsJson,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportFormulaFavorites() {
    return HiveBoxes.formulaFavorites.values.map((f) {
      return <String, dynamic>{
        'formulaId': f.formulaId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportAchievements() {
    return HiveBoxes.achievements.values.map((a) {
      return <String, dynamic>{
        'id': a.id,
        'profileId': a.profileId,
        'title': a.title,
        'description': a.description,
        'iconName': a.iconName,
        'isUnlocked': a.isUnlocked,
        'unlockedAt': a.unlockedAt?.toIso8601String(),
        'progress': a.progress,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportCheckIns() {
    return HiveBoxes.checkIns.values.map((c) {
      return <String, dynamic>{
        'profileId': c.profileId,
        'date': c.date,
        'poemCount': c.poemCount,
        'mathTotalCount': c.mathTotalCount,
        'mathCorrectCount': c.mathCorrectCount,
        'starsEarned': c.starsEarned,
        'durationSeconds': c.durationSeconds,
        'isCheckedIn': c.isCheckedIn,
        'activitySources': c.activitySources,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportUserStats() {
    return HiveBoxes.userStats.values.map((s) {
      return <String, dynamic>{
        'profileId': s.profileId,
        'totalStars': s.totalStars,
        'currentStreak': s.currentStreak,
        'longestStreak': s.longestStreak,
        'poemsLearned': s.poemsLearned,
        'poemsMastered': s.poemsMastered,
        'mathTotalProblems': s.mathTotalProblems,
        'mathTotalCorrect': s.mathTotalCorrect,
        'level': s.level,
        'createdAt': s.createdAt.toIso8601String(),
        'mathBestStreak': s.mathBestStreak,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportChallengeRecords() {
    return HiveBoxes.challengeRecords.values.map((r) {
      return <String, dynamic>{
        'id': r.id,
        'profileId': r.profileId,
        'mode': r.mode,
        'score': r.score,
        'totalAnswered': r.totalAnswered,
        'correctCount': r.correctCount,
        'bestCombo': r.bestCombo,
        'grade': r.grade,
        'semester': r.semester,
        'difficulty': r.difficulty,
        'durationSeconds': r.durationSeconds,
        'createdAt': r.createdAt.toIso8601String(),
        'starsEarned': r.starsEarned,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportLearningActivities() {
    return HiveBoxes.learningActivities.values.map((activity) {
      return <String, dynamic>{
        'id': activity.id,
        'profileId': activity.profileId,
        'activityType': activity.activityType,
        'totalItems': activity.totalItems,
        'successfulItems': activity.successfulItems,
        'poemId': activity.poemId,
        'starsEarned': activity.starsEarned,
        'durationSeconds': activity.durationSeconds,
        'completedAt': activity.completedAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportLlmProblems() {
    return HiveBoxes.llmProblems.values.map((p) {
      return <String, dynamic>{
        'id': p.id,
        'profileId': p.profileId,
        'questionText': p.questionText,
        'unit': p.unit,
        'operands': p.operands,
        'operators': p.operators,
        'answer': p.answer,
        'explanation': p.explanation,
        'batchId': p.batchId,
        'createdAt': p.createdAt.toIso8601String(),
        'grade': p.grade,
        'semester': p.semester,
        'topic': p.topic,
        'difficulty': p.difficulty,
        'done': p.done,
        'attempts': p.attempts,
        'correctCount': p.correctCount,
        'lastDoneAt': p.lastDoneAt?.toIso8601String(),
      };
    }).toList();
  }

  Map<String, dynamic> _exportSettings() {
    final box = HiveBoxes.settings;
    final result = <String, dynamic>{};
    // 只导白名单 key：排除 key（外部服务端点、凭据绑定状态）留在本机，
    // 备份文件干净且不误导「配置会同步」。
    for (final key in box.keys) {
      final name = key.toString();
      if (!_settingsValueType.containsKey(name)) continue;
      result[name] = box.get(key);
    }
    return result;
  }

  // ============ 恢复 ============

  Future<int> _restorePoemProgress(List<dynamic> items) async {
    final box = HiveBoxes.poemProgress;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = PoemProgress(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        status: LearningStatus.values[m['status'] as int? ?? 0],
        masteryLevel: m['masteryLevel'] as int? ?? 0,
        studyCount: m['studyCount'] as int? ?? 0,
        lastStudiedAt: _parseDateTime(m['lastStudiedAt']),
        firstStudiedAt: _parseDateTime(m['firstStudiedAt']),
        stars: m['stars'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restorePoemFavorites(List<dynamic> items) async {
    final box = HiveBoxes.poemFavorites;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = PoemFavorite(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreReviewSchedules(List<dynamic> items) async {
    final box = HiveBoxes.reviewSchedules;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = ReviewSchedule(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        currentRound: m['currentRound'] as int? ?? 0,
        nextReviewDate: _parseDateTime(m['nextReviewDate']) ?? DateTime.now(),
        lastReviewedAt: _parseDateTime(m['lastReviewedAt']),
        isCompleted: m['isCompleted'] as bool? ?? false,
        lastScore: (m['lastScore'] as num?)?.toDouble(),
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreMathMistakes(List<dynamic> items) async {
    final box = HiveBoxes.mathMistakes;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = MathMistake(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        problemText: m['problemText'] as String,
        correctAnswer: m['correctAnswer'] as String,
        userAnswer: m['userAnswer'] as String,
        problemType: m['problemType'] as String,
        grade: m['grade'] as int,
        errorType: m['errorType'] as String?,
        solutionStepsJson: m['solutionStepsJson'] as String?,
        createdAt: _parseDateTime(m['createdAt']),
        isResolved: m['isResolved'] as bool? ?? false,
        retryCount: m['retryCount'] as int? ?? 0,
        wrongCount: m['wrongCount'] as int? ?? 1,
        lastWrongAt: _parseDateTime(m['lastWrongAt']),
        consolidationRound: m['consolidationRound'] as int? ?? 0,
        nextConsolidationDate: _parseDateTime(m['nextConsolidationDate']),
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreMathSessions(List<dynamic> items) async {
    final box = HiveBoxes.mathSessions;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = MathSession(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        grade: m['grade'] as int,
        problemType: m['problemType'] as String,
        totalProblems: m['totalProblems'] as int,
        correctCount: m['correctCount'] as int? ?? 0,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        starsEarned: m['starsEarned'] as int? ?? 0,
        startedAt: _parseDateTime(m['startedAt']),
        finishedAt: _parseDateTime(m['finishedAt']),
        semester: m['semester'] as String?,
        difficulty: m['difficulty'] as String?,
        problemsJson: m['problemsJson'] as String?,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreFormulaFavorites(List<dynamic> items) async {
    final box = HiveBoxes.formulaFavorites;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = FormulaFavorite(
        formulaId: m['formulaId'] as String,
        profileId: m['profileId'] as String,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.formulaId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreAchievements(List<dynamic> items) async {
    final box = HiveBoxes.achievements;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = Achievement(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        title: m['title'] as String,
        description: m['description'] as String? ?? '',
        iconName: m['iconName'] as String? ?? 'trophy',
        isUnlocked: m['isUnlocked'] as bool? ?? false,
        unlockedAt: _parseDateTime(m['unlockedAt']),
        progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreCheckIns(List<dynamic> items) async {
    final box = HiveBoxes.checkIns;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = CheckIn(
        profileId: m['profileId'] as String,
        date: m['date'] as String,
        poemCount: m['poemCount'] as int? ?? 0,
        mathTotalCount: m['mathTotalCount'] as int? ?? 0,
        mathCorrectCount: m['mathCorrectCount'] as int? ?? 0,
        starsEarned: m['starsEarned'] as int? ?? 0,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        isCheckedIn: m['isCheckedIn'] as bool? ?? true,
        activitySources: m['activitySources'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.date}', obj);
    }
    return items.length;
  }

  Future<int> _restoreUserStats(List<dynamic> items) async {
    final box = HiveBoxes.userStats;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = UserStats(
        profileId: m['profileId'] as String,
        totalStars: m['totalStars'] as int? ?? 0,
        currentStreak: m['currentStreak'] as int? ?? 0,
        longestStreak: m['longestStreak'] as int? ?? 0,
        poemsLearned: m['poemsLearned'] as int? ?? 0,
        poemsMastered: m['poemsMastered'] as int? ?? 0,
        mathTotalProblems: m['mathTotalProblems'] as int? ?? 0,
        mathTotalCorrect: m['mathTotalCorrect'] as int? ?? 0,
        level: m['level'] as int? ?? 0,
        createdAt: _parseDateTime(m['createdAt']),
        mathBestStreak: m['mathBestStreak'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_stats', obj);
    }
    return items.length;
  }

  Future<int> _restoreChallengeRecords(List<dynamic> items) async {
    final box = HiveBoxes.challengeRecords;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = ChallengeRecord(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        mode: m['mode'] as String,
        score: m['score'] as int,
        totalAnswered: m['totalAnswered'] as int,
        correctCount: m['correctCount'] as int,
        bestCombo: m['bestCombo'] as int? ?? 0,
        grade: m['grade'] as int,
        semester: m['semester'] as String,
        difficulty: m['difficulty'] as String,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        createdAt: _parseDateTime(m['createdAt']),
        starsEarned: m['starsEarned'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreLearningActivities(
    List<dynamic> items, {
    bool canonicalize = true,
  }) async {
    final box = HiveBoxes.learningActivities;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final activity = LearningActivity(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        activityType: m['activityType'] as String,
        totalItems: m['totalItems'] as int,
        successfulItems: m['successfulItems'] as int,
        poemId: m['poemId'] == null
            ? null
            : canonicalize
                ? PoemIdentity.canonical(m['poemId'] as String)
                : m['poemId'] as String,
        starsEarned: m['starsEarned'] as int,
        durationSeconds: m['durationSeconds'] as int,
        completedAt: DateTime.parse(m['completedAt'] as String),
      );
      await box.put('${activity.profileId}_${activity.id}', activity);
    }
    return items.length;
  }

  Future<int> _restoreLlmProblems(List<dynamic> items) async {
    final box = HiveBoxes.llmProblems;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = LlmProblem(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        questionText: m['questionText'] as String,
        unit: m['unit'] as String,
        operands: (m['operands'] as List<dynamic>).cast<int>(),
        operators: (m['operators'] as List<dynamic>).cast<String>(),
        answer: m['answer'] as int,
        explanation: m['explanation'] as String? ?? '',
        batchId: m['batchId'] as String,
        createdAt: _parseDateTime(m['createdAt']) ?? DateTime.now(),
        grade: m['grade'] as int,
        semester: m['semester'] as String,
        topic: m['topic'] as String,
        difficulty: m['difficulty'] as int,
        done: m['done'] as bool? ?? false,
        attempts: m['attempts'] as int? ?? 0,
        correctCount: m['correctCount'] as int? ?? 0,
        lastDoneAt: _parseDateTime(m['lastDoneAt']),
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<void> _restoreSettings(Map<String, dynamic> items) async {
    final box = HiveBoxes.settings;

    // 先规范化全部白名单内的值（类型不符跳过该 key，不毁整个恢复）。
    final normalized = <String, Object>{};
    for (final entry in items.entries) {
      final expected = _settingsValueType[entry.key];
      if (expected == null) continue; // 白名单外：跳过
      final value = _normalizeSettingValue(entry.value, expected);
      if (value == null) continue; // 类型不符：跳过
      if (!SettingsConstraints.accepts(entry.key, value)) continue;
      normalized[entry.key] = value;
    }

    // LLM 一致性过滤：不落悬空 id / 坏结构（见 _filterLlmSettings）。
    // 非 LLM key 原样透传。
    final accepted = _filterLlmSettings(normalized);

    // 只删「最终会被写入」的 key，而非遍历 items.keys 或全白名单：
    // - 遍历全白名单 → 旧备份会抹掉本机新纳入的 LLM 配置；
    // - 遍历 items.keys → 备份中结构不合格（如坏 llm_providers）或类型
    //   不符的 key 被删后无写回，本机原值丢失。
    // 语义：备份中**有效给出**的 key 以备份为准，其余保留本机。
    for (final key in accepted.keys) {
      await box.delete(key);
    }
    for (final entry in accepted.entries) {
      await box.put(entry.key, entry.value);
    }
  }

  /// LLM 相关 settings 的一致性过滤（加固，非安全边界 —— 安全边界是恢复前的
  /// 端点确认框）。返回可落盘的子集；不合规的单个 key 跳过，不影响其余数据。
  /// 非 LLM key 原样透传（本方法同时充当「写入集」的构造入口）。
  ///
  /// 运行时消费端已能容忍悬空（`providerIdForScenario` 返回 null、
  /// `llmActiveProviderId` 自动回落、`_assembleLlmConfig` 对悬空 model 回落
  /// 默认），此处过滤的目的是**不把垃圾落盘**，不是防崩溃。
  Map<String, Object> _filterLlmSettings(Map<String, Object> values) {
    // 非 LLM key 透传。
    final out = <String, Object>{
      for (final entry in values.entries)
        if (!_isLlmSettingKey(entry.key)) entry.key: entry.value,
    };

    // 1. llm_providers：结构探测。区分「坏结构 → 跳过」与「合法空列表 → 放行」
    //    （用户主动清空厂商列表必须能恢复）。
    var providerIds = <String>{};
    final rawProviders = values['llm_providers'];
    if (rawProviders is String) {
      final parsed = _tryParseProviderList(rawProviders);
      if (parsed != null) {
        out['llm_providers'] = rawProviders;
        providerIds = parsed.map((c) => c.id).toSet();
      }
    }

    // 2. legacy llm_base_url：仅校验合法性（丢弃 normalizeBaseUrl 返回值 ——
    //    它会补 /v1 改变值；此处只判断抛不抛异常）。
    final legacyBase = values['llm_base_url'];
    if (legacyBase is String && _isValidBaseUrl(legacyBase)) {
      out['llm_base_url'] = legacyBase;
      // 3. legacy llm_model：仅在 base 也落盘时写入（孤立的 model 无意义）。
      final legacyModel = values['llm_model'];
      if (legacyModel is String) out['llm_model'] = legacyModel;
    }

    // 4. active 与场景绑定：值须 ∈ 本次落盘的厂商 id 集合。
    final activeId = values['llm_active_provider_id'];
    if (activeId is String && providerIds.contains(activeId)) {
      out['llm_active_provider_id'] = activeId;
    }
    for (final scenario in LlmScenario.values) {
      final boundId = values[scenario.settingsKey];
      if (boundId is! String || !providerIds.contains(boundId)) continue;
      out[scenario.settingsKey] = boundId;
      // 5. 场景 model：仅在绑定也落盘时写入（boundId 已校验存在）。
      final model = values[scenario.modelKey];
      if (model is String) out[scenario.modelKey] = model;
    }

    return out;
  }

  /// 该 key 是否属于「受一致性过滤约束的 LLM 配置类 key」。
  ///
  /// 注意与 `llm_provider_name` / `llm_*_prompt` 区分：后者是纯展示名与
  /// 提示词文本，不指向外部服务，不受过滤约束（照常透传）。
  static bool _isLlmSettingKey(String key) {
    if (key.startsWith('llm_provider_') || key.startsWith('llm_model_')) {
      // llm_provider_name 是纯展示名，不是场景绑定 —— 透传。
      return key != 'llm_provider_name';
    }
    return key == 'llm_providers' ||
        key == 'llm_active_provider_id' ||
        key == 'llm_base_url' ||
        key == 'llm_model';
  }

  /// 结构探测 `llm_providers` 字符串：坏结构返回 null，合法（含空列表）
  /// 返回配置列表。
  ///
  /// **不得**改用 `LlmProviderConfig.decodeList(...).isEmpty` 判定 ——
  /// decodeList 对坏 JSON / 坏条目同样返回空列表（见其注释「坏数据回退空
  /// 列表」），会与「用户主动清空厂商列表」混淆，导致清空操作恢复失效。
  static List<LlmProviderConfig>? _tryParseProviderList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((e) => LlmProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object {
      // TypeError 是 Error 不是 Exception，须捕 Object 兜全。
      return null;
    }
  }

  /// 校验 baseUrl 合法性；不改变值（规范化由写入侧负责）。
  static bool _isValidBaseUrl(String raw) {
    try {
      LlmClient.normalizeBaseUrl(raw);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// 按白名单类型契约规范化 settings 值；类型不符返回 null（跳过该 key）。
  ///
  /// - 'string'：仅接受 String；
  /// - 'bool'：仅接受 bool；
  /// - 'int'：仅接受 int（JSON 的 1.5 解出 double → 拒绝）；
  /// - 'double'：接受任意 num 并 `toDouble()`（JSON 整数 1 合法化为 1.0）。
  Object? _normalizeSettingValue(Object? value, String expected) {
    switch (expected) {
      case 'string':
        return value is String ? value : null;
      case 'bool':
        return value is bool ? value : null;
      case 'int':
        return value is int ? value : null;
      case 'double':
        return value is num ? value.toDouble() : null;
    }
    return null;
  }

  // ============ 工具 ============

  Map<String, dynamic> _decodeAndValidate(String jsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw const FormatException('无效的备份文件格式');
    }

    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('备份文件顶层必须是 JSON 对象');
    }

    final data = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('备份文件包含无效的顶层键');
      }
      data[entry.key as String] = entry.value;
    }

    final version = data['version'];
    if (version != null && (version is! int || version < 0)) {
      throw const FormatException('备份文件版本号无效');
    }
    if (version is int && version > _backupVersion) {
      throw FormatException('备份文件版本 ($version) 高于当前支持版本');
    }
    _validateOptionalDate(data, 'exportedAt', 'top-level');

    _validateList(data, 'poemProgress', _validatePoemProgress);
    _validateList(data, 'poemFavorites', _validatePoemFavorite);
    _validateList(data, 'reviewSchedules', _validateReviewSchedule);
    _validateList(data, 'mathMistakes', _validateMathMistake);
    _validateList(data, 'mathSessions', _validateMathSession);
    _validateList(data, 'formulaFavorites', _validateFormulaFavorite);
    _validateList(data, 'achievements', _validateAchievement);
    _validateList(data, 'checkIns', _validateCheckIn);
    _validateList(data, 'userStats', _validateUserStats);
    _validateList(data, 'challengeRecords', _validateChallengeRecord);
    _validateList(data, 'learningActivities', _validateLearningActivity);
    _validateList(data, 'llmProblems', _validateLlmProblem);
    _validateAssistantData(data);
    _validateUniqueLearningActivityIds(data);
    _validateActivitySettlements(data);

    if (data.containsKey('settings')) {
      final settings = data['settings'];
      if (settings is! Map<Object?, Object?>) {
        _invalidField('settings', '必须是 JSON 对象');
      }
      _validateJsonObject(settings, 'settings');
    }

    if (data.containsKey('credentials')) {
      final credentials = data['credentials'];
      if (credentials is! Map<Object?, Object?>) {
        _invalidField('credentials', '必须是 JSON 对象');
      }
    }

    return data;
  }

  void _validateAssistantData(Map<String, dynamic> data) {
    if (!data.containsKey('conversations') && !data.containsKey('messages')) {
      return;
    }
    if (!data.containsKey('conversations') || !data.containsKey('messages')) {
      _invalidField('conversations/messages', '会话和消息须一起提供');
    }
    final conversations = <String, int>{};
    final boundaries = <String, int>{};
    _validateList(data, 'conversations', (m, path) {
      for (final key in [
        'id',
        'profileId',
        'title',
        'createdAt',
        'updatedAt',
      ]) {
        _requiredString(m, key, path);
      }
      _validateOptionalDate(m, 'createdAt', path);
      _validateOptionalDate(m, 'updatedAt', path);
      _optionalNonNegativeInt(m, 'contextBaseIndex', path);
      final key = '${m['profileId']}_${m['id']}';
      if (conversations.containsKey(key)) _invalidField(path, '会话 ID 重复');
      conversations[key] = 0;
      boundaries[key] = m['contextBaseIndex'] as int? ?? 0;
    });
    final ids = <String>{};
    _validateList(data, 'messages', (m, path) {
      for (final key in [
        'id',
        'profileId',
        'conversationId',
        'role',
        'createdAt',
      ]) {
        _requiredString(m, key, path);
      }
      if (m['content'] is! String) _invalidField(path, '消息内容类型无效');
      if (!MessageRole.values.map((r) => r.name).contains(m['role'])) {
        _invalidField(path, '消息角色无效');
      }
      for (final key in ['toolName', 'toolCallId']) {
        if (m[key] != null && m[key] is! String) {
          _invalidField(path, '工具字段类型无效');
        }
      }
      _validateOptionalDate(m, 'createdAt', path);
      if (!ids.add('${m['profileId']}_${m['id']}')) {
        _invalidField(path, '消息 ID 重复');
      }
      final parent = '${m['profileId']}_${m['conversationId']}';
      if (!conversations.containsKey(parent)) _invalidField(path, '消息对应会话不存在');
      conversations[parent] = conversations[parent]! + 1;
    });
    for (final entry in boundaries.entries) {
      if (entry.value > conversations[entry.key]!) {
        _invalidField('contextBaseIndex', '超出消息范围');
      }
    }
  }

  void _validateActivitySettlements(Map<String, dynamic> data) {
    if (!data.containsKey('activitySettlements')) return;
    final value = data['activitySettlements'];
    if (value is! List<Object?>) {
      _invalidField('activitySettlements', '必须是 JSON 数组');
    }

    final keys = <String>{};
    for (var index = 0; index < value.length; index++) {
      final key = value[index];
      if (key is! String || !ActivitySettlementLedger.isSettlementKey(key)) {
        _invalidField('activitySettlements[$index]', '不是有效的活动结算标记');
      }
      if (!keys.add(key)) {
        _invalidField('activitySettlements[$index]', '活动结算标记重复');
      }
    }
  }

  void _validateList(
    Map<String, dynamic> data,
    String key,
    void Function(Map<String, dynamic> item, String path) validator,
  ) {
    if (!data.containsKey(key)) return;
    final value = data[key];
    if (value is! List<Object?>) {
      _invalidField(key, '必须是 JSON 数组');
    }

    for (var index = 0; index < value.length; index++) {
      final rawItem = value[index];
      if (rawItem is! Map<Object?, Object?>) {
        _invalidField('$key[$index]', '必须是 JSON 对象');
      }
      final item = <String, dynamic>{};
      for (final entry in rawItem.entries) {
        if (entry.key is! String) {
          _invalidField('$key[$index]', '包含无效字段名');
        }
        item[entry.key as String] = entry.value;
      }
      validator(item, '$key[$index]');
    }
  }

  void _validatePoemProgress(Map<String, dynamic> item, String path) {
    _requiredString(item, 'poemId', path);
    _requiredString(item, 'profileId', path);
    _optionalInt(
      item,
      'status',
      path,
      min: 0,
      max: LearningStatus.values.length - 1,
    );
    _optionalInt(item, 'masteryLevel', path, min: 0, max: 5);
    _optionalNonNegativeInt(item, 'studyCount', path);
    _optionalNonNegativeInt(item, 'stars', path);
    _validateOptionalDate(item, 'lastStudiedAt', path);
    _validateOptionalDate(item, 'firstStudiedAt', path);
  }

  void _validatePoemFavorite(Map<String, dynamic> item, String path) {
    _requiredString(item, 'poemId', path);
    _requiredString(item, 'profileId', path);
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateReviewSchedule(Map<String, dynamic> item, String path) {
    _requiredString(item, 'poemId', path);
    _requiredString(item, 'profileId', path);
    _optionalInt(
      item,
      'currentRound',
      path,
      min: 0,
      max: ReviewSchedule.intervals.length,
    );
    _validateOptionalDate(item, 'nextReviewDate', path);
    _validateOptionalDate(item, 'lastReviewedAt', path);
    _optionalBool(item, 'isCompleted', path);
    _optionalScore(item, 'lastScore', path);
  }

  void _validateMathMistake(Map<String, dynamic> item, String path) {
    for (final key in <String>[
      'id',
      'profileId',
      'problemText',
      'correctAnswer',
      'userAnswer',
      'problemType',
    ]) {
      _requiredString(item, key, path);
    }
    _requiredInt(item, 'grade', path);
    _optionalNullableString(item, 'errorType', path);
    _optionalNullableString(item, 'solutionStepsJson', path);
    _validateOptionalDate(item, 'createdAt', path);
    _optionalBool(item, 'isResolved', path);
    _optionalNonNegativeInt(item, 'retryCount', path);
    _optionalNonNegativeInt(item, 'wrongCount', path);
    _validateOptionalDate(item, 'lastWrongAt', path);
    _optionalInt(
      item,
      'consolidationRound',
      path,
      min: 0,
      max: MathMistakeRepository.consolidationIntervals.length,
    );
    _validateOptionalDate(item, 'nextConsolidationDate', path);
  }

  void _validateMathSession(Map<String, dynamic> item, String path) {
    for (final key in <String>['id', 'profileId', 'problemType']) {
      _requiredString(item, key, path);
    }
    _requiredInt(item, 'grade', path);
    _requiredNonNegativeInt(item, 'totalProblems', path);
    _optionalNonNegativeInt(item, 'correctCount', path);
    _optionalNonNegativeInt(item, 'durationSeconds', path);
    _optionalNonNegativeInt(item, 'starsEarned', path);
    _validateOptionalDate(item, 'startedAt', path);
    _validateOptionalDate(item, 'finishedAt', path);
    _optionalNullableString(item, 'semester', path);
    _optionalNullableString(item, 'difficulty', path);
    if (item['semester'] != null) {
      _optionalEnumString(
        item,
        'semester',
        path,
        const <String>{'上', '下'},
      );
    }
    if (item['difficulty'] != null) {
      _optionalEnumString(
        item,
        'difficulty',
        path,
        const <String>{'easy', 'medium', 'hard'},
      );
    }
    _optionalNullableString(item, 'problemsJson', path);
  }

  void _validateFormulaFavorite(Map<String, dynamic> item, String path) {
    _requiredString(item, 'formulaId', path);
    _requiredString(item, 'profileId', path);
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateAchievement(Map<String, dynamic> item, String path) {
    _requiredString(item, 'id', path);
    _requiredString(item, 'profileId', path);
    _requiredString(item, 'title', path);
    _optionalNullableString(item, 'description', path);
    _optionalNullableString(item, 'iconName', path);
    _optionalBool(item, 'isUnlocked', path);
    _validateOptionalDate(item, 'unlockedAt', path);
    final progress = item['progress'];
    if (progress != null &&
        (progress is! num || progress < 0 || progress > 1)) {
      _invalidField('$path.progress', '必须是 0 到 1 之间的数字');
    }
  }

  void _validateCheckIn(Map<String, dynamic> item, String path) {
    _requiredString(item, 'profileId', path);
    _requiredString(item, 'date', path);
    for (final key in <String>[
      'poemCount',
      'mathTotalCount',
      'mathCorrectCount',
      'starsEarned',
      'durationSeconds',
    ]) {
      _optionalNonNegativeInt(item, key, path);
    }
    _optionalBool(item, 'isCheckedIn', path);
    final sources = item['activitySources'];
    if (sources != null &&
        (sources is! int || sources < 0 || (sources & ~3) != 0)) {
      _invalidField('$path.activitySources', '包含未知来源标记');
    }
  }

  void _validateUserStats(Map<String, dynamic> item, String path) {
    _requiredString(item, 'profileId', path);
    for (final key in <String>[
      'totalStars',
      'currentStreak',
      'longestStreak',
      'poemsLearned',
      'poemsMastered',
      'mathTotalProblems',
      'mathTotalCorrect',
      'mathBestStreak',
    ]) {
      _optionalNonNegativeInt(item, key, path);
    }
    _optionalInt(
      item,
      'level',
      path,
      min: 0,
      max: UserStats.levelNames.length - 1,
    );
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateChallengeRecord(Map<String, dynamic> item, String path) {
    for (final key in <String>[
      'id',
      'profileId',
      'mode',
      'semester',
      'difficulty',
    ]) {
      _requiredString(item, key, path);
    }
    _optionalEnumString(
      item,
      'mode',
      path,
      const <String>{'fixed', 'extending'},
    );
    _optionalEnumString(item, 'semester', path, const <String>{'上', '下'});
    _optionalEnumString(
      item,
      'difficulty',
      path,
      const <String>{'easy', 'medium', 'hard'},
    );
    for (final key in <String>[
      'score',
      'totalAnswered',
      'correctCount',
      'bestCombo',
      'grade',
      'durationSeconds',
    ]) {
      _requiredNonNegativeInt(item, key, path);
    }
    _optionalNonNegativeInt(item, 'starsEarned', path);
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateLearningActivity(Map<String, dynamic> item, String path) {
    _requiredString(item, 'id', path);
    _requiredString(item, 'profileId', path);
    final activityType = _requiredString(item, 'activityType', path);
    final allowedTypes =
        LearningActivityType.values.map((type) => type.name).toSet();
    if (!allowedTypes.contains(activityType)) {
      _invalidField('$path.activityType', '不是受支持的枚举值');
    }

    final totalItems = _requiredInt(item, 'totalItems', path);
    final successfulItems = _requiredInt(item, 'successfulItems', path);
    final starsEarned = _requiredInt(item, 'starsEarned', path);
    final durationSeconds = _requiredInt(item, 'durationSeconds', path);
    if (totalItems < 0) {
      _invalidField('$path.totalItems', '不能为负数');
    }
    if (successfulItems < 0 || successfulItems > totalItems) {
      _invalidField('$path.successfulItems', '必须介于 0 和总数之间');
    }
    if (starsEarned < 0 || starsEarned > 3) {
      _invalidField('$path.starsEarned', '必须介于 0 和 3 之间');
    }
    if (durationSeconds < 0) {
      _invalidField('$path.durationSeconds', '不能为负数');
    }

    _optionalNullableString(item, 'poemId', path);
    final poemId = item['poemId'];
    if (poemId is String && poemId.isEmpty) {
      _invalidField('$path.poemId', '不能是空字符串');
    }
    final requiresPoem =
        activityType == LearningActivityType.poemRecitation.name ||
            activityType == LearningActivityType.poemQuiz.name ||
            activityType == LearningActivityType.poemDictation.name ||
            activityType == LearningActivityType.readAlong.name;
    if (requiresPoem && poemId is! String) {
      _invalidField('$path.poemId', '诗词活动必须提供诗词 ID');
    }

    final completedAt = item['completedAt'];
    if (completedAt is! String || DateTime.tryParse(completedAt) == null) {
      _invalidField('$path.completedAt', '必须是有效的 ISO 日期字符串');
    }
  }

  void _validateLlmProblem(Map<String, dynamic> item, String path) {
    for (final key in <String>[
      'id',
      'profileId',
      'questionText',
      'unit',
      'batchId',
      'semester',
      'topic',
    ]) {
      _requiredString(item, key, path);
    }
    final answer = _requiredInt(item, 'answer', path);
    _requiredInt(item, 'grade', path);
    _requiredInt(item, 'difficulty', path);
    _optionalNonNegativeInt(item, 'attempts', path);
    _optionalNonNegativeInt(item, 'correctCount', path);
    _optionalBool(item, 'done', path);
    _validateOptionalDate(item, 'createdAt', path);
    _validateOptionalDate(item, 'lastDoneAt', path);

    // 运算符类型检查：非空字符串数组
    final operators = item['operators'];
    if (operators is! List<Object?> ||
        operators.any((op) => op is! String || op.isEmpty)) {
      _invalidField('$path.operators', '必须是非空字符串数组');
    }
    // 操作数类型检查：非负整数
    final operands = item['operands'];
    if (operands is! List<Object?> || operands.any((v) => v is! int || v < 0)) {
      _invalidField('$path.operands', '必须是非负整数数组');
    }

    // ---- 语义校验：与生成侧 WordProblemValidator 同一信任标准 ----
    // 校验失败抛 FormatException，发生在任何 Box clear 之前。
    // 运算符白名单：symbol → Operator 映射，白名单即 Operator.symbol
    //（+、-、×、÷），映射不到即拒。
    final bySymbol = <String, Operator>{
      for (final op in Operator.values) op.symbol: op,
    };
    final mappedOperators = <Operator>[];
    for (final symbol in operators.cast<String>()) {
      final mapped = bySymbol[symbol];
      if (mapped == null) {
        _invalidField('$path.operators', '包含未知运算符: $symbol');
      }
      mappedOperators.add(mapped);
    }
    // 结构约束：operands 非空且数量 = 运算符数 + 1
    //（消除 expressionText 直接取 operands.first/[i+1] 的越界数据面风险）。
    final operandValues = operands.cast<int>();
    if (operandValues.isEmpty ||
        operandValues.length != mappedOperators.length + 1) {
      _invalidField('$path.operands', '与运算符数量不匹配');
    }
    // answer 非负：骨架全为非负整数，负 answer 是脏数据
    //（如 [4,12] + '-' 求值恰为 -8，仅靠求值一致性拦不住显式负数）。
    if (answer < 0) {
      _invalidField('$path.answer', '不能为负数');
    }
    // 求值一致性：ExpressionEvaluator 复算必须等于 answer（整数结果）。
    final evaluated = ExpressionEvaluator.evaluate(
      operandValues.map(NumberValue.fromInt).toList(),
      mappedOperators,
    );
    if (evaluated == null ||
        !evaluated.isInteger ||
        evaluated.asInteger != answer) {
      _invalidField('$path.answer', '与算式求值不一致');
    }
  }

  void _validateUniqueLearningActivityIds(Map<String, dynamic> data) {
    final activities = data['learningActivities'];
    if (activities is! List<Object?>) return;

    final keys = <String>{};
    for (var index = 0; index < activities.length; index++) {
      final activity = activities[index] as Map<Object?, Object?>;
      final key = '${activity['profileId']}\u0000${activity['id']}';
      if (!keys.add(key)) {
        _invalidField(
          'learningActivities[$index].id',
          '同一用户下活动 ID 重复',
        );
      }
    }
  }

  void _validateJsonObject(Map<Object?, Object?> object, String path) {
    for (final entry in object.entries) {
      if (entry.key is! String) {
        _invalidField(path, '包含无效字段名');
      }
      _validateJsonValue(entry.value, '$path.${entry.key}');
    }
  }

  void _validateJsonValue(Object? value, String path) {
    if (value == null || value is String || value is num || value is bool) {
      return;
    }
    if (value is List<Object?>) {
      for (var index = 0; index < value.length; index++) {
        _validateJsonValue(value[index], '$path[$index]');
      }
      return;
    }
    if (value is Map<Object?, Object?>) {
      _validateJsonObject(value, path);
      return;
    }
    _invalidField(path, '不是有效的 JSON 值');
  }

  String _requiredString(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value is! String || value.isEmpty) {
      _invalidField('$path.$key', '必须是非空字符串');
    }
    return value;
  }

  void _optionalNullableString(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value != null && value is! String) {
      _invalidField('$path.$key', '必须是字符串或 null');
    }
  }

  int _requiredInt(Map<String, dynamic> item, String key, String path) {
    final value = item[key];
    if (value is! int) _invalidField('$path.$key', '必须是整数');
    return value;
  }

  void _requiredNonNegativeInt(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = _requiredInt(item, key, path);
    if (value < 0) _invalidField('$path.$key', '不能为负数');
  }

  void _optionalNonNegativeInt(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value == null) return;
    if (value is! int || value < 0) {
      _invalidField('$path.$key', '必须是非负整数');
    }
  }

  void _optionalInt(
    Map<String, dynamic> item,
    String key,
    String path, {
    int? min,
    int? max,
  }) {
    final value = item[key];
    if (value == null) return;
    if (value is! int ||
        (min != null && value < min) ||
        (max != null && value > max)) {
      _invalidField('$path.$key', '整数超出允许范围');
    }
  }

  void _optionalBool(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value != null && value is! bool) {
      _invalidField('$path.$key', '必须是布尔值');
    }
  }

  void _optionalScore(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value == null) return;
    if (value is! num || value < 0 || value > 1) {
      _invalidField('$path.$key', '必须是 0.0–1.0 之间的得分或 null');
    }
  }

  void _optionalEnumString(
    Map<String, dynamic> item,
    String key,
    String path,
    Set<String> allowed,
  ) {
    final value = item[key];
    if (value is! String || !allowed.contains(value)) {
      _invalidField('$path.$key', '不是受支持的枚举值');
    }
  }

  void _validateOptionalDate(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value == null) return;
    if (value is! String || DateTime.tryParse(value) == null) {
      _invalidField('$path.$key', '必须是有效的 ISO 日期字符串或 null');
    }
  }

  Never _invalidField(String path, String reason) {
    throw FormatException('备份字段 $path 无效：$reason');
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// 恢复写入失败；[rollbackError] 非 null 表示回滚也失败。
class BackupRestoreException implements Exception {
  const BackupRestoreException(
    this.message, {
    this.cause,
    this.rollbackError,
  });

  final String message;
  final Object? cause;
  final Object? rollbackError;

  bool get rollbackFailed => rollbackError != null;

  @override
  String toString() => 'BackupRestoreException: $message';
}

/// 单条 LLM 端点变更（同 id 配置的 host 变化）。
class LlmEndpointChange {
  const LlmEndpointChange({
    required this.label,
    required this.from,
    required this.to,
  });

  /// 配置显示名（name 为空时回落「配置 N」）。
  final String label;

  /// 本机 host。
  final String from;

  /// 备份 host。
  final String to;

  @override
  String toString() => 'LlmEndpointChange($label: $from → $to)';
}

/// 备份与本机的 LLM 端点差异摘要（恢复前确认框的数据源）。
///
/// 只含 host，不含完整 URL —— 降低无谓的信息暴露，也避免长串撑爆弹框。
class LlmEndpointChangeSet {
  const LlmEndpointChangeSet({
    required this.added,
    required this.changed,
    required this.removed,
  });

  /// 备份有、本机无的 host。
  final List<String> added;

  /// 同 id 但 host 变了的配置。
  final List<LlmEndpointChange> changed;

  /// 本机有、备份无的 host（信息性，不触发确认框）。
  final List<String> removed;

  /// 是否需要用户确认 —— 只有新增与变更构成外泄风险；移除不打扰用户。
  bool get isEmpty => added.isEmpty && changed.isEmpty;

  @override
  String toString() => 'LlmEndpointChangeSet(added: $added, changed: $changed, '
      'removed: $removed)';
}
