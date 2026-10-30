import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_realtime_asr_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

class _Settings extends Mock implements SettingsRepository {}

class _Recorder implements SpeechAudioRecorder {
  final _chunks = StreamController<Uint8List>();
  int cancelCalls = 0;

  void emit(Uint8List bytes) => _chunks.add(bytes);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async => _chunks.stream;

  @override
  Future<void> stop() async => _chunks.close();

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {
    if (!_chunks.isClosed) await _chunks.close();
  }
}

void main() {
  test('未配置 APPID 时继续使用一句话识别且不标记为回退', () async {
    final settings = _Settings();
    when(() => settings.readTencentAsrCredentials()).thenAnswer(
      (_) async => const TencentAsrCredentials(
        secretId: 'AKID',
        secretKey: 'SECRET',
      ),
    );
    final recorder = _Recorder();
    final sentenceClient = TencentAsrClient(
      httpClient: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object>{
              'Response': <String, String>{'Result': '孩子正在放风筝'},
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final service = PreferredSpeechRecognitionService(
      recorder: recorder,
      sentenceClient: sentenceClient,
      realtimeClient: TencentRealtimeAsrClient(),
      settingsRepository: settings,
    );

    addTearDown(service.dispose);
    await service.start();
    recorder.emit(Uint8List.fromList(List<int>.filled(32, 1)));
    final result = await service.stop();

    expect(result.text, '孩子正在放风筝');
    expect(result.mode, 'sentence');
    expect(result.usedFallback, isFalse);
    expect(service.usedFallback, isFalse);
  });
}
