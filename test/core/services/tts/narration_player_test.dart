import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import '../../../helpers/narration_fakes.dart';

class _AudioPlayer extends Fake implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final events = StreamController<AudioEvent>.broadcast(sync: true);
  final sources = <Source>[];
  Completer<void>? load;
  bool paused = false;
  bool destroyed = false;
  int resumes = 0;
  int stops = 0;
  @override
  PlayerState state = PlayerState.stopped;
  @override
  Stream<PlayerState> get onPlayerStateChanged => states.stream;
  @override
  Stream<AudioEvent> get eventStream => events.stream;
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    sources.add(source);
    paused = false;
    if (load != null) await load!.future;
    if (destroyed || paused) return;
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> pause() async {
    paused = true;
    state = PlayerState.paused;
    states.add(state);
  }

  @override
  Future<void> resume() async {
    resumes++;
    paused = false;
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> stop() async {
    stops++;
    state = PlayerState.stopped;
  }

  @override
  Future<void> dispose() async {
    destroyed = true;
  }

  void finish() {
    state = PlayerState.completed;
    events.add(const AudioEvent(eventType: AudioEventType.complete));
  }

  Future<void> close() async {
    await states.close();
    await events.close();
  }
}

void main() {
  NarrationAudio clip() => NarrationAudio(bytes: Uint8List(16), format: 'mp3');
  test('暂停保留同一音源，长暂停不计超时，恢复不重新play或seek', () async {
    final native = _AudioPlayer();
    final player = AudioplayersNarrationPlayer(
        player: native, completionTimeout: const Duration(milliseconds: 300),);
    var starts = 0;
    var ended = false;
    final task = player
        .play(clip(), onStarted: () => starts++)
        .then((_) => ended = true);
    await flushNarration();
    await player.pause();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(ended, false);
    expect(native.sources.length, 1);
    await player.resume();
    await flushNarration();
    expect(starts, 1);
    expect(native.resumes, 1);
    native.finish();
    await task;
    await player.dispose();
    await native.close();
  });
  test('播放器准备期间暂停立即传递意图，完成加载也不提前出声', () async {
    final native = _AudioPlayer()..load = Completer<void>();
    final player = AudioplayersNarrationPlayer(player: native);
    var starts = 0;
    final task = player.play(clip(), onStarted: () => starts++);
    await flushNarration();
    await player.pause();
    native.load!.complete();
    await flushNarration();
    expect(starts, 0);
    expect(native.state, PlayerState.paused);
    await player.resume();
    await flushNarration();
    expect(starts, 1);
    expect(native.sources.length, 1);
    native.finish();
    await task;
    await player.dispose();
    await native.close();
  });
  test('平台错误被接住且先停止音频；完成与暂停竞争后下一段仍正常计时', () async {
    final native = _AudioPlayer();
    final player = AudioplayersNarrationPlayer(
        player: native, completionTimeout: const Duration(milliseconds: 80),);
    final bad = player.play(clip(), onStarted: () {});
    final assertion = expectLater(bad, throwsStateError);
    await flushNarration();
    native.events.addError(StateError('音频损坏'));
    await assertion;
    expect(native.stops, 1);
    final next = player.play(clip(), onStarted: () {});
    await flushNarration();
    await player.pause();
    native.finish();
    await next;
    final third = player.play(clip(), onStarted: () {});
    await expectLater(third, throwsA(isA<Exception>()));
    expect(native.stops, 2);
    await player.dispose();
    await native.close();
  });
  test('初始化等待中停止立即结束，迟到启动不复活', () async {
    final native = _AudioPlayer()..load = Completer<void>();
    final player = AudioplayersNarrationPlayer(player: native);
    var starts = 0;
    final task = player.play(clip(), onStarted: () => starts++);
    await flushNarration();
    await player.dispose();
    await task;
    native.load!.complete();
    await flushNarration();
    expect(starts, 0);
    expect(native.destroyed, true);
    await native.close();
  });
}
