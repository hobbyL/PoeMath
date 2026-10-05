// lib/data/repositories/settings_repository.dart
//
// 层级：data/repositories
// 职责：应用设置仓储。使用 settingsBox 作为 KV 存储。

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
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

  // ============ LLM 应用题生成设置（可选） ============

  /// LLM 服务地址（Hive 非敏感存储）；未配置返回空串。
  String get llmBaseUrl =>
      HiveBoxes.settings.get(_keyLlmBaseUrl, defaultValue: '') as String;

  Future<void> setLlmBaseUrl(String baseUrl) async {
    await HiveBoxes.settings.put(_keyLlmBaseUrl, baseUrl);
  }

  /// LLM 模型名；未配置返回空串。
  String get llmModel =>
      HiveBoxes.settings.get(_keyLlmModel, defaultValue: '') as String;

  Future<void> setLlmModel(String model) async {
    await HiveBoxes.settings.put(_keyLlmModel, model);
  }

  /// 读取 LLM 完整配置；地址或模型未配置时返回 null（Key 允许为空，
  /// 对应 Ollama 等无鉴权服务）。
  Future<LlmConfig?> readLlmConfig() async {
    final base = llmBaseUrl.trim();
    final model = llmModel.trim();
    if (base.isEmpty || model.isEmpty) return null;
    final apiKey = await _credentialStore.readLlmApiKey();
    return LlmConfig(baseUrl: base, apiKey: apiKey ?? '', model: model);
  }

  /// 保存 LLM 配置（地址/模型入 Hive、Key 入安全存储）。
  Future<void> saveLlmConfig({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    // 先校验地址合法（非法抛 FormatException，不落盘）。
    LlmClient.normalizeBaseUrl(baseUrl);
    final key = apiKey.trim();
    if (key.isEmpty) {
      await _credentialStore.deleteLlmApiKey();
    } else {
      await _credentialStore.saveLlmApiKey(key);
    }
    await setLlmBaseUrl(baseUrl.trim());
    await setLlmModel(model.trim());
  }

  /// 删除 LLM 配置（Key + 地址 + 模型）。
  Future<void> deleteLlmConfig() async {
    await _credentialStore.deleteLlmApiKey();
    await HiveBoxes.settings.delete(_keyLlmBaseUrl);
    await HiveBoxes.settings.delete(_keyLlmModel);
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
