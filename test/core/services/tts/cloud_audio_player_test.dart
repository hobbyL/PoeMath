import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/tts_models.dart';

class _NativePlayer extends Fake implements AudioPlayer {
  final events = StreamController<AudioEvent>.broadcast(sync: true);
  final sources = <Source>[];
  AudioContext? context;
  Completer<void>? loading;
  Completer<void>? stopping;
  int stops = 0;
  bool intendedPlaying = false;
  bool audible = false;

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
    context = ctx;
    intendedPlaying = true;
    await loading?.future;
    audible = intendedPlaying;
  }

  @override
  Future<void> stop() async {
    stops++;
    intendedPlaying = false;
    audible = false;
    await stopping?.future;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('诗词云播放器声明 MP3 与媒体用途，底层失败立即退出并停止', () async {
    final native = _NativePlayer();
    final player = AudioplayersCloudAudioPlayer(player: native);
    final playing = player.play(Uint8List(16));
    final failure = expectLater(playing, throwsStateError);
    await _flush();
    expect(native.sources.single.mimeType, 'audio/mpeg');
    expect(native.context!.android.contentType, AndroidContentType.speech);
    expect(native.context!.android.usageType, AndroidUsageType.media);
    expect(native.context!.iOS.category, AVAudioSessionCategory.playback);
    native.events.addError(StateError('解码失败'));
    await failure;
    expect(native.audible, isFalse);
    expect(native.stops, 2);
    await player.dispose();
    await native.events.close();
  });

  test('准备音频期间停止立即释放，迟到准备结果不播放，随后新播放可完成', () async {
    final native = _NativePlayer()..loading = Completer<void>();
    final player = AudioplayersCloudAudioPlayer(player: native);
    final old = player.play(Uint8List(16));
    await _flush();
    await player.stop();
    await old;
    native.loading!.complete();
    await _flush();
    expect(native.audible, isFalse);
    native.loading = null;
    final next = player.play(Uint8List(32));
    await _flush();
    expect(native.audible, isTrue);
    native.events.add(const AudioEvent(eventType: AudioEventType.complete));
    await next;
    expect(native.sources.length, 2);
    await player.dispose();
    await native.events.close();
  });

  test('停止旧音频期间取消，不再启动排队的云音频', () async {
    final native = _NativePlayer()..stopping = Completer<void>();
    final player = AudioplayersCloudAudioPlayer(player: native);
    final playing = player.play(Uint8List(16));
    await _flush();
    final stopped = player.stop();
    native.stopping!.complete();
    await stopped;
    await playing;
    expect(native.sources, isEmpty);
    await player.dispose();
    await native.events.close();
  });
}
