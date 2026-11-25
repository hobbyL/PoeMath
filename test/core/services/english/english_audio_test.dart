import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/english_recording_store.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/features/english/english_audio.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/narration_fakes.dart';
import '../../../helpers/english_fixture.dart';

class _Recorder implements SpeechAudioRecorder {
  final stream = StreamController<Uint8List>.broadcast();
  bool permitted = true, started = false, disposed = false;
  Completer<bool>? permission;
  Completer<void>? stopping;
  Completer<void>? releasing, disposing;
  Object? stopError;
  @override
  Future<bool> hasPermission() async =>
      permission == null ? permitted : await permission!.future;
  @override
  Future<Stream<Uint8List>> startStream() async {
    started = true;
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    await stopping?.future;
    if (stopError != null) throw stopError!;
    started = false;
  }

  @override
  Future<void> cancel() async {
    started = false;
  }

  @override
  Future<void> dispose() async {
    if (disposing != null && !disposing!.isCompleted) disposing!.complete();
    await releasing?.future;
    disposed = true;
    await stream.close();
  }
}

class _Synth extends NarrationSynth {
  final voices = <Map<String, String>?>[];
  @override
  Future<String> describeVoice(Map<String, String>? voice, double speed) async {
    voices.add(voice);
    return '${voice?['locale']}|${voice?['name']}|$speed';
  }
}

