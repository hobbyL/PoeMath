// lib/data/repositories/settings_repository.dart
//
// 层级：data/repositories
// 职责：应用设置仓储。使用 settingsBox 作为 KV 存储。

import 'dart:convert';

import 'package:poemath/core/services/parent_access_service.dart';

import 'package:crypto/crypto.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/settings_constraints.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/domain/math_entry_kind.dart';
import 'package:poemath/domain/completion_sound.dart';
import 'package:poemath/domain/answer_feedback_sound.dart';

class SettingsRepository {
  // 跨仓储实例记录本进程内的手动配置写入，覆盖多次凭据复核之间的异步窗口。
  static final Map<String, int> _llmProviderVersions = {};

  static void _markLlmProviderWrite(String id) {
    _llmProviderVersions[id] = (_llmProviderVersions[id] ?? 0) + 1;
  }

  int _boundedInt(String key, int fallback) {
    final value = HiveBoxes.settings.get(key);
    return value is int && SettingsConstraints.accepts(key, value)
        ? value
        : fallback;
  }

  SettingsRepository({SecureCredentialStore? credentialStore})
      : _credentialStore = credentialStore ?? SecureCredentialStore();

  /// 迁移并发去重的 in-flight Future（R5）；repo 由 Provider 缓存为
  /// 单例，实例级去重覆盖全部并发面。失败时 whenComplete 清空，
  /// 后续调用允许重试。
  Future<void>? _legacyMigrationInFlight;
  // ============ KV 键名 ============
  // 注意：新增需要随备份迁移的 settings key 时，必须同步登记到
  // backup_service.dart 的 _settingsValueType 白名单（并注明类型），
  // 否则该 key 不会随备份导出/恢复；指向外部服务或绑定凭据的 key
  // 一律不得加入白名单（设备绑定，换机重配）。
  static const String _keyThemeMode =
      'theme_mode'; // 'system' | 'light' | 'dark'
  static const String _keyActiveSubject = 'active_subject'; // 'poem' | 'math'
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyHapticEnabled = 'haptic_enabled';
  static const String _keySelectedGrade = 'selected_grade';
  static const String _keySelectedSemester = 'selected_semester';
  static const String _keyTtsSpeed = 'tts_speed';
  static const String _keyTtsVoice =
      'tts_voice'; // JSON: {"name":"...", "locale":"..."}
  static const String _keyDailyPoemGoal = 'daily_poem_goal';
  static const String _keyDailyMathGoal = 'daily_math_goal';
  static const String _keyWebDavConfigs = 'webdav_configs';
  static const String _keyMathBatchSize = 'math_batch_size';
  static const String _keyMathDifficulty = 'math_difficulty';
  static const String _keyMathPracticeMode = 'math_practice_mode';
  static const String _keyMathEntryKinds = 'math_entry_kinds';
  static const String _keyHasOnboarded = 'has_onboarded';
  static const String _keyTencentAsrCredentialFingerprint =
      'tencent_asr_credential_fingerprint';
  static const String _keyTencentAsrVerifiedAt = 'tencent_asr_verified_at';
  static const String _keyTtsCloudEnabled = 'tts_cloud_enabled';
  static const String _keyTtsCloudBaseUrl = 'tts_cloud_base_url';
  static const String _keyTtsCloudVoice = 'tts_cloud_voice';
  static const String _keyTtsCloudStyle = 'tts_cloud_style';
  static const String _keyWorkerTtsVerifiedFingerprint =
      'worker_tts_verified_fingerprint';
  static const String _keyLlmBaseUrl = 'llm_base_url';
  static const String _keyLlmModel = 'llm_model';
  static const String _keyLlmProviderName = 'llm_provider_name';
  // LLM 多厂商配置（设备绑定，不入备份白名单，见 backup_service.dart）：
  // llm_providers 含 baseUrl/model 指向外部服务，与 webdav_configs 同类；
  // llm_active_provider_id 依赖 llm_providers 存在，单独迁移无意义。
  static const String _keyLlmProviders = 'llm_providers';
  static const String _keyLlmActiveProviderId = 'llm_active_provider_id';
  // 场景级厂商绑定 key（见 LlmScenario.settingsKey，共 3 个）：
  // llm_provider_word_problem / llm_provider_poem_explain /
  // llm_provider_math_explain。值为 llm_providers 中某条配置的 id，
  // 与 llm_active_provider_id 同类（依赖本机配置列表存在，跨机迁移
  // 必然悬空），一律不入备份白名单。
  // AI 讲解 system prompt 用户自定义覆盖（string，入备份白名单——
  // 纯文本、非凭据、不指向外部服务，随备份迁移换机不丢）：
  // 空/缺失 = 用内置默认常量（core/prompts/explain_prompt_defaults.dart）；
  // 恢复默认 = 删除 key（不写常量副本，升级改进默认后自动享受新版）。
  static const String _keyPoemExplainPrompt = 'llm_poem_explain_prompt';
  static const String _keyMathExplainPrompt = 'llm_math_explain_prompt';
  static const String _keyAssistantPrompt = 'llm_assistant_prompt';
  // AI 助手悬浮球位置（设备绑定，不入备份白名单）：坐标随屏幕尺寸
  // 变化而失效，换机/旋转后由 _clampToBounds 越界回落兜底，跨设备
  // 迁移无意义（对照：assistant_enabled 是用户偏好，在白名单内）。
  static const String _keyAssistantBubbleDx = 'assistant_bubble_dx';
  static const String _keyAssistantBubbleDy = 'assistant_bubble_dy';
  // 本机与云端的同步时间线（设备绑定，不入备份白名单）：见 lastSyncedAt。
  static const String _keyLastSyncedAt = 'last_synced_at';

  Future<void> _putValidated(String key, Object value) async {
    if (!SettingsConstraints.accepts(key, value)) {
      throw ArgumentError.value(value, key, '设置值超出允许范围');
    }
    await HiveBoxes.settings.put(key, value);
  }

  String _boundedString(String key, String fallback) {
    final value = HiveBoxes.settings.get(key);
    return value is String && SettingsConstraints.accepts(key, value)
        ? value
        : fallback;
  }

  // ============ 主题 ============

  /// 当前活跃学科主题（'poem' 或 'math'），默认 'poem'。
  String get activeSubject => _boundedString(_keyActiveSubject, 'poem');

