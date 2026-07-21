// lib/data/repositories/settings_repository.dart
//
// 层级：data/repositories
// 职责：应用设置仓储。使用 settingsBox 作为 KV 存储。

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';

class SettingsRepository {
  SettingsRepository({SecureCredentialStore? credentialStore})
      : _credentialStore = credentialStore ?? SecureCredentialStore();
  // ============ KV 键名 ============
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
  static const String _keyTencentAsrHighAccuracyEnabled =
      'tencent_asr_high_accuracy_enabled';

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

  bool get tencentAsrHighAccuracyEnabled => HiveBoxes.settings.get(
        _keyTencentAsrHighAccuracyEnabled,
        defaultValue: false,
      ) as bool;

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
    final requestedHighAccuracy = tencentAsrHighAccuracyEnabled;

    if (requestedHighAccuracy && !isVerified) {
      await HiveBoxes.settings.put(
        _keyTencentAsrHighAccuracyEnabled,
        false,
      );
    }

    return SpeechRecognitionSettingsState(
      hasCredentials: credentials != null,
      isVerified: isVerified,
      highAccuracyEnabled: requestedHighAccuracy && isVerified,
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

  Future<void> setTencentAsrHighAccuracyEnabled(bool enabled) async {
    if (enabled) {
      final state = await loadSpeechRecognitionSettings();
      if (!state.isVerified) {
        throw StateError('请先完成腾讯云真实录音测试');
      }
    }
    await HiveBoxes.settings.put(
      _keyTencentAsrHighAccuracyEnabled,
      enabled,
    );
  }

  Future<void> invalidateTencentAsrVerification() async {
    await HiveBoxes.settings.put(
      _keyTencentAsrHighAccuracyEnabled,
      false,
    );
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
