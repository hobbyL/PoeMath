// lib/core/services/haptic_service.dart
//
// 触觉反馈服务：在按钮点击、答题提交等场景触发震动反馈。
// 受 settingsRepository.hapticEnabled 全局开关控制。

import 'package:flutter/services.dart';

import 'package:poemath/data/repositories/settings_repository.dart';

/// 触觉反馈服务。
///
/// 使用 [SettingsRepository.hapticEnabled] 作为全局开关。
/// 优先使用 lightImpact/mediumImpact/heavyImpact；**仅当主调用抛异常时**
/// 才兜底一次替代震动。早期实现无条件追加兜底，导致每次反馈震动两次。
class HapticService {
  final SettingsRepository _settings;

  HapticService(this._settings);

  /// 轻微震动（按钮点击）。
  Future<void> light() async {
    if (!_settings.hapticEnabled) return;
    await _withFallback(
      HapticFeedback.lightImpact,
      HapticFeedback.selectionClick,
    );
  }

  /// 中等震动（答题提交）。
  Future<void> medium() async {
    if (!_settings.hapticEnabled) return;
    await _withFallback(HapticFeedback.mediumImpact, HapticFeedback.vibrate);
  }

  /// 重度震动（答错、重要提醒）。
  Future<void> heavy() async {
    if (!_settings.hapticEnabled) return;
    await _withFallback(HapticFeedback.heavyImpact, HapticFeedback.vibrate);
  }

  /// 选择反馈（滑动切换、选项选择）。
  Future<void> selection() async {
    if (!_settings.hapticEnabled) return;
    await _withFallback(HapticFeedback.selectionClick, null);
  }

  /// 执行 [primary]；仅在其抛异常（如平台未实现该通道）时才调用
  /// [fallback]。兜底自身再失败一律忽略——触觉反馈不值得打断业务流程。
  Future<void> _withFallback(
    Future<void> Function() primary,
    Future<void> Function()? fallback,
  ) async {
    try {
      await primary();
    } on Exception {
      if (fallback == null) return;
      try {
        await fallback();
      } on Exception {
        // 兜底也不支持：静默忽略。
      }
    }
  }
}