  Future<void> setActiveSubject(String subject) async {
    await _putValidated(_keyActiveSubject, subject);
  }

  String get themeMode => _boundedString(_keyThemeMode, 'system');

  Future<void> setThemeMode(String mode) async {
    await _putValidated(_keyThemeMode, mode);
  }

  // ============ 音效 ============

  bool get soundEnabled =>
      HiveBoxes.settings.get(_keySoundEnabled, defaultValue: true) as bool;

  Future<void> setSoundEnabled(bool enabled) async {
    await HiveBoxes.settings.put(_keySoundEnabled, enabled);
  }

  /// 用户偏好，随备份迁移；缺失或未知值回落默认，不在读取时写盘。
  CompletionSound get completionSound =>
      CompletionSound.fromId(
        HiveBoxes.settings.get(CompletionSound.settingsKey),
      ) ??
      CompletionSound.defaultSound;

  Future<void> setCompletionSound(CompletionSound sound) async {
    await _putValidated(CompletionSound.settingsKey, sound.id);
  }

  /// 旧安装保留经典音效；损坏值只读回落，不改写历史数据。
  AnswerFeedbackSound get answerFeedbackSound =>
      AnswerFeedbackSound.fromId(
        HiveBoxes.settings.get(AnswerFeedbackSound.settingsKey),
      ) ??
      AnswerFeedbackSound.defaultSound;

  Future<void> setAnswerFeedbackSound(AnswerFeedbackSound sound) async {
    await _putValidated(AnswerFeedbackSound.settingsKey, sound.id);
  }

  // ============ 触觉反馈 ============

  bool get hapticEnabled =>
      HiveBoxes.settings.get(_keyHapticEnabled, defaultValue: true) as bool;

  Future<void> setHapticEnabled(bool enabled) async {
    await HiveBoxes.settings.put(_keyHapticEnabled, enabled);
  }

  // ============ 选择的年级 ============

  int get selectedGrade => _boundedInt(_keySelectedGrade, 1);

  Future<void> setSelectedGrade(int grade) async {
    await _putValidated(_keySelectedGrade, grade);
  }

  String get selectedSemester => _boundedString(_keySelectedSemester, '上');

  Future<void> setLearningBackground(int grade, String semester) async {
    if (!SettingsConstraints.accepts(_keySelectedGrade, grade) ||
        !SettingsConstraints.accepts(_keySelectedSemester, semester)) {
      throw ArgumentError('请选择一至六年级及上、下学期');
    }
    await HiveBoxes.settings.putAll({
      _keySelectedGrade: grade,
      _keySelectedSemester: semester,
    });
  }

  // ============ 口算页一级入口 ============

  /// 口算页显示哪些一级练习入口。
  ///
  /// 缺省（无 key / 解析为空 / 校验不过）回落到 [kDefaultMathEntryKinds]
  /// 即四类全开 —— 与改造前"三个按钮恒定显示"的旧行为等价，旧数据升级
  /// 后无感知。校验不过的情况包括空串与连续逗号等脏数据。
  Set<MathEntryKind> get mathEntryKinds {
    final raw = HiveBoxes.settings.get(_keyMathEntryKinds);
    if (raw is! String ||
        !SettingsConstraints.accepts(_keyMathEntryKinds, raw)) {
      return kDefaultMathEntryKinds;
    }
    final parsed = parseMathEntryKinds(raw);
    return parsed.isEmpty ? kDefaultMathEntryKinds : parsed;
  }

  /// 保存口算页一级入口集合；空集合视为非法。
  ///
  /// 空集合会让口算页无任何入口，故与 [setLearningBackground] 同法在此
  /// 拒绝（UI 层已拦一道，此处是备份导入等旁路的兜底）。
  Future<void> setMathEntryKinds(Set<MathEntryKind> kinds) async {
    if (kinds.isEmpty) {
      throw ArgumentError.value(kinds, _keyMathEntryKinds, '至少保留一类练习');
    }
    await _putValidated(_keyMathEntryKinds, encodeMathEntryKinds(kinds));
  }

  // ============ TTS 语速 ============

  double get ttsSpeed {
    final value = HiveBoxes.settings.get(_keyTtsSpeed);
    return value is num && SettingsConstraints.accepts(_keyTtsSpeed, value)
        ? value.toDouble()
        : 0.5;
  }

  Future<void> setTtsSpeed(double speed) async {
    await _putValidated(_keyTtsSpeed, speed);
  }

  // ============ TTS 音色 ============

  /// 用户选择的 TTS 音色，返回 {"name": "...", "locale": "..."} 或 null（使用系统默认）。
  Map<String, String>? get ttsVoice {
    final json = HiveBoxes.settings.get(_keyTtsVoice) as String?;
    if (json == null || json.isEmpty) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  /// 保存用户选择的 TTS 音色。传 null 恢复系统默认。
  Future<void> setTtsVoice(Map<String, String>? voice) async {
    if (voice == null) {
      await HiveBoxes.settings.delete(_keyTtsVoice);
    } else {
      await HiveBoxes.settings.put(_keyTtsVoice, jsonEncode(voice));
    }
  }

  // ============ 自建 Worker 云端朗读（可选） ============

  /// 云端朗读开关，默认关闭；开启需自建服务已验证。
  bool get ttsCloudEnabled =>
      HiveBoxes.settings.get(_keyTtsCloudEnabled, defaultValue: false) as bool;

  Future<void> setTtsCloudEnabled(bool enabled) async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.put(_keyTtsCloudEnabled, enabled);
  }

  /// 云端朗读服务地址（Hive 非敏感存储），默认自建 Worker 地址。
  String get ttsCloudBaseUrl => HiveBoxes.settings.get(
        _keyTtsCloudBaseUrl,
        defaultValue: kDefaultWorkerBaseUrl,
      ) as String;

