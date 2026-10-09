// lib/data/repositories/settings_repository.dart
//
// 层级：data/repositories
// 职责：应用设置仓储。使用 settingsBox 作为 KV 存储。

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/models/webdav_config.dart';

class SettingsRepository {
  SettingsRepository({SecureCredentialStore? credentialStore})
      : _credentialStore = credentialStore ?? SecureCredentialStore();
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
  static const String _keyTtsSpeed = 'tts_speed';
  static const String _keyTtsVoice =
      'tts_voice'; // JSON: {"name":"...", "locale":"..."}
  static const String _keyPinyinVisible = 'pinyin_visible';
  static const String _keyDailyPoemGoal = 'daily_poem_goal';
  static const String _keyDailyMathGoal = 'daily_math_goal';
  static const String _keyWebDavConfigs = 'webdav_configs';
  static const String _keyMathBatchSize = 'math_batch_size';
  static const String _keyMathDifficulty = 'math_difficulty';
  static const String _keyMathPracticeMode = 'math_practice_mode';
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

  // ============ 主题 ============

  /// 当前活跃学科主题（'poem' 或 'math'），默认 'poem'。
  String get activeSubject =>
      HiveBoxes.settings.get(_keyActiveSubject, defaultValue: 'poem') as String;

  Future<void> setActiveSubject(String subject) async {
    await HiveBoxes.settings.put(_keyActiveSubject, subject);
  }

  String get themeMode =>
      HiveBoxes.settings.get(_keyThemeMode, defaultValue: 'system') as String;

  Future<void> setThemeMode(String mode) async {
    await HiveBoxes.settings.put(_keyThemeMode, mode);
  }

  // ============ 音效 ============

  bool get soundEnabled =>
      HiveBoxes.settings.get(_keySoundEnabled, defaultValue: true) as bool;

  Future<void> setSoundEnabled(bool enabled) async {
    await HiveBoxes.settings.put(_keySoundEnabled, enabled);
  }

  // ============ 触觉反馈 ============

  bool get hapticEnabled =>
      HiveBoxes.settings.get(_keyHapticEnabled, defaultValue: true) as bool;

  Future<void> setHapticEnabled(bool enabled) async {
    await HiveBoxes.settings.put(_keyHapticEnabled, enabled);
  }

  // ============ 选择的年级 ============

  int get selectedGrade =>
      HiveBoxes.settings.get(_keySelectedGrade, defaultValue: 1) as int;

  Future<void> setSelectedGrade(int grade) async {
    await HiveBoxes.settings.put(_keySelectedGrade, grade);
  }

  // ============ TTS 语速 ============

  double get ttsSpeed =>
      HiveBoxes.settings.get(_keyTtsSpeed, defaultValue: 0.5) as double;

  Future<void> setTtsSpeed(double speed) async {
    await HiveBoxes.settings.put(_keyTtsSpeed, speed);
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
    await HiveBoxes.settings.put(_keyTtsCloudEnabled, enabled);
  }

  /// 云端朗读服务地址（Hive 非敏感存储），默认自建 Worker 地址。
  String get ttsCloudBaseUrl => HiveBoxes.settings.get(
        _keyTtsCloudBaseUrl,
        defaultValue: kDefaultWorkerBaseUrl,
      ) as String;

  Future<void> setTtsCloudBaseUrl(String baseUrl) async {
    await HiveBoxes.settings.put(_keyTtsCloudBaseUrl, baseUrl);
  }

  /// 云端朗读音色（Worker shortName），默认晓晓。
  String get ttsCloudVoice => HiveBoxes.settings.get(
        _keyTtsCloudVoice,
        defaultValue: kDefaultWorkerVoice,
      ) as String;

  Future<void> setTtsCloudVoice(String voice) async {
    await HiveBoxes.settings.put(_keyTtsCloudVoice, voice);
  }

  /// 云端朗读风格，默认诗词范读。
  String get ttsCloudStyle =>
      HiveBoxes.settings.get(_keyTtsCloudStyle, defaultValue: 'poetry-reading')
          as String;

  Future<void> setTtsCloudStyle(String style) async {
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
    final stored =
        HiveBoxes.settings.get(_keyLlmActiveProviderId) as String?;
    if (providers.any((p) => p.id == stored)) return stored;
    final fallback = providers.first.id;
    HiveBoxes.settings.put(_keyLlmActiveProviderId, fallback);
    return fallback;
  }

  /// 设置生效配置；id 不在列表中抛 [ArgumentError]。
  Future<void> setLlmActiveProvider(String id) async {
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
    return _assembleLlmConfig(targetId);
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
    if (id == null) {
      await HiveBoxes.settings.delete(scenario.settingsKey);
      return;
    }
    if (!llmProviders.any((p) => p.id == id)) {
      throw ArgumentError('LLM 配置不存在：$id');
    }
    await HiveBoxes.settings.put(scenario.settingsKey, id);
  }

