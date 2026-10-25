import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';

abstract interface class NarrationPlayer {
  Future<void> play(NarrationAudio audio, {required void Function() onStarted});
  Future<void> pause();
  Future<void> resume();
  Future<void> dispose();
}

/// 与现有云音频一样等待真正完成；暂停不消耗播放超时。
class AudioplayersNarrationPlayer implements NarrationPlayer {
  AudioplayersNarrationPlayer({
    AudioPlayer? player,
    this.completionTimeout = const Duration(seconds: 300),
  }) : _player = player ?? AudioPlayer();
  final AudioPlayer _player;
  final Duration completionTimeout;
  Completer<void>? _completion;
  Timer? _timer;
  final _clock = Stopwatch();
  bool _disposed = false;
  bool _paused = false;
  bool _started = false;
  Future<void>? _loading;

  void _arm() {
    _timer?.cancel();
    if (_disposed || _paused || !_started) return;
    _clock.start();
    final remaining = completionTimeout - _clock.elapsed;
    _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      final completion = _completion;
      if (completion != null && !completion.isCompleted) {
        completion.completeError(const NarrationException('音频播放超时，请重试'));
      }
    });
  }

  @override
  Future<void> play(
    NarrationAudio audio, {
    required void Function() onStarted,
  }) async {
    if (_disposed) return;
    final completion = Completer<void>();
    _completion = completion;
    _paused = false;
    _started = false;
    _clock.reset();
    void ready() {
      if (_started || _paused || _disposed || completion.isCompleted) return;
      _started = true;
      _arm();
      onStarted();
    }

    final state = _player.onPlayerStateChanged.listen((value) {
      if (value == PlayerState.playing) ready();
    });
    final events = _player.eventStream.listen(
      (event) {
        if (event.eventType == AudioEventType.complete &&
            !completion.isCompleted) {
          completion.complete();
        }
      },
      onError: (Object error) {
        if (!completion.isCompleted) completion.completeError(error);
      },
    );
    try {
      final source = audio.path != null
          ? DeviceFileSource(audio.path!)
          : BytesSource(
              audio.bytes!,
              mimeType: audio.format == 'wav' ? 'audio/wav' : 'audio/mpeg',
            );
      final starting = _player.play(source);
      _loading = starting;
      // 在播放器初始化窗口内退出，也立即释放会话；晚到启动再次停止。
      unawaited(
        starting.then<void>(
          (_) {
            if (_disposed) unawaited(_player.stop().catchError((Object _) {}));
          },
          onError: (Object error, StackTrace stack) {
            if (!completion.isCompleted) completion.completeError(error, stack);
          },
        ),
      );
      await Future.any<void>([starting, completion.future]);
      _loading = null;
      if (_disposed) return;
      if (_player.state == PlayerState.playing) ready();
      await completion.future;
    } on Object {
      // 失败后停止旧音频，用户重试才重新播放该段。
      try {
        await _player.stop();
      } on Object {/* 保留原始播放错误。 */}
      rethrow;
    } finally {
      _timer?.cancel();
      _clock.stop();
      _completion = null;
      _loading = null;
      await state.cancel();
      await events.cancel();
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _timer?.cancel();
    _clock.stop();
    try {
      if (!_disposed && _completion?.isCompleted == false) {
        await _player.pause();
      }
    } on Object {
      _paused = false;
      _arm();
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    _paused = false;
    if (!_disposed && _completion?.isCompleted == false) {
      final loading = _loading;
      if (loading != null) {
        await Future.any<void>([loading, _completion!.future]);
        if (_disposed || _completion?.isCompleted != false) return;
      }
      await _player.resume();
      _arm();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    final completion = _completion;
    if (completion != null && !completion.isCompleted) completion.complete();
    try {
      await _player.stop();
    } finally {
      await _player.dispose();
    }
  }
}
