// lib/core/services/sound_service.dart
//
// 音效服务：在答题正确/错误、打卡成功等场景播放短音效。
// 使用 audioplayers 播放 asset 音效文件。
// 受 settingsRepository.soundEnabled 全局开关控制。

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

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

  SoundService(this._settings);

  @visibleForTesting
  bool get hasPlayer => _player != null;

  /// 播放音效。开关关闭时静默跳过。
  Future<void> play(SoundEffect effect) async {
    if (!_settings.soundEnabled) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.play(AssetSource(effect.assetPath));
    } catch (_) {
      // 音效文件缺失或播放失败时静默忽略
    }
  }

  void dispose() {
    _player?.dispose();
  }
}
