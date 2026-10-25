import 'dart:async';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';

enum NarrationStatus {
  preparing,
  buffering,
  playing,
  paused,
  failed,
  completed,
  stopped
}

class NarrationState {
  const NarrationState(this.status, this.index, {this.message});
  final NarrationStatus status;
  final int index;
  final String? message;
}

typedef _Prepared = ({NarrationAudio? audio, Object? error});

class _Cancelled implements Exception {}

/// 身份只来自 TtsService；页面不维护第二个代际计数器。
class NarrationSession {
  NarrationSession({
    required this.sessionId,
    required this.count,
    required this.player,
    required this.isCurrent,
    required this.prepare,
    required this.cancelPreparation,
    this.onState,
    this.onSegmentStart,
  });
  final int sessionId;
  final int count;
  final NarrationPlayer player;
  final bool Function() isCurrent;
  final Future<NarrationAudio> Function(int index) prepare;
  final Future<void> Function() cancelPreparation;
  final void Function(NarrationState state, int sessionId)? onState;
  final void Function(int index, int sessionId)? onSegmentStart;
  final _pending = <int, Future<_Prepared>>{};
  final _cancelled = Completer<void>();
  Completer<void>? _resumeGate;
  Completer<void>? _retryGate;
  bool _stopped = false;
  bool _paused = false;
  bool _playing = false;
  bool _started = false;
  int _index = 0;
  late final Future<void> completed;
  bool get active => !_stopped && isCurrent();

  void start() {
    completed = _run();
  }

  void _check() {
    if (!active) throw _Cancelled();
  }

  void _emit(NarrationStatus status, {String? message}) {
    if (isCurrent() || status == NarrationStatus.stopped) {
      onState?.call(
        NarrationState(status, _index, message: message),
        sessionId,
      );
    }
  }

  Future<T> _owned<T>(Future<T> future) => Future.any<T>([
        future,
        _cancelled.future.then<T>((_) => throw _Cancelled()),
      ]);
  Future<void> _unpaused() async {
    _check();
    while (_paused) {
      await _owned(_resumeGate!.future);
    }
    _check();
  }

  Future<_Prepared> _prepare(int index) => _pending.putIfAbsent(
        index,
        () => Future.sync(() {
          _check();
          return prepare(index);
        }).then<_Prepared>(
          (audio) {
            if (!active) {
              audio.release();
              return (audio: null, error: _Cancelled());
            }
            return (audio: audio, error: null);
          },
          onError: (Object error, StackTrace _) => (audio: null, error: error),
        ),
      );
  void _prefetch() {
    if (!active || _paused) return;
    for (var next = _index + 1; next < count && next <= _index + 2; next++) {
      _prepare(next);
    }
  }

  Future<void> _run() async {
    try {
      while (_index < count) {
        NarrationAudio? audio;
        try {
          await _unpaused();
          _emit(
            _index == 0 ? NarrationStatus.preparing : NarrationStatus.buffering,
          );
          final ready = await _owned(_prepare(_index));
          _pending.remove(_index);
          if (ready.error != null) throw ready.error!;
          audio = ready.audio!;
          await _unpaused();
          _playing = true; // 包含播放器加载窗口，暂停同样必须传到平台。
          _started = false;
          await _owned(
            player.play(
              audio,
              onStarted: () {
                if (!active) return;
                _started = true;
                onSegmentStart?.call(_index, sessionId);
                if (_paused) {
                  unawaited(player.pause().catchError((Object _) {}));
                } else {
                  _emit(NarrationStatus.playing);
                  _prefetch();
                }
              },
            ),
          );
          _playing = false;
          await _unpaused();
          _index++;
        } on _Cancelled {
          return;
        } on Object catch (error) {
          if (!active) return;
          _playing = false;
          _pending.remove(_index);
          await _unpaused();
          _retryGate = Completer<void>();
          _emit(
            NarrationStatus.failed,
            message: error is NarrationException ? error.message : '朗读遇到问题，请重试',
          );
          await _owned(_retryGate!.future);
          _retryGate = null;
        } finally {
          audio?.release();
        }
      }
      if (active) _emit(NarrationStatus.completed);
    } on _Cancelled {/* 正常停止 */} finally {
      for (final future in _pending.values) {
        unawaited(future.then((ready) => ready.audio?.release()));
      }
      _pending.clear();
      await player.dispose();
    }
  }

  Future<void> pause() async {
    if (!active || _paused) return;
    _paused = true;
    _resumeGate = Completer<void>();
    _emit(NarrationStatus.paused);
    try {
      if (_playing) await player.pause();
    } on Object {
      _paused = false;
      _resumeGate?.complete();
      _resumeGate = null;
      _emit(_playing && _started
          ? NarrationStatus.playing
          : NarrationStatus.buffering,);
      rethrow;
    }
  }

  Future<void> resume() async {
    if (!active || !_paused) return;
    _paused = false;
    try {
      if (_playing) await player.resume();
    } on Object {
      _paused = true;
      _emit(NarrationStatus.paused);
      rethrow;
    }
    if (!active) return;
    _resumeGate?.complete();
    _resumeGate = null;
    _emit(_playing && _started
        ? NarrationStatus.playing
        : NarrationStatus.buffering,);
    if (_playing && _started) _prefetch();
  }

  void retry() {
    if (active && _retryGate?.isCompleted == false) _retryGate!.complete();
  }

  Future<void> cancel() async {
    if (_stopped) return;
    _stopped = true;
    _cancelled.complete();
    _emit(NarrationStatus.stopped);
    await Future.wait([player.dispose(), cancelPreparation()]);
  }
}
