// lib/data/repositories/settings_repository.dart
//
// 层级：data/repositories
// 职责：应用设置仓储。使用 settingsBox 作为 KV 存储。

import 'package:poemath/data/hive/hive_boxes.dart';

class SettingsRepository {
  // ============ KV 键名 ============
  static const String _keyThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyHapticEnabled = 'haptic_enabled';
  static const String _keySelectedGrade = 'selected_grade';
  static const String _keyTtsSpeed = 'tts_speed';
  static const String _keyPinyinVisible = 'pinyin_visible';

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

  // ============ 拼音显示 ============

  bool get pinyinVisible =>
      HiveBoxes.settings.get(_keyPinyinVisible, defaultValue: true) as bool;

  Future<void> setPinyinVisible(bool visible) async {
    await HiveBoxes.settings.put(_keyPinyinVisible, visible);
  }
}