  /// 按配置 id 组装 [LlmConfig]（[readLlmConfig] 与
  /// [readLlmConfigForScenario] 共用尾段）。
  ///
  /// 配置不存在或 baseUrl/model 为空返回 null；Key 允许为空。
  Future<LlmConfig?> _assembleLlmConfig(String id) async {
    final providers = llmProviders;
    if (!providers.any((p) => p.id == id)) return null;
    final target = providers.firstWhere((p) => p.id == id);
    final base = target.baseUrl.trim();
    final model = target.model.trim();
    if (base.isEmpty || model.isEmpty) return null;
    final apiKey = await _credentialStore.readLlmApiKeyFor(id);
    return LlmConfig(baseUrl: base, apiKey: apiKey ?? '', model: model);
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
  }) async {
    // 先校验地址合法（非法抛 FormatException，不落盘）。
    final normalized = LlmClient.normalizeBaseUrl(baseUrl);
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
    if (index < 0) {
      final activeId = llmActiveProviderId;
      if (activeId == null || activeId != id && !llmProviders.any(
            (p) => p.id == activeId,
          )) {
        await HiveBoxes.settings.put(_keyLlmActiveProviderId, id);
      }
    }
  }

  /// 删除一条 LLM 厂商配置及其安全存储 Key。
  ///
  /// 若删除的是生效配置，active 自动切到剩余第一条；无剩余清空 active。
  /// 指向被删配置的场景绑定一并清理（防悬空残留）。
  Future<void> deleteLlmProviderConfig(String id) async {
    await _credentialStore.deleteLlmApiKeyFor(id);
    // 先按原始存储值清理场景绑定（列表写回后无法再判断悬空归属）。
    for (final scenario in LlmScenario.values) {
      if (HiveBoxes.settings.get(scenario.settingsKey) == id) {
        await HiveBoxes.settings.delete(scenario.settingsKey);
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
    if (activeId == null || activeId == id || !list.any((c) => c.id == activeId)) {
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

  /// 旧单配置（llm_base_url/llm_model/llm_provider_name + llm_api_key）
  /// → 多配置迁移（幂等）：
  ///
  /// llm_providers 为空 && llm_base_url 非空 → 生成 id、复制
  /// llm_api_key → `llm_api_key_{id}`、删旧 llm_api_key、删旧三 key、
  /// active 指向新配置。
  ///
  /// readLlmConfig 与设置页 initState 均调用（幂等，双保险）。
  Future<void> migrateLegacyLlmConfigIfNeeded() async {
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

  // ============ 拼音显示 ============

  bool get pinyinVisible =>
      HiveBoxes.settings.get(_keyPinyinVisible, defaultValue: true) as bool;

  Future<void> setPinyinVisible(bool visible) async {
    await HiveBoxes.settings.put(_keyPinyinVisible, visible);
  }

  // ============ 每日目标 ============

  /// 每日诗词背诵目标（默认 1 首）
  int get dailyPoemGoal =>
      HiveBoxes.settings.get(_keyDailyPoemGoal, defaultValue: 1) as int;

  Future<void> setDailyPoemGoal(int count) async {
    await HiveBoxes.settings.put(_keyDailyPoemGoal, count);
  }

  /// 每日口算做题目标（默认 10 题）
  int get dailyMathGoal =>
      HiveBoxes.settings.get(_keyDailyMathGoal, defaultValue: 10) as int;

  Future<void> setDailyMathGoal(int count) async {
    await HiveBoxes.settings.put(_keyDailyMathGoal, count);
  }

  // ============ 口算练习设置 ============

  /// 每组题目数量（默认 10 题）
  int get mathBatchSize =>
      HiveBoxes.settings.get(_keyMathBatchSize, defaultValue: 10) as int;

  Future<void> setMathBatchSize(int count) async {
    await HiveBoxes.settings.put(_keyMathBatchSize, count);
  }

  /// 口算难度（默认 'medium'）
  String get mathDifficulty =>
      HiveBoxes.settings.get(_keyMathDifficulty, defaultValue: 'medium')
          as String;

  Future<void> setMathDifficulty(String difficulty) async {
    await HiveBoxes.settings.put(_keyMathDifficulty, difficulty);
  }

  /// 口算练习模式（null = 综合，否则为 ProblemMode.name）
  String? get mathPracticeMode =>
      HiveBoxes.settings.get(_keyMathPracticeMode) as String?;

  Future<void> setMathPracticeMode(String? mode) async {
    if (mode == null) {
      await HiveBoxes.settings.delete(_keyMathPracticeMode);
    } else {
      await HiveBoxes.settings.put(_keyMathPracticeMode, mode);
    }
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
  List<WebDavConfig> get webDavConfigs {
    final json = HiveBoxes.settings.get(_keyWebDavConfigs) as String?;
    return WebDavConfig.decodeList(json);
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
    // 凭据 → 安全存储
    await _credentialStore.saveWebDavCredentials(
      configId: config.id,
      username: config.username,
      password: config.password,
    );

    // 非敏感信息 → Hive（凭据字段置空）
    final stripped = WebDavConfig(
      id: config.id,
      name: config.name,
      url: config.url,
      username: '',
      password: '',
      remotePath: config.remotePath,
    );
    final list = webDavConfigs;
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
    await _credentialStore.deleteWebDavCredentials(id);
    final list = webDavConfigs..removeWhere((c) => c.id == id);
    await _saveConfigsToHive(list);
  }

  Future<void> _saveConfigsToHive(List<WebDavConfig> configs) async {
    await HiveBoxes.settings.put(
      _keyWebDavConfigs,
      WebDavConfig.encodeList(configs),
    );
  }
}
