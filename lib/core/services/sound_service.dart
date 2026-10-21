// lib/core/services/sound_service.dart
//
// 音效服务：在答题正确/错误、打卡成功等场景播放短音效。
// 使用 audioplayers 播放 asset 音效文件。
// 受 settingsRepository.soundEnabled 全局开关控制。

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/completion_sound.dart';
import 'package:poemath/domain/answer_feedback_sound.dart';

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
  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  bool _disposed = false;
  bool _previewingAnswerFeedback = false;
  Completer<bool>? _previewCompletion;

  // 答题反馈均为短音效，防止平台未回报完成时一直锁住试听按钮。
  static const _previewTimeout = Duration(seconds: 15);

  /// 已记录过失败的音效类型，避免答题过程中同一音效反复刷日志。
  final Set<String> _loggedFailures = <String>{};

  SoundService(this._settings, {AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new;

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
  /// 同一素材路径只记一次（`_loggedFailures`）。
  Future<void> play(SoundEffect effect) async {
    if (!_settings.soundEnabled) return;
    final path = switch (effect) {
      SoundEffect.correct =>
        _settings.answerFeedbackSound.assetPath(correct: true),
      SoundEffect.wrong =>
        _settings.answerFeedbackSound.assetPath(correct: false),
      _ => effect.assetPath,
    };
    await _playAsset(path);
  }

  /// 完成一组练习后读取当前选择；全局开关关闭时跳过。
  Future<void> playCompletion() async {
    if (!_settings.soundEnabled) return;
    await _playAsset(_settings.completionSound.assetPath);
  }

  /// 用户主动试听不改变音效开关，由选择面板的独立服务管理播放器。
  Future<bool> previewCompletion(CompletionSound sound) =>
      _playAsset(sound.assetPath);

  /// 一次依次试听答对、答错，不写设置，也不受自动音效开关影响。
  Future<bool> previewAnswerFeedback(AnswerFeedbackSound sound) async {
    if (_disposed || _previewingAnswerFeedback) return false;
    _previewingAnswerFeedback = true;
    try {
      for (final correct in [true, false]) {
        final success = await _playAsset(
          sound.assetPath(correct: correct),
          waitForCompletion: true,
        );
        if (!success) return false;
      }
      return true;
    } finally {
      _previewingAnswerFeedback = false;
    }
  }

  Future<bool> _playAsset(
    String assetPath, {
    bool waitForCompletion = false,
  }) async {
    if (_disposed) return false;
    StreamSubscription<void>? subscription;
    Completer<bool>? completion;
    try {
      final player = _player ??= _playerFactory();
      if (waitForCompletion) {
        final session = Completer<bool>();
        completion = session;
        _previewCompletion = session;
        // play() 只等启动；先监听完成事件，避免短素材结束早于订阅。
        subscription = player.onPlayerComplete.listen(
          (_) {
            if (!session.isCompleted) session.complete(true);
          },
          onError: (Object error, StackTrace stackTrace) {
            _logFailure(assetPath, error, stackTrace);
            if (!session.isCompleted) session.complete(false);
          },
          onDone: () {
            if (!session.isCompleted) session.complete(false);
          },
        );
      }
      await player.play(AssetSource(assetPath));
      if (completion == null) return !_disposed;
      return await completion.future.timeout(_previewTimeout);
    } on Object catch (error, stackTrace) {
      _logFailure(assetPath, error, stackTrace);
      return false;
    } finally {
      if (identical(_previewCompletion, completion)) {
        _previewCompletion = null;
      }
      await subscription?.cancel();
    }
  }

  void _logFailure(String assetPath, Object error, StackTrace stackTrace) {
    if (_loggedFailures.add(assetPath)) {
      AppLogger.e(
        '音效播放失败（后续同类不再重复记录）：$assetPath',
        tag: 'Sound',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final completion = _previewCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(false);
    }
    _player?.dispose();
  }
}
