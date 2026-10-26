import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';

class Player implements NarrationPlayer {
  final played = <int>[];
  final completions = <Completer<void>>[];
  final starts = <void Function()>[];
  int pauses = 0;
  int resumes = 0;
  bool disposed = false;
  @override
  Future<void> play(NarrationAudio audio,
      {required void Function() onStarted,}) {
    played.add(audio.bytes!.single);
    starts.add(onStarted);
    final completion = Completer<void>();
    completions.add(completion);
    return completion.future;
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> resume() async {
    resumes++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    for (final c in completions) {
      if (!c.isCompleted) c.complete();
    }
  }
}

NarrationAudio audio(int index) =>
    NarrationAudio(bytes: Uint8List.fromList([index]), format: 'mp3');
Future<void> flush() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.value();
  }
}

void main() {
  test('实际音频身份回调同步取消，片段不会播放且租约只释放一次', () async {
    final player = Player();
    final identity = NarrationAudioIdentity(cacheKey: 'a' * 64, backend: NarrationBackend.system, audioSha256: 'b' * 64);
    var released = 0, cancelled = 0;
    final calls = <int>[];
    final statuses = <NarrationStatus>[];
    late NarrationSession session;
    session = NarrationSession(sessionId: 9, count: 1, player: player,
      isCurrent: () => true, cancelPreparation: () async {cancelled++;},
      prepare: (_) async => NarrationAudio(bytes: Uint8List.fromList([1]), format: 'wav', identity: identity, release: () => released++),
      onAudioReady: (index, actual, id) {expect(actual.signature, identity.signature); expect(id, 9); calls.add(index); unawaited(session.cancel());},
      onState: (state, _) => statuses.add(state.status),);
    session.start(); await session.completed; await flush();
    expect(calls, [0]); expect(player.played, isEmpty); expect(player.starts, isEmpty);
    expect(released, 1); expect(cancelled, 1);
    expect(statuses, contains(NarrationStatus.stopped)); expect(statuses, isNot(contains(NarrationStatus.completed)));
  });
  test('恢复与再次暂停同帧发生时必须等待新的暂停闸门', () async {
    final player = Player();
    final gate = Completer<NarrationAudio>();
    final session = NarrationSession(
      sessionId: 6,
      count: 1,
      player: player,
      isCurrent: () => true,
      cancelPreparation: () async {},
      prepare: (_) => gate.future,
    );
    session.start();
    await flush();
    await session.pause();
    gate.complete(audio(0));
    await flush();
    final resuming = session.resume();
    final pausing = session.pause();
    await Future.wait([resuming, pausing]);
    await flush();
    expect(player.played, isEmpty);
    await session.resume();
    await flush();
    expect(player.played, [0]);
    await session.cancel();
    await session.completed;
  });
  test('首段先播放，真正播放后才高亮与有限预取；乱序生成按序播放', () async {
    final gates = List.generate(5, (_) => Completer<NarrationAudio>());
    final requests = <int>[];
    final highlights = <int>[];
    final player = Player();
    final session = NarrationSession(
      sessionId: 7,
      count: 5,
      player: player,
      isCurrent: () => true,
      cancelPreparation: () async {},
      prepare: (index) {
        requests.add(index);
        return gates[index].future;
      },
      onSegmentStart: (index, id) {
        expect(id, 7);
        highlights.add(index);
      },
    );
    session.start();
    await flush();
    expect(requests, [0]);
    expect(highlights, isEmpty);
    expect(player.played, isEmpty);
    gates[0].complete(audio(0));
    await flush();
    expect(player.played, [0]);
    expect(requests, [0]);
    expect(highlights, isEmpty);
    player.starts[0]();
    await flush();
    expect(requests, [0, 1, 2]);
    expect(highlights, [0]);
    gates[2].complete(audio(2));
    gates[1].complete(audio(1));
    await flush();
    expect(player.played, [0]);
    player.completions[0].complete();
    await flush();
    expect(player.played, [0, 1]);
    player.starts[1]();
    await flush();
    expect(highlights, [0, 1]);
    expect(requests, [0, 1, 2, 3]);
    await session.cancel();
    await session.completed;
    gates[3].complete(audio(3));
    await flush();
    expect(player.played, [0, 1]);
  });
  test('暂停不重建音频，完成与暂停竞争时不推进；恢复后继续', () async {
    final player = Player();
    final states = <NarrationStatus>[];
    final session = NarrationSession(
      sessionId: 8,
      count: 2,
      player: player,
      isCurrent: () => true,
      cancelPreparation: () async {},
      prepare: (i) async => audio(i),
      onState: (state, _) => states.add(state.status),
    );
    session.start();
    await flush();
    player.starts[0]();
    await flush();
    await session.pause();
    expect(player.pauses, 1);
    expect(player.played, [0]);
    player.completions[0].complete();
    await flush();
    expect(player.played, [0]);
    expect(states.last, NarrationStatus.paused);
    await session.resume();
    await flush();
    expect(player.played, [0, 1]);
    await session.cancel();
    await session.completed;
  });
  test('生成时暂停，音频完成也不能出声；退出后晚到结果释放', () async {
    final gate = Completer<NarrationAudio>();
    final player = Player();
    var releases = 0;
    final session = NarrationSession(
      sessionId: 9,
      count: 1,
      player: player,
      isCurrent: () => true,
      cancelPreparation: () async {},
      prepare: (_) => gate.future,
    );
    session.start();
    await flush();
    await session.pause();
    gate.complete(NarrationAudio(
        bytes: Uint8List.fromList([0]),
        format: 'mp3',
        release: () => releases++,),);
    await flush();
    expect(player.played, isEmpty);
    await session.cancel();
    await session.completed;
    expect(releases, 1);
    expect(player.played, isEmpty);
  });
  test('后台生成失败不产生未处理错误，当前段失败可重试且不跳句', () async {
    final player = Player();
    var attempts = 0;
    final states = <NarrationStatus>[];
    final session = NarrationSession(
      sessionId: 10,
      count: 2,
      player: player,
      isCurrent: () => true,
      cancelPreparation: () async {},
      prepare: (i) async {
        if (i == 1 && attempts++ == 0) throw const NarrationException('测试失败');
        return audio(i);
      },
      onState: (state, _) => states.add(state.status),
    );
    session.start();
    await flush();
    player.starts[0]();
    await flush();
    player.completions[0].complete();
    await flush();
    expect(states.last, NarrationStatus.failed);
    expect(player.played, [0]);
    session.retry();
    await flush();
    expect(player.played, [0, 1]);
    await session.cancel();
    await session.completed;
  });
  test('停止在合成等待内立即结束，不等服务响应；晚到结果不播放', () async {
    final gate = Completer<NarrationAudio>();
    final player = Player();
    var cancels = 0;
    final session = NarrationSession(
      sessionId: 11,
      count: 1,
      player: player,
      isCurrent: () => true,
      cancelPreparation: () async {
        cancels++;
      },
      prepare: (_) => gate.future,
    );
    session.start();
    await flush();
    await session.cancel();
    await session.completed;
    expect(cancels, 1);
    expect(player.disposed, true);
    gate.complete(audio(0));
    await flush();
    expect(player.played, isEmpty);
  });
}