  Future<void> setTtsCloudBaseUrl(String baseUrl) async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.put(_keyTtsCloudBaseUrl, baseUrl);
  }

  /// 云端朗读音色（Worker shortName），默认晓晓。
  String get ttsCloudVoice => HiveBoxes.settings.get(
        _keyTtsCloudVoice,
        defaultValue: kDefaultWorkerVoice,
      ) as String;

  Future<void> setTtsCloudVoice(String voice) async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.put(_keyTtsCloudVoice, voice);
  }

  /// 云端朗读风格，默认诗词范读。
  String get ttsCloudStyle =>
      HiveBoxes.settings.get(_keyTtsCloudStyle, defaultValue: 'poetry-reading')
          as String;

  Future<void> setTtsCloudStyle(String style) async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.put(_keyTtsCloudStyle, style);
  }

  /// 读取自建服务完整配置；API Key 缺失时返回 null。
  Future<WorkerTtsConfig?> readWorkerTtsConfig() async {
    final apiKey = await _credentialStore.readWorkerTtsApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;
    final base = WorkerTtsClient.normalizeBaseUrl(ttsCloudBaseUrl);
    return WorkerTtsConfig(base: base, apiKey: apiKey);
  }

  /// 保存服务配置（地址入 Hive、Key 入安全存储）并清除验证指纹（强制重验）。
  Future<void> saveWorkerTtsConfig({
    required String baseUrl,
    required String apiKey,
  }) async {
    ParentAccessService.instance.assertAllowed();
    final normalized = WorkerTtsClient.normalizeBaseUrl(baseUrl);
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw ArgumentError('API Key 不能为空');
    }
    await _credentialStore.saveWorkerTtsApiKey(key);
    await setTtsCloudBaseUrl(normalized.toString());
    await HiveBoxes.settings.delete(_keyWorkerTtsVerifiedFingerprint);
  }

  /// 当前存储的配置是否已通过验证（指纹匹配）。
  Future<bool> isWorkerTtsVerified() async {
    final config = await readWorkerTtsConfig();
    if (config == null) return false;
    final stored =
        HiveBoxes.settings.get(_keyWorkerTtsVerifiedFingerprint) as String?;
    return stored == _workerTtsConfigFingerprint(config);
  }

  /// 标记当前配置已通过验证。
  Future<void> markWorkerTtsVerified() async {
    ParentAccessService.instance.assertAllowed();
    final config = await readWorkerTtsConfig();
    if (config == null) {
      throw StateError('尚未保存自建语音服务配置');
    }
    await HiveBoxes.settings.put(
      _keyWorkerTtsVerifiedFingerprint,
      _workerTtsConfigFingerprint(config),
    );
  }

  /// 删除已保存的服务配置（Key + 指纹），并关闭云端朗读开关。
  Future<void> deleteWorkerTtsConfig() async {
    ParentAccessService.instance.assertAllowed();
    await _credentialStore.deleteWorkerTtsApiKey();
    await HiveBoxes.settings.delete(_keyWorkerTtsVerifiedFingerprint);
    await HiveBoxes.settings.delete(_keyTtsCloudBaseUrl);
    await HiveBoxes.settings.delete(_keyTtsCloudVoice);
    await HiveBoxes.settings.delete(_keyTtsCloudStyle);
    await setTtsCloudEnabled(false);
  }

  static String _workerTtsConfigFingerprint(WorkerTtsConfig config) {
    final canonical = jsonEncode(<String>[
      config.base.toString(),
      config.apiKey,
    ]);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  // ============ LLM 应用题生成设置（可选，多厂商配置） ============

  /// 全部 LLM 厂商配置（Hive JSON 解码；无则空列表）。
  List<LlmProviderConfig> get llmProviders {
    final json = HiveBoxes.settings.get(_keyLlmProviders) as String?;
    return LlmProviderConfig.decodeList(json);
  }

  /// 当前生效配置 id；列表为空返回 null。
  ///
  /// getter 内自愈：active id 不在列表中时回落第一条并写回，
  /// 防手工删 Hive key 造成的悬空导致 UI 卡死。
  String? get llmActiveProviderId {
    final providers = llmProviders;
    if (providers.isEmpty) return null;
    final stored = HiveBoxes.settings.get(_keyLlmActiveProviderId) as String?;
    if (providers.any((p) => p.id == stored)) return stored;
    final fallback = providers.first.id;
    HiveBoxes.settings.put(_keyLlmActiveProviderId, fallback);
    return fallback;
  }

  /// 设置生效配置；id 不在列表中抛 [ArgumentError]。
  Future<void> setLlmActiveProvider(String id) async {
    ParentAccessService.instance.assertAllowed();
    final providers = llmProviders;
    if (!providers.any((p) => p.id == id)) {
      throw ArgumentError('LLM 配置不存在：$id');
    }
    await HiveBoxes.settings.put(_keyLlmActiveProviderId, id);
  }

  /// 读取 LLM 完整配置（应用题生成链路入口）：委托
  /// [readLlmConfigForScenario] 的 word_problem 场景，使出题场景
  /// 绑定生效。无绑定（或绑定悬空）时回落默认生效配置，与旧
  /// 「读 active」语义等价（迁移行为亦一致：两者先走
  /// [migrateLegacyLlmConfigIfNeeded]）。生效配置缺失（列表空/
  /// 字段空）返回 null（Key 允许为空，对应 Ollama 等无鉴权服务）。
  Future<LlmConfig?> readLlmConfig() {
    return readLlmConfigForScenario(LlmScenario.wordProblem);
  }

  /// 读取指定场景生效的 LLM 配置：
  /// 场景已绑定且绑定有效 → 用该配置；否则回落默认生效配置。
  ///
  /// 返回 null 的条件与 [readLlmConfig] 一致（无可用配置/字段为空）。
  Future<LlmConfig?> readLlmConfigForScenario(LlmScenario scenario) async {
    await migrateLegacyLlmConfigIfNeeded();
    final scenarioId = providerIdForScenario(scenario);
    final targetId = scenarioId ?? llmActiveProviderId;
    if (targetId == null) return null;
    // 仅当场景确有绑定配置时，场景选中 model 才适用（回落默认配置时忽略）。
    final modelOverride =
        scenarioId != null ? modelForScenario(scenario) : null;
    final primary = await _assembleLlmConfig(
      targetId,
      scenario: scenario,
      modelOverride: modelOverride,
    );
    if (primary == null) return null;
    final fallbacks = <LlmConfig>[];
    for (final provider in llmProviders) {
      if (provider.id == targetId) continue;
      try {
        final config =
            await _assembleLlmConfig(provider.id, scenario: scenario);
        if (config != null) fallbacks.add(config);
      } on Object {
        // 额外凭据不可读不能阻断原供应商；不泄漏平台异常中的凭据信息。
        AppLogger.e('读取备用 LLM 供应商配置失败', tag: 'LLM');
      }
    }
    return LlmConfig(
      baseUrl: primary.baseUrl,
      apiKey: primary.apiKey,
      model: primary.model,
      models: primary.models,
      selection: primary.selection,
      fallbacks: List.unmodifiable(fallbacks),
    );
  }

  /// 读取场景绑定的配置 id；未绑定或绑定已悬空（配置被删）返回 null。
  ///
  /// 读时不写回 Hive（与 [llmActiveProviderId] 的自愈策略不同）：
  /// 场景绑定缺省语义为「跟随默认」，悬空静默回落即可。
  String? providerIdForScenario(LlmScenario scenario) {
    final stored = HiveBoxes.settings.get(scenario.settingsKey);
    if (stored is! String || stored.isEmpty) return null;
    if (!llmProviders.any((p) => p.id == stored)) return null;
    return stored;
  }

  /// 设置场景绑定的配置 id；[id] 为 null 表示清除绑定（跟随默认）。
  ///
  /// id 不在配置列表中抛 [ArgumentError]（不落盘）。
  Future<void> setProviderIdForScenario(
    LlmScenario scenario,
    String? id,
  ) async {
    ParentAccessService.instance.assertAllowed();
    if (id == null) {
      await HiveBoxes.settings.delete(scenario.settingsKey);
      // 解绑同时清掉该场景选中的 model（旧 model 属于被解绑的配置）。
      await HiveBoxes.settings.delete(scenario.modelKey);
      return;
    }
    if (!llmProviders.any((p) => p.id == id)) {
      throw ArgumentError('LLM 配置不存在：$id');
    }
    await HiveBoxes.settings.put(scenario.settingsKey, id);
  }

  /// 场景选中的模型名；未选 / 空串读作 null（跟随该配置默认 model）。
  ///
  /// 读时不校验是否 ∈ 候选（校验在 [readLlmConfigForScenario] 组装处做，
  /// 悬空静默回落默认），与 [providerIdForScenario] 的读策略一致。
  String? modelForScenario(LlmScenario scenario) {
    final stored = HiveBoxes.settings.get(scenario.modelKey);
    if (stored is! String || stored.trim().isEmpty) return null;
    return stored;
  }

  /// 设置场景选中的模型；[model] 为 null / 空串表示清除（跟随默认）。
  Future<void> setModelForScenario(LlmScenario scenario, String? model) async {
    ParentAccessService.instance.assertAllowed();
    final trimmed = model?.trim() ?? '';
    if (trimmed.isEmpty) {
      await HiveBoxes.settings.delete(scenario.modelKey);
      return;
    }
    await HiveBoxes.settings.put(scenario.modelKey, trimmed);
  }

  /// 一次设定场景的（配置, 模型）绑定（助手切换器 / 场景设置页用）。
  /// [providerId] 为 null 清除绑定（连带清 model）；非 null 时 id 须存在。
  Future<void> setScenarioSelection(
    LlmScenario scenario, {
    required String? providerId,
    required String? model,
  }) async {
    ParentAccessService.instance.assertAllowed();
    await setProviderIdForScenario(scenario, providerId);
    if (providerId != null) {
      await setModelForScenario(scenario, model);
    }
  }

  /// 按配置 id 组装 [LlmConfig]（[readLlmConfig] 与
  /// [readLlmConfigForScenario] 共用尾段）。
  ///
  /// 配置不存在或 baseUrl/model 为空返回 null；Key 允许为空。
  Future<LlmConfig?> _assembleLlmConfig(
    String id, {
    required LlmScenario scenario,
    String? modelOverride,
  }) async {
    final providers = llmProviders;
    if (!providers.any((p) => p.id == id)) return null;
    final target = providers.firstWhere((p) => p.id == id);
    final base = target.baseUrl.trim();
    // 覆盖 model 须 ∈ 该配置候选模型，否则回落默认 model（防删/改名悬空）。
    final model =
        (modelOverride != null && target.models.contains(modelOverride))
            ? modelOverride.trim()
            : target.model.trim();
    if (base.isEmpty || model.isEmpty) return null;
    final snapshot = LlmSelectionSnapshot(
      providerId: id,
      scenario: scenario,
      defaultModel: target.model,
      models: target.models,
      boundProviderId: providerIdForScenario(scenario),
      selectedModel: modelForScenario(scenario),
      providerVersion: _llmProviderVersions[id] ?? 0,
    );
    final apiKey = await _credentialStore.readLlmApiKeyFor(id);
    return LlmConfig(
      baseUrl: base,
      apiKey: apiKey ?? '',
      model: model,
      models: snapshot.models,
      selection: snapshot,
    );
  }

  /// 兼容同供应商的候选模型恢复。
  /// 手动编辑 API 仍需家长解锁；这个受限恢复操作可以在锁定时执行。
  Future<bool> promoteSuccessfulLlmModel(
    LlmConfig request,
    String model, {
    required bool Function() isActive,
  }) =>
      promoteSuccessfulLlmSelection(
        request,
        request.withModel(model),
        isActive: isActive,
      );

  /// 仅在请求捕获的已配置供应商/候选内恢复，不改地址或凭据。
  Future<bool> promoteSuccessfulLlmSelection(
    LlmConfig request,
    LlmConfig successful, {
    required bool Function() isActive,
  }) async {
    final source = request.selection;
    final target = successful.selection;
    if (source == null || target == null || !isActive()) return false;
    final approved = [request, ...request.fallbacks].where(
      (candidate) => candidate.selection?.providerId == target.providerId,
    );
    if (approved.isEmpty) return false;
    final candidate = approved.first;
    final model = successful.model;
    final switchedProvider = target.providerId != source.providerId;
    if ((!switchedProvider && model == request.model) ||
        !candidate.candidateModels.contains(model) ||
        successful.baseUrl != candidate.baseUrl ||
        successful.apiKey != candidate.apiKey) {
      return false;
    }
    for (final config in {request, candidate}) {
      final key =
          await _credentialStore.readLlmApiKeyFor(config.selection!.providerId);
      if (!isActive() || (key ?? '') != config.apiKey) return false;
    }
    // 最后一个 await 后重新读全部配置；检查到写入之间没有异步窗口。
    final providers = llmProviders;
    bool unchanged(LlmConfig config) {
      final snapshot = config.selection!;
      if ((_llmProviderVersions[snapshot.providerId] ?? 0) !=
          snapshot.providerVersion) {
        return false;
      }
      final matches = providers.where((p) => p.id == snapshot.providerId);
      if (matches.isEmpty) return false;
      final current = matches.first;
      return current.baseUrl.trim() == config.baseUrl &&
          current.model == snapshot.defaultModel &&
          current.models.length == snapshot.models.length &&
          current.models.indexed
              .every((entry) => entry.$2 == snapshot.models[entry.$1]);
    }

    if (!unchanged(request) ||
        !unchanged(candidate) ||
        providerIdForScenario(source.scenario) != source.boundProviderId ||
        modelForScenario(source.scenario) != source.selectedModel ||
        (source.boundProviderId == null &&
            llmActiveProviderId != source.providerId)) {
      return false;
    }
    final index = providers.indexWhere((p) => p.id == target.providerId);
    final current = providers[index];
    providers[index] = LlmProviderConfig(
      id: current.id,
      name: current.name,
      baseUrl: current.baseUrl,
      model: model,
      models: LlmProviderConfig.normalizeModels(current.models, model),
    );
    await HiveBoxes.settings.putAll({
      _keyLlmProviders: LlmProviderConfig.encodeList(providers),
      if (switchedProvider && source.boundProviderId == null)
        _keyLlmActiveProviderId: target.providerId,
      if (switchedProvider && source.boundProviderId != null)
        source.scenario.settingsKey: target.providerId,
      if (source.boundProviderId != null &&
          (switchedProvider || source.selectedModel != null))
        source.scenario.modelKey: model,
    });
    return true;
  }

  /// 保存（新增或更新）一条 LLM 厂商配置。
  ///
  /// - baseUrl 先经 [LlmClient.normalizeBaseUrl] 校验（非法抛
  ///   [FormatException]，不落盘）；
  /// - apiKey 空串 = 保留该配置旧 Key；非空写入 `llm_api_key_{id}`；
  /// - 追加且当前无 active（或 active 已失效）时自动设为生效。
  Future<void> saveLlmProviderConfig({
    required String id,
    required String name,
    required String baseUrl,
    required String model,
    required String apiKey,
    List<String> models = const <String>[],
  }) async {
    ParentAccessService.instance.assertAllowed();
    // 先校验地址合法（非法抛 FormatException，不落盘）。
    final normalized = LlmClient.normalizeBaseUrl(baseUrl);
    _markLlmProviderWrite(id);
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      await _credentialStore.saveLlmApiKeyFor(id, key);
    }

    final list = llmProviders;
    final config = LlmProviderConfig(
      id: id,
      name: name.trim(),
      baseUrl: normalized.toString(),
      model: model.trim(),
      models: LlmProviderConfig.normalizeModels(models, model.trim()),
    );
    final index = list.indexWhere((c) => c.id == id);
    if (index >= 0) {
      list[index] = config;
    } else {
      list.add(config);
    }
    await HiveBoxes.settings.put(
      _keyLlmProviders,
      LlmProviderConfig.encodeList(list),
    );
    // 追加且无有效 active 时自动设为生效。
    //
    // 读「原始存储值」而非 llmActiveProviderId getter：getter 自带
    // 回落写回的自愈副作用（列表非空时永不返回 null），用它判断会让
    // 本分支语义隐性且条件不可达。
    if (index < 0) {
      final storedActive =
          HiveBoxes.settings.get(_keyLlmActiveProviderId) as String?;
      final hasValidActive =
          storedActive != null && list.any((c) => c.id == storedActive);
      if (!hasValidActive) {
        await HiveBoxes.settings.put(_keyLlmActiveProviderId, id);
      }
    }
  }

  /// 删除一条 LLM 厂商配置及其安全存储 Key。
  ///
  /// 若删除的是生效配置，active 自动切到剩余第一条；无剩余清空 active。
  /// 指向被删配置的场景绑定一并清理（防悬空残留）。
  Future<void> deleteLlmProviderConfig(String id) async {
    ParentAccessService.instance.assertAllowed();
    _markLlmProviderWrite(id);
    await _credentialStore.deleteLlmApiKeyFor(id);
    // 先按原始存储值清理场景绑定（列表写回后无法再判断悬空归属）。
    for (final scenario in LlmScenario.values) {
      if (HiveBoxes.settings.get(scenario.settingsKey) == id) {
        await HiveBoxes.settings.delete(scenario.settingsKey);
        // 绑定被删，该场景选中的 model 一并清掉（属于被删配置）。
        await HiveBoxes.settings.delete(scenario.modelKey);
      }
    }
    final list = llmProviders..removeWhere((c) => c.id == id);
    await HiveBoxes.settings.put(
      _keyLlmProviders,
      LlmProviderConfig.encodeList(list),
    );
    if (list.isEmpty) {
      await HiveBoxes.settings.delete(_keyLlmActiveProviderId);
      return;
    }
    final activeId = llmActiveProviderId;
    if (activeId == null ||
        activeId == id ||
        !list.any((c) => c.id == activeId)) {
      await HiveBoxes.settings.put(
        _keyLlmActiveProviderId,
        list.first.id,
      );
    }
  }

  /// 读取指定配置的已存 Key（页面回退判断用）。
  Future<String?> readLlmApiKeyFor(String id) {
    return _credentialStore.readLlmApiKeyFor(id);
  }

  /// 清除指定配置已保存的 API Key（如从有鉴权服务切到无鉴权服务）；
  /// 不触碰配置本身。无已存 Key 时调用无副作用。
  Future<void> clearLlmApiKey(String id) {
    ParentAccessService.instance.assertAllowed();
    _markLlmProviderWrite(id);
    return _credentialStore.deleteLlmApiKeyFor(id);
  }

  /// 旧单配置（llm_base_url/llm_model/llm_provider_name + llm_api_key）
  /// → 多配置迁移（幂等）：
  ///
  /// llm_providers 为空 && llm_base_url 非空 → 生成 id、复制
  /// llm_api_key → `llm_api_key_{id}`、删旧 llm_api_key、删旧三 key、
  /// active 指向新配置。
  ///
  /// readLlmConfig 与设置页 initState 均调用。并发调用由实例级
  /// in-flight Future 去重（幂等检查存在 await 窗口，两场景并发首启
  /// 若各自完整跑一遍会双写：第二份配置覆盖第一份、第一份的
  /// `llm_api_key_{id}` 泄留安全存储成为孤儿 Key）。
  Future<void> migrateLegacyLlmConfigIfNeeded() {
    final inFlight = _legacyMigrationInFlight;
    if (inFlight != null) return inFlight;
    return _legacyMigrationInFlight = _doMigrateLegacyLlmConfig()
        .whenComplete(() => _legacyMigrationInFlight = null);
  }

  Future<void> _doMigrateLegacyLlmConfig() async {
    final providers = llmProviders;
    final legacyBase =
        HiveBoxes.settings.get(_keyLlmBaseUrl, defaultValue: '') as String;
    if (providers.isNotEmpty || legacyBase.trim().isEmpty) return;

    final id = LlmProviderConfig.generateId();
    // 旧 Key 复制到新键位；旧单 Key（无 Key 服务）允许为空。
    final legacyKey = await _credentialStore.readLlmApiKey();
    if (legacyKey != null && legacyKey.isNotEmpty) {
      await _credentialStore.saveLlmApiKeyFor(id, legacyKey);
      await _credentialStore.deleteLlmApiKey();
    }
    final config = LlmProviderConfig(
      id: id,
      name: HiveBoxes.settings.get(_keyLlmProviderName, defaultValue: '')
          as String,
      baseUrl: legacyBase.trim(),
      model: HiveBoxes.settings.get(_keyLlmModel, defaultValue: '') as String,
    );
    await HiveBoxes.settings.put(
      _keyLlmProviders,
      LlmProviderConfig.encodeList([config]),
    );
    await HiveBoxes.settings.put(_keyLlmActiveProviderId, id);
    await HiveBoxes.settings.delete(_keyLlmBaseUrl);
    await HiveBoxes.settings.delete(_keyLlmModel);
    await HiveBoxes.settings.delete(_keyLlmProviderName);
  }

  // ============ AI 讲解提示词（可编辑，覆盖 ?? 内置默认） ============

  /// 诗词讲解 system prompt 用户覆盖值；null = 未自定义（用内置默认）。
  /// 空串/空白串防御性读作 null（历史脏数据不留隐患）。
  String? get poemExplainPromptOverride {
    final raw = HiveBoxes.settings.get(_keyPoemExplainPrompt) as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  /// 保存诗词讲解覆盖值；[value] trim 后为空 → 删除 key（恢复默认）。
  Future<void> setPoemExplainPrompt(String value) async {
    ParentAccessService.instance.assertAllowed();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await HiveBoxes.settings.delete(_keyPoemExplainPrompt);
      return;
    }
    await HiveBoxes.settings.put(_keyPoemExplainPrompt, trimmed);
  }

  /// 一键恢复内置默认：删除覆盖 key，运行时回落编译期常量。
  Future<void> resetPoemExplainPrompt() async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.delete(_keyPoemExplainPrompt);
  }

  /// 口算解析 system prompt 用户覆盖值；null = 未自定义（用内置默认）。
  String? get mathExplainPromptOverride {
    final raw = HiveBoxes.settings.get(_keyMathExplainPrompt) as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  /// 保存口算解析覆盖值；[value] trim 后为空 → 删除 key（恢复默认）。
  Future<void> setMathExplainPrompt(String value) async {
    ParentAccessService.instance.assertAllowed();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await HiveBoxes.settings.delete(_keyMathExplainPrompt);
      return;
    }
    await HiveBoxes.settings.put(_keyMathExplainPrompt, trimmed);
  }

  /// 一键恢复内置默认：删除覆盖 key，运行时回落编译期常量。
  Future<void> resetMathExplainPrompt() async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.delete(_keyMathExplainPrompt);
  }

  /// AI 助手 system prompt 用户覆盖值；null = 未自定义（用内置默认）。
  String? get assistantPromptOverride {
    final raw = HiveBoxes.settings.get(_keyAssistantPrompt) as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  /// 保存 AI 助手覆盖值；[value] trim 后为空 → 删除 key（恢复默认）。
  Future<void> setAssistantPrompt(String value) async {
    ParentAccessService.instance.assertAllowed();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await HiveBoxes.settings.delete(_keyAssistantPrompt);
      return;
    }
    await HiveBoxes.settings.put(_keyAssistantPrompt, trimmed);
  }

  /// 一键恢复内置默认：删除覆盖 key，运行时回落编译期常量。
  Future<void> resetAssistantPrompt() async {
    ParentAccessService.instance.assertAllowed();
    await HiveBoxes.settings.delete(_keyAssistantPrompt);
  }

  // ============ 每日目标 ============

  /// 每日诗词背诵目标（默认 1 首）
  int get dailyPoemGoal => _boundedInt(_keyDailyPoemGoal, 1);

  Future<void> setDailyPoemGoal(int count) async {
    await _putValidated(_keyDailyPoemGoal, count);
  }

  /// 每日口算做题目标（默认 10 题）
  int get dailyMathGoal => _boundedInt(_keyDailyMathGoal, 10);

  Future<void> setDailyMathGoal(int count) async {
    await _putValidated(_keyDailyMathGoal, count);
  }

  // ============ 口算练习设置 ============

  /// 每组题目数量（默认 10 题）
  int get mathBatchSize => _boundedInt(_keyMathBatchSize, 10);

  Future<void> setMathBatchSize(int count) async {
    await _putValidated(_keyMathBatchSize, count);
  }

  /// 口算难度（默认 'medium'）
  String get mathDifficulty => _boundedString(_keyMathDifficulty, 'medium');

  Future<void> setMathDifficulty(String difficulty) async {
    await _putValidated(_keyMathDifficulty, difficulty);
  }

  /// 口算练习模式（null = 综合，否则为 ProblemMode.name）
  String? get mathPracticeMode {
    final value = HiveBoxes.settings.get(_keyMathPracticeMode);
    return value is String &&
            SettingsConstraints.accepts(_keyMathPracticeMode, value)
        ? value
        : null;
  }

  Future<void> setMathPracticeMode(String? mode) async {
    if (mode == null) {
      await HiveBoxes.settings.delete(_keyMathPracticeMode);
    } else {
      await _putValidated(_keyMathPracticeMode, mode);
    }
  }

  // ============ 云端同步时间线（设备绑定，不入备份白名单） ============

  /// 本机最后一次成功上传/下载云端备份的时刻；null = 从未同步过。
  ///
  /// 用途：跨设备冲突检测。云端备份顶层带 `exportedAt`（导出时刻），若它
  /// **晚于**本机上次同步时刻，说明另一台设备在本机之后又写过云端，直接
  /// 覆盖会让对方的数据消失 —— 此时先提醒用户。
  ///
  /// 刻意**不**进 `_settingsValueType` 白名单：它是「本机与云端的相对时间线」，
  /// 随备份迁到另一台设备会继承一台机器的时点，反而制造误报（对照：
  /// assistant_bubble_dx 同属设备绑定）。用测试锁定导出 JSON 不含该 key。
  DateTime? get lastSyncedAt {
    final raw = HiveBoxes.settings.get(_keyLastSyncedAt) as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLastSyncedAt(DateTime value) async {
    await HiveBoxes.settings.put(
      _keyLastSyncedAt,
      value.toIso8601String(),
    );
  }

  // ============ AI 助手悬浮球位置（设备绑定，不入备份白名单） ============

  /// 悬浮球上次停留位置 x（body 坐标系逻辑像素）；null = 未存过（默认角）。
  double? get assistantBubbleDx =>
      (HiveBoxes.settings.get(_keyAssistantBubbleDx) as num?)?.toDouble();

  Future<void> setAssistantBubbleDx(double dx) async {
    await HiveBoxes.settings.put(_keyAssistantBubbleDx, dx);
  }

  /// 悬浮球上次停留位置 y（body 坐标系逻辑像素）；null = 未存过（默认角）。
  double? get assistantBubbleDy =>
      (HiveBoxes.settings.get(_keyAssistantBubbleDy) as num?)?.toDouble();

  Future<void> setAssistantBubbleDy(double dy) async {
    await HiveBoxes.settings.put(_keyAssistantBubbleDy, dy);
  }

  // ============ 新手引导 ============

  /// 用户是否已完成新手引导。
  bool get hasOnboarded =>
      HiveBoxes.settings.get(_keyHasOnboarded, defaultValue: false) as bool;

  Future<void> setHasOnboarded(bool value) async {
    await HiveBoxes.settings.put(_keyHasOnboarded, value);
  }

  // ============ 语音识别设置 ============

  DateTime? get tencentAsrVerifiedAt {
    final value = HiveBoxes.settings.get(_keyTencentAsrVerifiedAt);
    if (value is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<TencentAsrCredentials?> readTencentAsrCredentials() {
    return _credentialStore.readTencentAsrCredentials();
  }

  Future<SpeechRecognitionSettingsSnapshot>
      loadSpeechRecognitionSettingsSnapshot() async {
    final credentials = await readTencentAsrCredentials();
    final settings = await _resolveSpeechRecognitionSettings(credentials);
    return SpeechRecognitionSettingsSnapshot(
      credentials: credentials,
      settings: settings,
    );
  }

  Future<SpeechRecognitionSettingsState> loadSpeechRecognitionSettings() async {
    final snapshot = await loadSpeechRecognitionSettingsSnapshot();
    return snapshot.settings;
  }

  Future<SpeechRecognitionSettingsState> _resolveSpeechRecognitionSettings(
    TencentAsrCredentials? credentials,
  ) async {
    final storedFingerprint =
        HiveBoxes.settings.get(_keyTencentAsrCredentialFingerprint) as String?;
    final verifiedAt = tencentAsrVerifiedAt;
    final isVerified = credentials != null &&
        storedFingerprint == _credentialFingerprint(credentials) &&
        verifiedAt != null;

    return SpeechRecognitionSettingsState(
      hasCredentials: credentials != null,
      isVerified: isVerified,
      verifiedAt: isVerified ? verifiedAt : null,
    );
  }

  Future<void> saveTencentAsrCredentials({
    required String secretId,
    required String secretKey,
  }) async {
    ParentAccessService.instance.assertAllowed();
    final credentials = TencentAsrCredentials(
      secretId: secretId.trim(),
      secretKey: secretKey.trim(),
    );
    if (!credentials.isComplete) {
      throw ArgumentError('SecretId 和 SecretKey 不能为空');
    }

    final existing = await readTencentAsrCredentials();
    final changed = existing == null ||
        _credentialFingerprint(existing) != _credentialFingerprint(credentials);
    if (changed) {
      await invalidateTencentAsrVerification();
    }
    await _credentialStore.saveTencentAsrCredentials(credentials);
  }

  Future<void> markTencentAsrCredentialsVerified({
    required TencentAsrCredentials testedCredentials,
    DateTime? verifiedAt,
  }) async {
    ParentAccessService.instance.assertAllowed();
    final current = await readTencentAsrCredentials();
    if (current == null ||
        _credentialFingerprint(current) !=
            _credentialFingerprint(testedCredentials)) {
      await invalidateTencentAsrVerification();
      throw StateError('腾讯云密钥已发生变化，请重新测试');
    }

    await HiveBoxes.settings.put(
      _keyTencentAsrCredentialFingerprint,
      _credentialFingerprint(current),
    );
    await HiveBoxes.settings.put(
      _keyTencentAsrVerifiedAt,
      (verifiedAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  Future<void> invalidateTencentAsrVerification() async {
    await HiveBoxes.settings.delete(_keyTencentAsrCredentialFingerprint);
    await HiveBoxes.settings.delete(_keyTencentAsrVerifiedAt);
  }

  Future<void> deleteTencentAsrCredentials() async {
    ParentAccessService.instance.assertAllowed();
    await invalidateTencentAsrVerification();
    await _credentialStore.deleteTencentAsrCredentials();
  }

  static String _credentialFingerprint(TencentAsrCredentials credentials) {
    final canonical = jsonEncode(<String>[
      credentials.secretId,
      credentials.secretKey,
    ]);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  // ============ WebDAV 配置（移至底部） ============

  final SecureCredentialStore _credentialStore;

  /// 所有 WebDAV 同步配置（不含凭据，仅用于列表展示）。
  List<WebDavConfig> get webDavConfigs => webDavConfigsDetailed.configs;

  /// 所有 WebDAV 同步配置 + 因不合法被忽略的条数（供列表页提示）。
  ///
  /// `skipped` 只统计逐条非法的条目；整串 JSON 损坏时记 0（按「无配置」
  /// 处理，那是存储项损坏而非「有 N 条不合法」）。凭据为空**不**算非法，
  /// 详见 `WebDavConfig.tryCreate`。
  ({List<WebDavConfig> configs, int skipped}) get webDavConfigsDetailed {
    final json = HiveBoxes.settings.get(_keyWebDavConfigs) as String?;
    final result = WebDavConfig.decodeListDetailed(json);
    return (configs: result.configs, skipped: result.skipped);
  }

  /// 配置列表的**可变副本**，供 `saveWebDavConfig` / `deleteWebDavConfig`
  /// 就地增删改。
  ///
  /// 不能直接改 [webDavConfigs] 的返回值：那来自 `decodeListDetailed` 内部的
  /// 累加列表，且 `const WebDavConfigDecodeResult([], 0)` 在「无配置」时返回的
  /// 是**编译期常量空列表**，对它 `add` 会抛
  /// `Unsupported operation: Cannot add to an unmodifiable list`。
  /// 也就是说，「保存第一条配置」这条路径此前必然崩溃。
  List<WebDavConfig> _mutableConfigs() => List<WebDavConfig>.of(webDavConfigs);

  /// 一次性迁移：把 Hive 中仍带明文凭据的配置搬进安全存储并置空。
  ///
  /// 启动时对所有配置跑一遍（`saveWebDavConfig` 只覆盖此后写入的配置，
  /// 历史版本留下的明文凭据需要这里兜底）。
  ///
  /// **顺序必须是「先写安全存储成功，再清 Hive」**：任一条写失败就保留该条
  /// 原值（明文留在 Hive 里仍可被读取，比直接丢失凭据安全），并只记日志、
  /// 不中断整批迁移。写失败时不落盘，因此 `changed` 为 false 时 Hive 不变。
  Future<void> migratePlaintextWebDavCredentials() async {
    final raw = HiveBoxes.settings.get(_keyWebDavConfigs) as String?;
    final result = WebDavConfig.decodeListDetailed(raw);
    if (result.configs.isEmpty) return;

    var changed = false;
    final cleaned = <WebDavConfig>[];
    for (final config in result.configs) {
      if (config.username.isEmpty && config.password.isEmpty) {
        cleaned.add(config);
        continue;
      }
      try {
        await _credentialStore.saveWebDavCredentials(
          configId: config.id,
          username: config.username,
          password: config.password,
        );
        // 安全存储写入成功后，才在 Hive 副本中置空凭据。
        cleaned.add(
          WebDavConfig(
            id: config.id,
            name: config.name,
            url: config.url,
            username: '',
            password: '',
            remotePath: config.remotePath,
          ),
        );
        changed = true;
      } on Object catch (error) {
        AppLogger.e(
          'WebDAV 凭据迁移失败，保留 Hive 原值',
          tag: 'Startup',
          error: error,
        );
        cleaned.add(config);
      }
    }
    if (changed) await _saveConfigsToHive(cleaned);
  }

  /// 加载完整的 WebDAV 配置（含凭据）。
  ///
  /// 若安全存储中无凭据，尝试从 Hive 迁移旧明文凭据。
  Future<WebDavConfig> loadWebDavConfigWithCredentials(
    WebDavConfig config,
  ) async {
    // 先尝试从安全存储读取
    final creds = await _credentialStore.readWebDavCredentials(config.id);
    if (creds != null) {
      return WebDavConfig(
        id: config.id,
        name: config.name,
        url: config.url,
        username: creds.username,
        password: creds.password,
        remotePath: config.remotePath,
      );
    }

    // 安全存储无数据，检查 Hive 中是否有旧明文凭据（迁移）
    if (config.username.isNotEmpty && config.password.isNotEmpty) {
      await _credentialStore.saveWebDavCredentials(
        configId: config.id,
        username: config.username,
        password: config.password,
      );
      // 清除 Hive 中的明文凭据
      await _saveConfigsToHive(
        webDavConfigs.map((c) {
          return WebDavConfig(
            id: c.id,
            name: c.name,
            url: c.url,
            username: '',
            password: '',
            remotePath: c.remotePath,
          );
        }).toList(),
      );
      return config; // 原始 config 已含凭据
    }

    return config;
  }

  /// 保存（新增或更新）一条 WebDAV 配置。
  ///
  /// 凭据存入安全存储，非敏感信息存入 Hive。
  Future<void> saveWebDavConfig(WebDavConfig config) async {
    ParentAccessService.instance.assertAllowed();
    // 凭据 → 安全存储
    await _credentialStore.saveWebDavCredentials(
      configId: config.id,
      username: config.username,
      password: config.password,
    );

    // 非敏感信息 → Hive（凭据字段**刻意**置空）。
    //
    // 凭据不落盘是本模块的设计不变量：Hive 中的配置形状永远不含凭据，读取
    // 时由 loadWebDavConfigWithCredentials 从安全存储重新注入。不要「优化」
    // 成把 config 原样写入（例如复用同一个对象、或补上 username/password），
    // 那会让明文密码永久留在未加密的 settings box 里。
    final stripped = WebDavConfig(
      id: config.id,
      name: config.name,
      url: config.url,
      username: '',
      password: '',
      remotePath: config.remotePath,
    );
    final list = _mutableConfigs();
    final index = list.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      list[index] = stripped;
    } else {
      list.add(stripped);
    }
    await _saveConfigsToHive(list);
  }

  /// 删除一条 WebDAV 配置。
  Future<void> deleteWebDavConfig(String id) async {
    ParentAccessService.instance.assertAllowed();
    await _credentialStore.deleteWebDavCredentials(id);
    final list = _mutableConfigs()..removeWhere((c) => c.id == id);
    await _saveConfigsToHive(list);
  }

  Future<void> _saveConfigsToHive(List<WebDavConfig> configs) async {
    await HiveBoxes.settings.put(
      _keyWebDavConfigs,
      WebDavConfig.encodeList(configs),
    );
  }
}
