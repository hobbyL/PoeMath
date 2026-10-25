import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

class NarrationSettings extends Fake implements SettingsRepository {
  bool enabled = false;
  bool verified = true;
  double speed = 0.5;
  Map<String, String>? voice;
  @override
  bool get ttsCloudEnabled => enabled;
  @override
  double get ttsSpeed => speed;
  @override
  Map<String, String>? get ttsVoice => voice;
  @override
  String get ttsCloudVoice => kDefaultWorkerVoice;
  @override
  String get ttsCloudStyle => 'poetry-reading';
  @override
  Future<bool> isWorkerTtsVerified() async => verified;
  @override
  Future<WorkerTtsConfig?> readWorkerTtsConfig() async => WorkerTtsConfig(
        base: Uri.parse('https://example.org'),
        apiKey: 'test-key',
      );
}

class NarrationEngine extends Fake implements FlutterTts {
  final spoken = <String>[];
  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> setVoice(Map<String, String> voice) async => 1;
  @override
  Future<dynamic> awaitSpeakCompletion(bool value) async => 1;
  @override
  void setCancelHandler(void Function() callback) {}
  @override
  void setErrorHandler(ErrorHandler handler) {}
  @override
  Future<dynamic> stop() async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }
}

class NarrationSynth implements SystemTtsFileSynthesizer {
  String identity = 'engine-v1|zh-CN';
  final texts = <String>[];
  final cancelled = <int>[];
  Future<Uint8List> Function(String text)? generate;
  @override
  Future<String> describeVoice(
          Map<String, String>? voice, double speed,) async =>
      identity;
  @override
  Future<Uint8List> synthesize({
    required int sessionId,
    required String text,
    required Map<String, String>? voice,
    required double speed,
  }) async {
    texts.add(text);
    return generate == null
        ? Uint8List.fromList([texts.length])
        : await generate!(text);
  }

  @override
  Future<void> cancelSession(int sessionId) async {
    cancelled.add(sessionId);
  }

  @override
  Future<void> dispose() async {}
}

class RecordingNarrationPlayer implements NarrationPlayer {
  bool automatic = false;
  final audio = <NarrationAudio>[];
  final starts = <void Function()>[];
  final ends = <Completer<void>>[];
  int pauses = 0;
  int resumes = 0;
  bool disposed = false;
  @override
  Future<void> play(NarrationAudio clip,
      {required void Function() onStarted,}) async {
    audio.add(clip);
    starts.add(onStarted);
    final end = Completer<void>();
    ends.add(end);
    if (automatic) {
      onStarted();
      end.complete();
    }
    await end.future;
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
    for (final end in ends) {
      if (!end.isCompleted) end.complete();
    }
  }
}

class MemoryNarrationCache extends NarrationAudioCache {
  final entries = <String, Uint8List>{};
  @override
  Future<NarrationAudio?> read(String book, String key, String format) async {
    final bytes = entries['$book|$key|$format'];
    return bytes == null ? null : NarrationAudio(bytes: bytes, format: format);
  }

  @override
  Future<NarrationAudio> store(
    String book,
    String key,
    String format,
    Uint8List bytes, {
    required int revision,
    required bool Function() isCurrent,
  }) async {
    if (isCurrent() && revision == this.revision(book)) {
      entries['$book|$key|$format'] = bytes;
    }
    return NarrationAudio(bytes: bytes, format: format);
  }
}

class NarrationUsage extends Fake implements CloudUsageService {
  bool exhausted = false;
  int reservations = 0;
  @override
  Future<void> reserve(CloudUsageKind kind) async {
    reservations++;
    if (exhausted) throw CloudQuotaExceededException(kind);
  }
}

class NarrationCloud {
  final texts = <String>[];
  final usage = NarrationUsage();
  Future<Uint8List> Function(String text)? generate;
  bool unauthorized = false;
  late final client = WorkerTtsClient(
    usage: usage,
    httpClient: MockClient((request) async {
      final text = (jsonDecode(request.body) as Map)['text'] as String;
      texts.add(text);
      if (unauthorized) return http.Response('', 401);
      final bytes = generate == null ? Uint8List(16) : await generate!(text);
      return http.Response.bytes(bytes, 200,
          headers: {'content-type': 'audio/mpeg'},);
    }),
  );
}

Future<void> flushNarration() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.value();
  }
}
