// test/core/services/speech/tencent_speech_recognition_service_test.dart
//
// 纯腾讯云识别服务测试：录音状态机、凭据门禁、云端失败上抛。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

class FakeSpeechAudioRecorder implements SpeechAudioRecorder {
  FakeSpeechAudioRecorder({this.hasPermissionResult = true});

  bool hasPermissionResult;
  final List<Uint8List> chunks = <Uint8List>[];
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  void emitChunk(Uint8List bytes) {
    chunks.add(bytes);
    _controller.add(bytes);
  }

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<Stream<Uint8List>> startStream() async => _controller.stream;

  @override
  Future<void> stop() async {
    stopCalls++;
    _controller.close();
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

const credentials = TencentAsrCredentials(
  secretId: 'AKIDEXAMPLE',
  secretKey: 'SECRETKEYEXAMPLE',
);

TencentSpeechRecognitionService buildService({
  required FakeSpeechAudioRecorder recorder,
  required MockSettingsRepository repository,
  http.Client? httpClient,
}) {
  return TencentSpeechRecognitionService(
    recorder: recorder,
    tencentClient: TencentAsrClient(
      httpClient: httpClient ?? http.Client(),
    ),
    settingsRepository: repository,
  );
}

MockClient successClient({String result = '床前明月光'}) {
  return MockClient((request) async {
    return http.Response.bytes(
      utf8.encode(
        jsonEncode(<String, Object>{
          'Response': <String, Object>{'Result': result, 'RequestId': 'id'},
        }),
      ),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const TencentAsrCredentials(secretId: '', secretKey: ''),
    );
  });

  test('start → stop 返回腾讯云识别文本', () async {
    final recorder = FakeSpeechAudioRecorder();
    final repository = MockSettingsRepository();
    when(() => repository.readTencentAsrCredentials())
        .thenAnswer((_) async => credentials);

    Uint8List? uploaded;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      uploaded = base64Decode(body['Data'] as String);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, Object>{
            'Response': <String, Object>{'Result': '床前明月光'},
          }),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: client,
    );

    await service.start();
    final pcm = Uint8List.fromList(List.filled(320, 7));
    recorder.emitChunk(pcm);
    final result = await service.stop();

    expect(result.text, '床前明月光');
    expect(uploaded, orderedEquals(pcm));
    expect(recorder.stopCalls, 1);
    expect(service.isRecording, false);
  });

  test('未保存凭据时 stop 抛出鉴权异常并取消录音', () async {
    final recorder = FakeSpeechAudioRecorder();
    final repository = MockSettingsRepository();
    when(() => repository.readTencentAsrCredentials())
        .thenAnswer((_) async => null);

    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: successClient(),
    );

    await service.start();
    recorder.emitChunk(Uint8List(16));

    await expectLater(
      service.stop(),
      throwsA(
        isA<TencentAsrException>().having(
          (e) => e.kind,
          'kind',
          TencentAsrErrorKind.authentication,
        ),
      ),
    );
    expect(recorder.cancelCalls, greaterThan(0));
  });

  test('云端识别失败时异常上抛（不回退）', () async {
    final recorder = FakeSpeechAudioRecorder();
    final repository = MockSettingsRepository();
    when(() => repository.readTencentAsrCredentials())
        .thenAnswer((_) async => credentials);

    final failingClient = MockClient(
      (request) async => http.Response('server boom', 500),
    );
    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: failingClient,
    );

    await service.start();
    recorder.emitChunk(Uint8List(16));

    await expectLater(
      service.stop(),
      throwsA(isA<TencentAsrException>()),
    );
    expect(recorder.cancelCalls, greaterThan(0));
  });

  test('网络不可用时上抛网络异常', () async {
    final recorder = FakeSpeechAudioRecorder();
    final repository = MockSettingsRepository();
    when(() => repository.readTencentAsrCredentials())
        .thenAnswer((_) async => credentials);

    final networkClient = MockClient(
      (request) async => throw const SocketException('offline'),
    );
    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: networkClient,
    );

    await service.start();
    recorder.emitChunk(Uint8List(16));

    await expectLater(
      service.stop(),
      throwsA(
        isA<TencentAsrException>().having(
          (e) => e.kind,
          'kind',
          TencentAsrErrorKind.network,
        ),
      ),
    );
  });

  test('麦克风权限被拒绝时 start 抛出权限异常', () async {
    final recorder = FakeSpeechAudioRecorder(hasPermissionResult: false);
    final repository = MockSettingsRepository();

    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: successClient(),
    );

    await expectLater(
      service.start(),
      throwsA(isA<SpeechPermissionDeniedException>()),
    );
    expect(service.isRecording, false);
  });

  test('录音超过 60 秒上限时 stop 抛出录音失败', () async {
    final recorder = FakeSpeechAudioRecorder();
    final repository = MockSettingsRepository();
    when(() => repository.readTencentAsrCredentials())
        .thenAnswer((_) async => credentials);

    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: successClient(),
    );

    await service.start();
    recorder.emitChunk(Uint8List(TencentAsrClient.maxRawBytes + 2));
    recorder._controller.close();

    await expectLater(
      service.stop(),
      throwsA(isA<SpeechRecognitionException>()),
    );
  });

  test('未开始录音时 stop 抛出状态异常', () async {
    final service = buildService(
      recorder: FakeSpeechAudioRecorder(),
      repository: MockSettingsRepository(),
      httpClient: successClient(),
    );

    await expectLater(
      service.stop(),
      throwsA(isA<SpeechRecognitionException>()),
    );
  });

  test('cancel 清理录音状态且不再上报音频', () async {
    final recorder = FakeSpeechAudioRecorder();
    final repository = MockSettingsRepository();
    final service = buildService(
      recorder: recorder,
      repository: repository,
      httpClient: successClient(),
    );

    await service.start();
    await service.cancel();

    expect(service.isRecording, false);
    expect(recorder.cancelCalls, 1);
    await expectLater(
      service.stop(),
      throwsA(isA<SpeechRecognitionException>()),
    );
  });

  test('重复 start 抛出录音中异常', () async {
    final recorder = FakeSpeechAudioRecorder();
    final service = buildService(
      recorder: recorder,
      repository: MockSettingsRepository(),
      httpClient: successClient(),
    );

    await service.start();
    await expectLater(
      service.start(),
      throwsA(isA<SpeechRecognitionException>()),
    );
    await service.cancel();
  });
}
