// lib/data/repositories/settings_repository.dart
//
// 层级：data/repositories
// 职责：应用设置仓储。使用 settingsBox 作为 KV 存储。

import 'dart:convert';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/webdav_config.dart';

class SettingsRepository {
  // ============ KV 键名 ============
  static const String _keyThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyHapticEnabled = 'haptic_enabled';
  static const String _keySelectedGrade = 'selected_grade';
  static const String _keyTtsSpeed = 'tts_speed';
  static const String _keyTtsVoice = 'tts_voice'; // JSON: {"name":"...", "locale":"..."}
  static const String _keyPinyinVisible = 'pinyin_visible';
  static const String _keyDailyPoemGoal = 'daily_poem_goal';
  static const String _keyDailyMathGoal = 'daily_math_goal';
  static const String _keyWebDavConfigs = 'webdav_configs';
  static const String _keyMathBatchSize = 'math_batch_size';
  static const String _keyMathDifficulty = 'math_difficulty';

  // ============ 主题 ============

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

  // ============ WebDAV 配置 ============

  /// 所有 WebDAV 同步配置。
  List<WebDavConfig> get webDavConfigs {
    final json = HiveBoxes.settings.get(_keyWebDavConfigs) as String?;
    return WebDavConfig.decodeList(json);
  }

  /// 保存（新增或更新）一条 WebDAV 配置。
  Future<void> saveWebDavConfig(WebDavConfig config) async {
    final list = webDavConfigs;
    final index = list.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      list[index] = config;
    } else {
      list.add(config);
    }
    await HiveBoxes.settings.put(
      _keyWebDavConfigs,
      WebDavConfig.encodeList(list),
    );
  }

  /// 删除一条 WebDAV 配置。
  Future<void> deleteWebDavConfig(String id) async {
    final list = webDavConfigs..removeWhere((c) => c.id == id);
    await HiveBoxes.settings.put(
      _keyWebDavConfigs,
      WebDavConfig.encodeList(list),
    );
  }
}
