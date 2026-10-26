import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts/narration_audio_identity.dart';
import 'package:poemath/core/services/tts_service.dart';
import '../../../helpers/narration_fakes.dart';
import '../../../helpers/textbook_course_fixture.dart';

class _BrokenSettings extends NarrationSettings {
  @override
  double get ttsSpeed => throw StateError('Hive closed');
}

class _DelayedPlayer extends RecordingNarrationPlayer {
  final gate = Completer<void>();
  Future<void>? disposing;
  @override
  Future<void> dispose() => disposing ??= gate.future.then((_) => super.dispose());
}

void main() {
  test('旧播放器停止未完成时新入口等待，迟到的短文本入口不抢播', () async {
    final oldPlayer = _DelayedPlayer(); final freshPlayer = RecordingNarrationPlayer();
    var created = 0; final engine = NarrationEngine(); final cache = MemoryNarrationCache();
    final service = TtsService(NarrationSettings(), flutterTts: engine, fileSynthesizer: NarrationSynth(),
      narrationPlayerFactory: () => created++ == 0 ? oldPlayer : freshPlayer,);
    final old = service.startNarration(['旧文。'], bookId: courseFixtureHash, cache: cache);
    await flushNarration(); oldPlayer.starts.single();
    final legacy = service.speak('迟到的短文本'); await flushNarration(); expect(engine.spoken, isEmpty);
    final fresh = service.startNarration(['新文。'], bookId: courseFixtureHash, cache: cache);
    await flushNarration(); expect(freshPlayer.audio, isEmpty);
    oldPlayer.gate.complete(); await flushNarration(); await legacy; await old.completed;
    expect(engine.spoken, isEmpty); expect(freshPlayer.audio.length, 1);
    await service.stop(); await fresh.completed; service.dispose();
  });
  test('系统文件音频复用缓存，改变语速或实际引擎身份必须重新合成', () async {
    final settings = NarrationSettings();
    final synth = NarrationSynth();
    final cache = MemoryNarrationCache();
    final service = TtsService(
      settings,
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () =>
          RecordingNarrationPlayer()..automatic = true,
    );
    Future<void> read() => service.startNarration(['星月。'],
        bookId: courseFixtureHash, cache: cache,).completed;
    await read();
    await read();
    expect(synth.texts, ['星月。']);
    settings.speed = 0.6;
    await read();
    expect(synth.texts.length, 2);
    synth.identity = 'engine-v2|zh-CN';
    await read();
    expect(synth.texts.length, 3);
    service.dispose();
  });

  test('额度失败禁止新云请求但继续读取后续云缓存，缺失片段才用系统音色', () async {
    final settings = NarrationSettings()..enabled = true;
    final cloud = NarrationCloud();
    final synth = NarrationSynth();
    final cache = MemoryNarrationCache();
    final players = <RecordingNarrationPlayer>[];
    final service = TtsService(
      settings,
      flutterTts: NarrationEngine(),
      cloudClient: cloud.client,
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final p = RecordingNarrationPlayer()..automatic = true;
        players.add(p);
        return p;
      },
    );
    await service.startNarration(['缓存段。'],
        bookId: courseFixtureHash, cache: cache,).completed;
    cloud.usage.exhausted = true;
    final identities = <NarrationBackend>[];
    final session = service.startNarration(['缺失段。', '缓存段。', '另一个缺失段。'],
        bookId: courseFixtureHash, cache: cache, onAudioReady: (index, identity, sessionId) => identities.add(identity.backend),);
    await session.completed;
    expect(cloud.texts, ['缓存段。']);
    expect(cloud.usage.reservations, 2);
    expect(synth.texts, ['缺失段。', '另一个缺失段。']);
    expect(players.last.audio.map((a) => a.format), ['wav', 'mp3', 'wav']);
    expect(identities, [NarrationBackend.system, NarrationBackend.cloud, NarrationBackend.system]);
    service.dispose();
  });

  test('旧合成晚到不播放或写缓存，新会话与旧短文本接口相互停止', () async {
    final synth = NarrationSynth();
    final gate = Completer<Uint8List>();
    synth.generate = (text) =>
        text == '旧文。' ? gate.future : Future.value(Uint8List.fromList([7]));
    final players = <RecordingNarrationPlayer>[];
    final engine = NarrationEngine();
    final cache = MemoryNarrationCache();
    final service = TtsService(
      NarrationSettings(),
      flutterTts: engine,
      fileSynthesizer: synth,
      narrationPlayerFactory: () {
        final p = RecordingNarrationPlayer();
        players.add(p);
        return p;
      },
    );
    final old = service
        .startNarration(['旧文。'], bookId: courseFixtureHash, cache: cache);
    await flushNarration();
    final fresh = service
        .startNarration(['新文。'], bookId: courseFixtureHash, cache: cache);
    await flushNarration();
    gate.complete(Uint8List.fromList([1]));
    await flushNarration();
    expect(old.sessionId, lessThan(fresh.sessionId));
    expect(players.first.audio, isEmpty);
    expect(players.last.audio.length, 1);
    expect(cache.entries.length, 1);
    await service.speak('旧入口');
    await fresh.completed;
    expect(players.last.disposed, true);
    expect(engine.spoken, ['旧入口']);
    final finalRead = service
        .startNarration(['新文。'], bookId: courseFixtureHash, cache: cache);
    await flushNarration();
    await service.stop();
    await finalRead.completed;
    expect(service.isSpeaking, false);
    service.dispose();
  });

  test('设置读取 Error 被包装且播放态归零；生成失败暂停后仍可恢复并重试', () async {
    final broken = TtsService(_BrokenSettings(), flutterTts: NarrationEngine());
    expect(
        () => broken.startNarration(['正文。'],
            bookId: courseFixtureHash, cache: MemoryNarrationCache(),),
        throwsA(isA<TtsException>()),);
    expect(broken.isSpeaking, false);
    broken.dispose();
    final gate = Completer<Uint8List>();
    final synth = NarrationSynth()..generate = (_) => gate.future;
    final states = <NarrationStatus>[];
    final p = RecordingNarrationPlayer();
    final service = TtsService(NarrationSettings(),
        flutterTts: NarrationEngine(),
        fileSynthesizer: synth,
        narrationPlayerFactory: () => p,);
    final session = service.startNarration(
      ['正文。'],
      bookId: courseFixtureHash,
      cache: MemoryNarrationCache(),
      onState: (s, _) => states.add(s.status),
    );
    await flushNarration();
    await session.pause();
    gate.completeError(StateError('生成失败'));
    await flushNarration();
    expect(states.last, NarrationStatus.paused);
    await session.resume();
    await flushNarration();
    expect(states.last, NarrationStatus.failed);
    synth.generate = null;
    session.retry();
    await flushNarration();
    expect(p.audio.length, 1);
    await service.stop();
    await session.completed;
    service.dispose();
  });
}
