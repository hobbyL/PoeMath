// lib/core/services/haptic_service.dart
//
// 触觉反馈服务：在按钮点击、答题提交等场景触发震动反馈。
// 受 settingsRepository.hapticEnabled 全局开关控制。

import 'package:flutter/services.dart';

import 'package:poemath/data/repositories/settings_repository.dart';

/// 触觉反馈服务。
///
/// 使用 [SettingsRepository.hapticEnabled] 作为全局开关。
/// 优先使用 mediumImpact/heavyImpact，部分设备不支持时自动兜底 vibrate()。
class HapticService {
  final SettingsRepository _settings;

  HapticService(this._settings);

  /// 轻微震动（按钮点击）。
  Future<void> light() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.lightImpact();
    // 兜底：部分设备 lightImpact 无效，补一次 selectionClick
    await HapticFeedback.selectionClick();
  }

  /// 中等震动（答题提交）。
  Future<void> medium() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.mediumImpact();
    // 兜底：部分 Android 设备 mediumImpact 无效
    await HapticFeedback.vibrate();
  }

  /// 重度震动（答错、重要提醒）。
  Future<void> heavy() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.heavyImpact();
    // 兜底
    await HapticFeedback.vibrate();
  }

  /// 选择反馈（滑动切换、选项选择）。
  Future<void> selection() async {
    if (!_settings.hapticEnabled) return;
    await HapticFeedback.selectionClick();
  }
}
