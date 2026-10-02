// test/core/services/tts_service_cloud_test.dart
//
// 云端 TTS 行为测试：云优先路由、逐行合成、回退、缓存与中断。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts/tencent_tts_client.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

final class _FakeCloudAudioPlayer implements CloudAudioPlayer {
  _FakeCloudAudioPlayer({this.events, this.holdPlayback = false});

  final List<String>? events;
  final List<Uint8List> played = <Uint8List>[];
  final List<Completer<void>> _gates = <Completer<void>>[];
  int stopCalls = 0;
  bool holdPlayback = false;

  @override
  Future<void> play(Uint8List bytes) async {
    played.add(bytes);
    events?.add('play');
    if (!holdPlayback) return;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

class _FakeFlutterTts extends Fake implements FlutterTts {
  final List<String> spokenTexts = <String>[];

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  void setCancelHandler(VoidCallback callback) {}

  @override
  void setErrorHandler(ErrorHandler handler) {}

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spokenTexts.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

const _credentials = TencentAsrCredentials(
  secretId: 'AKIDEXAMPLE',
  secretKey: 'SECRETKEYEXAMPLE',
);

const _verifiedSettings = SpeechRecognitionSettingsState(
  hasCredentials: true,
  isVerified: true,
);

const _unverifiedSettings = SpeechRecognitionSettingsState(
  hasCredentials: false,
  isVerified: false,
);

final _audioBytes = Uint8List.fromList(List<int>.filled(16, 3));

// dart 不支持闭包捕获计数引用，用可变包装。
class _RequestCounter {
  int value = 0;
}

TencentTtsClient _client(
  _RequestCounter counter, {
  TencentTtsErrorKind? failKind,
}) {
  return TencentTtsClient(
    httpClient: MockClient((_) async {
      counter.value++;
      if (failKind != null) {
        return http.Response(
          jsonEncode(<String, Object>{
            'Response': <String, Object>{
              'Error': <String, Object>{
                'Code': switch (failKind) {
                  TencentTtsErrorKind.quota =>
                    'UnsupportedOperation.NoFreeAccount',
                  TencentTtsErrorKind.authentication =>
                    'AuthFailure.SignatureFailure',
                  _ => 'InternalError',
                },
                'Message': 'server details',
              },
            },
          }),
          400,
        );
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, Object>{
            'Response': <String, Object>{
              'Audio': base64Encode(_audioBytes),
            },
          }),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

SettingsRepository _stubSettings({
  required bool cloudEnabled,
  bool verified = true,
}) {
  final settings = _MockSettingsRepository();
  when(() => settings.ttsCloudEnabled).thenReturn(cloudEnabled);
  when(() => settings.ttsCloudVoiceType).thenReturn(101001);
  when(() => settings.ttsSpeed).thenReturn(0.5);
  when(() => settings.ttsVoice).thenReturn(null);
  when(() => settings.loadSpeechRecognitionSettings()).thenAnswer(
    (_) async => verified ? _verifiedSettings : _unverifiedSettings,
  );
  when(() => settings.readTencentAsrCredentials()).thenAnswer(
    (_) async => verified ? _credentials : null,
  );
  return settings;
}

void main() {
  test('开关关闭时走系统引擎且不发起云请求', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final player = _FakeCloudAudioPlayer();
    final service = TtsService(
      _stubSettings(cloudEnabled: false),
      flutterTts: tts,
      cloudClient: _client(counter),
      cloudPlayer: player,
    );

    await service.speakLines(['床前明月光', '疑是地上霜']);

    expect(counter.value, 0);
    expect(player.played, isEmpty);
    expect(tts.spokenTexts, ['床前明月光', '疑是地上霜']);
  });

  test('凭据未验证时走系统引擎且不发起云请求', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final service = TtsService(
      _stubSettings(cloudEnabled: true, verified: false),
      flutterTts: tts,
      cloudClient: _client(counter),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speak('床前明月光');

    expect(counter.value, 0);
    expect(tts.spokenTexts, ['床前明月光']);
  });

  test('云端逐行合成播放且回调时序正确', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final events = <String>[];
    final player = _FakeCloudAudioPlayer(events: events);
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter),
      cloudPlayer: player,
    );
    final lineStarts = <int>[];

    await service.speakLines(
      ['床前明月光', '疑是地上霜', '举头望明月'],
      onLineStart: lineStarts.add,
    );

    expect(lineStarts, [0, 1, 2]);
    expect(player.played.length, 3);
    expect(tts.spokenTexts, isEmpty);
    // 播放交错：每行回调后紧跟一次播放，无系统朗读。
    expect(events, ['play', 'play', 'play']);
    expect(counter.value, 3);
  });

  test('单行网络失败回退系统引擎完成当句', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter, failKind: TencentTtsErrorKind.network),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speak('床前明月光');

    expect(counter.value, 1);
    expect(tts.spokenTexts, ['床前明月光']);
  });

  test('额度类错误整段降级且只请求一次', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter, failKind: TencentTtsErrorKind.quota),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speakLines(['床前明月光', '疑是地上霜', '举头望明月']);

    expect(counter.value, 1);
    expect(tts.spokenTexts, ['床前明月光', '疑是地上霜', '举头望明月']);
  });

  test('同一句重复朗读命中缓存不重复请求', () async {
    final counter = _RequestCounter();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient: _client(counter),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speak('床前明月光');
    await service.speak('床前明月光');

    expect(counter.value, 1);
  });

  test('stop 中断挂起的云端播放且不触发完成回调', () async {
    final counter = _RequestCounter();
    final player = _FakeCloudAudioPlayer(holdPlayback: true);
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient: _client(counter),
      cloudPlayer: player,
    );

    var completed = false;
    final task = service.speakLines(
      ['床前明月光', '疑是地上霜'],
      onComplete: () => completed = true,
    );
    // 等第一行播放挂起。
    await Future<void>.delayed(Duration.zero);
    expect(player.played.length, 1);

    await service.stop();
    await task;

    expect(player.played.length, 1);
    expect(player.stopCalls, greaterThan(0));
    expect(completed, isFalse);
    expect(service.isSpeaking, isFalse);
  });

  test('previewCloud 云端失败上抛具体原因', () async {
    final counter = _RequestCounter();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient: _client(counter, failKind: TencentTtsErrorKind.quota),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await expectLater(
      service.previewCloud('床前明月光'),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.quota,
        ),
      ),
    );
  });

  test('previewCloud 未验证凭据时抛出引导配置异常', () async {
    final counter = _RequestCounter();
    final service = TtsService(
      _stubSettings(cloudEnabled: true, verified: false),
      flutterTts: _FakeFlutterTts(),
      cloudClient: _client(counter),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await expectLater(
      service.previewCloud('床前明月光'),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.authentication,
        ),
      ),
    );
    expect(counter.value, 0);
  });
}
