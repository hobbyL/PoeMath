// lib/core/services/sound_service.dart
//
// 音效服务：在答题正确/错误、打卡成功等场景播放短音效。
// 使用 audioplayers 播放 asset 音效文件。
// 受 settingsRepository.soundEnabled 全局开关控制。

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 音效类型枚举。
enum SoundEffect {
  correct('sounds/correct.wav'),
  wrong('sounds/wrong.wav'),
  checkIn('sounds/checkin.wav'),
  achievement('sounds/achievement.wav');

  const SoundEffect(this.assetPath);
  final String assetPath;
}

/// 音效服务。
///
/// 使用 [SettingsRepository.soundEnabled] 作为全局开关。
/// 音效文件放在 `assets/sounds/` 目录下。
class SoundService {
  final SettingsRepository _settings;
  AudioPlayer? _player;

  /// 已记录过失败的音效类型，避免答题过程中同一音效反复刷日志。
  final Set<SoundEffect> _loggedFailures = <SoundEffect>{};

  SoundService(this._settings);

  @visibleForTesting
  bool get hasPlayer => _player != null;

  /// 播放音效。开关关闭时静默跳过。
  ///
  /// 播放失败**不打断学习流程**（答对/答错的反馈音缺失不该弹提示遮住题目），
  /// 但必须留日志：用户已明确在设置页开启音效，此后每次触发都无声，
  /// 界面上没有任何可观测线索 —— 用户只会以为是自己手机静音，
  /// 线上「音效没声音」的工单将完全无法定位（asset 缺失？平台通道挂掉？
  /// 还是开关没生效？）。asset 文件本身已确认存在且已在 pubspec 声明，
  /// 所以真实失败路径只剩平台层，正是最需要日志的一类。
  ///
  /// 用 `AppLogger.e`（唯一能带 `error`/`stackTrace` 的级别，见
  /// `logger.dart` —— `AppLogger.w` 只收 message+tag）：这是可降级的体验缺失、
  /// 不影响数据，但它是**持久性**失败，用户每次答题都在失去反馈，
  /// 需要栈信息才能定位是 asset 解包还是平台通道。为避免答题时刷屏，
  /// 同一 [SoundEffect] 只记一次（`_loggedFailures`）。
  Future<void> play(SoundEffect effect) async {
    if (!_settings.soundEnabled) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.play(AssetSource(effect.assetPath));
    } on Object catch (error, stackTrace) {
      if (_loggedFailures.add(effect)) {
        AppLogger.e(
          '音效播放失败（后续同类不再重复记录）：${effect.assetPath}',
          tag: 'Sound',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  void dispose() {
    _player?.dispose();
  }
}