void main() {
  late Directory root;
  setUp(() async {
    await setUpHiveForTesting();
    root = await Directory.systemTemp.createTemp('english-audio-');
  });
  tearDown(() async {
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });
  test('英文显式声音绕过云端，之后中文仍使用原设置，同声缓存复用', () async {
    final settings = NarrationSettings()
      ..voice = {'locale': 'zh-CN', 'name': 'Chinese'};
    final synth = _Synth(), cache = MemoryNarrationCache();
    final tts = TtsService(
      settings,
      flutterTts: NarrationEngine(),
      fileSynthesizer: synth,
      narrationPlayerFactory: () =>
          RecordingNarrationPlayer()..automatic = true,
    );
    final audio = EnglishAudio(
      bookId: englishBook().pdfSha256,
      tts: tts,
      cache: cache,
      store: EnglishRecordingStore(directory: () async => root),
    );
    settings.enabled = true;
    expect(
      await audio.speak('A red kite.', {'locale': 'en-US', 'name': 'English'}),
      isTrue,
    );
    expect(synth.texts, ['A red kite.']);
    expect(synth.voices.last!['locale'], 'en-US');
    await audio.speak('A red kite.', {'locale': 'en-US', 'name': 'English'});
    expect(synth.texts, hasLength(1));
    settings.enabled = false;
    await tts
        .startNarration(['你好'], bookId: englishBook().pdfSha256, cache: cache)
        .completed;
    expect(synth.voices.last!['locale'], 'zh-CN');
    expect(synth.texts, ['A red kite.', '你好']);
    expect(
      await audio.speak('no voice', {'locale': 'zh-CN', 'name': 'Chinese'}),
      isFalse,
    );
    audio.dispose();
    tts.dispose();
  });
  test('停止准备中的英语示范会清除过期准备提示', () async {
    final players = <RecordingNarrationPlayer>[];
    final tts = TtsService(
      NarrationSettings(),
      flutterTts: NarrationEngine(),
      fileSynthesizer: _Synth(),
      narrationPlayerFactory: () {
        final player = RecordingNarrationPlayer();
        players.add(player);
        return player;
      },
    );
    final audio = EnglishAudio(
      bookId: englishBook().pdfSha256,
      tts: tts,
      cache: MemoryNarrationCache(),
      store: EnglishRecordingStore(directory: () async => root),
    );
    final pending = audio.speak('Hello there.', {
      'locale': 'en-US',
      'name': 'English',
    });
    while (players.isEmpty || players.single.audio.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(audio.message, '准备英语示范');

    await audio.stop();

    expect(await pending, isFalse);
    expect(audio.busy, isFalse);
    expect(audio.message, isEmpty);
    audio.dispose();
    tts.dispose();
  });
  test('录音拒绝可重试、未保存回听、保存幂等、停后台不会自动续录', () async {
    final recorders = <_Recorder>[], players = <RecordingNarrationPlayer>[];
    final tts = TtsService(NarrationSettings(), flutterTts: NarrationEngine());
    final store = EnglishRecordingStore(directory: () async => root);
    final audio = EnglishAudio(
      bookId: englishBook().pdfSha256,
      tts: tts,
      cache: MemoryNarrationCache(),
      store: store,
      recorderFactory: () {
        final r = _Recorder()..permitted = recorders.isNotEmpty;
        recorders.add(r);
        return r;
      },
      playerFactory: () {
        final p = RecordingNarrationPlayer()..automatic = true;
        players.add(p);
        return p;
      },
    );
    await audio.startRecording();
    expect(audio.recording, isFalse);
    expect(audio.message, contains('麦克风'));
    expect(recorders.first.disposed, isTrue);
    await audio.startRecording();
    expect(audio.recording, isTrue);
    recorders.last.stream.add(Uint8List(3200));
    await Future<void>.delayed(Duration.zero);
    await audio.finishRecording();
    expect(audio.hasUnsaved, isTrue);
    await audio.replay();
    expect(players.single.audio.single.bytes!.length, 3244);
    final id = await audio.saveRecording();
    expect(await audio.saveRecording(), id);
    expect(audio.hasUnsaved, isTrue);
    audio.acknowledgeRecording();
    expect(audio.hasUnsaved, isFalse);
    expect(
      await store.path(audio.profileId, id, bookId: audio.bookId),
      isNotNull,
    );
    await audio.startRecording();
    await audio.stop();
    expect(audio.recording, isFalse);
    expect(recorders.last.started, isFalse);
    await audio.replay(id: id);
    expect(
      players.last.audio.single.path,
      await store.path(audio.profileId, id, bookId: audio.bookId),
    );
    audio.dispose();
    tts.dispose();
  });
  test('权限窗口停止后，晚到授权不会启动麦克风', () async {
    final r = _Recorder()..permission = Completer<bool>();
    final tts = TtsService(NarrationSettings(), flutterTts: NarrationEngine());
    final audio = EnglishAudio(
      bookId: englishBook().pdfSha256,
      tts: tts,
      cache: MemoryNarrationCache(),
      store: EnglishRecordingStore(directory: () async => root),
      recorderFactory: () => r,
    );
    final pending = audio.startRecording();
    await Future<void>.delayed(Duration.zero);
    await audio.stop();
    r.permission!.complete(true);
    await pending;
    expect(r.started, isFalse);
    expect(audio.recording, isFalse);
    audio.dispose();
    tts.dispose();
  });

  test('录音流中断保留可见错误，释放麦克风后可重新录制', () async {
    final recorders = <_Recorder>[];
    final tts = TtsService(NarrationSettings(), flutterTts: NarrationEngine());
    final audio = EnglishAudio(
      bookId: englishBook().pdfSha256,
      tts: tts,
      cache: MemoryNarrationCache(),
      store: EnglishRecordingStore(directory: () async => root),
      recorderFactory: () {
        final recorder = _Recorder();
        recorders.add(recorder);
        return recorder;
      },
    );
    final interrupted = Completer<void>();
    var awaitingError = false;
    audio.addListener(() {
      if (awaitingError &&
          !audio.recording &&
          !audio.busy &&
          !interrupted.isCompleted) {
        interrupted.complete();
      }
    });
    try {
      await audio.startRecording();
      awaitingError = true;
      recorders.single.stream.addError(StateError('microphone interrupted'));
      await interrupted.future.timeout(const Duration(seconds: 2));
      expect(audio.message, '录音中断，请重试');
      expect(audio.hasUnsaved, isFalse);
      expect(recorders.single.disposed, isTrue);
      await audio.startRecording();
      expect(audio.recording, isTrue);
      expect(recorders.last.started, isTrue);
      expect(audio.message, '正在录音，最长一分钟');
    } finally {
      await audio.stop();
      audio.dispose();
      tts.dispose();
    }
  });

  test('结束录音失败也释放麦克风，不留下未完成片段', () async {
    final recorder = _Recorder()..stopError = StateError('stop failed');
    final tts = TtsService(NarrationSettings(), flutterTts: NarrationEngine());
    final audio = EnglishAudio(
      bookId: englishBook().pdfSha256,
      tts: tts,
      cache: MemoryNarrationCache(),
      store: EnglishRecordingStore(directory: () async => root),
      recorderFactory: () => recorder,
    );
    try {
      await audio.startRecording();
      recorder.stream.add(Uint8List(3200));
      await Future<void>.delayed(Duration.zero);
      await audio.finishRecording();
      expect(audio.message, '录音未完成，请重新录制');
      expect(audio.recording, isFalse);
      expect(audio.busy, isFalse);
      expect(recorder.disposed, isTrue);
      expect(recorder.started, isFalse);
      expect(audio.hasUnsaved, isFalse);
    } finally {
      await audio.stop();
      audio.dispose();
      tts.dispose();
    }
  });

  for (final (stage, fail) in [
    ('stop', false),
    ('stop', true),
    ('dispose', false),
  ]) {
    test('旧录音结束晚回调不取消新录音或覆盖状态（$stage，失败=$fail）', () async {
      final gate = Completer<void>();
      final first = _Recorder()
        ..stopping = stage == 'stop' ? gate : null
        ..releasing = stage == 'dispose' ? gate : null
        ..disposing = Completer<void>();
      final second = _Recorder();
      final recorders = [first, second].iterator;
      final tts = TtsService(
        NarrationSettings(),
        flutterTts: NarrationEngine(),
      );
      final store = EnglishRecordingStore(directory: () async => root);
      final audio = EnglishAudio(
        bookId: englishBook().pdfSha256,
        tts: tts,
        cache: MemoryNarrationCache(),
        store: store,
        recorderFactory: () {
          recorders.moveNext();
          return recorders.current;
        },
      );
      try {
        await audio.startRecording();
        final ending = audio.finishRecording();
        if (stage == 'dispose') await first.disposing!.future;
        final stopping = audio.stop();
        if (stage == 'stop') await stopping;
        await audio.startRecording();
        if (fail) {
          gate.completeError(StateError('old stop failed'));
        } else {
          gate.complete();
        }
        await ending;
        await stopping;
        expect(audio.recording, isTrue);
        expect(audio.message, '正在录音，最长一分钟');
        expect(second.stream.hasListener, isTrue);
        final pcm = Uint8List.fromList(List.filled(3200, 7));
        second.stream.add(pcm);
        await Future<void>.delayed(Duration.zero);
        await audio.finishRecording();
        final id = await audio.saveRecording();
        final path = await store.path(
          audio.profileId,
          id,
          bookId: audio.bookId,
        );
        expect((await File(path!).readAsBytes()).sublist(44), pcm);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await audio.stop();
        audio.dispose();
        tts.dispose();
      }
    });
  }
}
