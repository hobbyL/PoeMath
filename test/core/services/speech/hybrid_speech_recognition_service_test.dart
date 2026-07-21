import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/hybrid_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/local_speech_recognizer.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../../helpers/hive_test_helper.dart';

final class _MemoryCredentialStore extends SecureCredentialStore {
  TencentAsrCredentials? credentials;

  @override
  Future<void> saveTencentAsrCredentials(
    TencentAsrCredentials value,
  ) async {
    credentials = value;
  }

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async {
    return credentials;
  }

  @override
  Future<void> deleteTencentAsrCredentials() async {
    credentials = null;
  }
}

final class _FakeRecorder implements SpeechAudioRecorder {
  _FakeRecorder(this.bytes);

  final Uint8List bytes;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async =>
      Stream<Uint8List>.value(bytes);

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FakeLocalRecognizer implements LocalSpeechRecognizer {
  _FakeLocalRecognizer({this.acceptGate});

  final Completer<void>? acceptGate;
  bool started = false;
  bool cancelled = false;
  bool disposed = false;
  int acceptedChunks = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<String> acceptPcm(Uint8List bytes) async {
    acceptedChunks++;
    await acceptGate?.future;
    return '本地实时结果';
  }

  @override
  Future<String> finish() async => '本地最终结果';

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late SettingsRepository settings;
  late _MemoryCredentialStore credentialStore;

  setUp(() async {
    await setUpHiveForTesting();
    credentialStore = _MemoryCredentialStore();
    settings = SettingsRepository(credentialStore: credentialStore);
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  Future<void> enableCloud() async {
    const credentials =
        TencentAsrCredentials(secretId: 'AKID', secretKey: 'SK');
    await settings.saveTencentAsrCredentials(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
    );
    await settings.markTencentAsrCredentialsVerified(
      testedCredentials: credentials,
    );
    await settings.setTencentAsrHighAccuracyEnabled(true);
  }

  HybridSpeechRecognitionService createService({
    required SpeechAudioRecorder recorder,
    required LocalSpeechRecognizer local,
    required http.Client client,
  }) {
    return HybridSpeechRecognitionService(
      recorder: recorder,
      localRecognizer: local,
      tencentClient: TencentAsrClient(httpClient: client),
      settingsRepository: settings,
    );
  }

  test('始终先完成本地识别，云端成功时覆盖最终文字', () async {
    await enableCloud();
    final recorder = _FakeRecorder(Uint8List.fromList(<int>[0, 0, 1, 0]));
    final local = _FakeLocalRecognizer();
    var requests = 0;
    final service = createService(
      recorder: recorder,
      local: local,
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '{"Response":{"Result":"云端结果","RequestId":"id"}}',
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    await service.start();
    final result = await service.stop();

    expect(local.started, isTrue);
    expect(local.acceptedChunks, 1);
    expect(result.localText, '本地最终结果');
    expect(result.text, '云端结果');
    expect(result.usedTencentCloud, isTrue);
    expect(requests, 1);
    await service.dispose();
  });

  test('腾讯云失败时回退本地结果且不抛出', () async {
    await enableCloud();
    final service = createService(
      recorder: _FakeRecorder(Uint8List.fromList(<int>[0, 0])),
      local: _FakeLocalRecognizer(),
      client: MockClient((_) async {
        return http.Response(
          '{"Response":{"Error":{"Code":"AuthFailure","Message":"no"}}}',
          401,
        );
      }),
    );

    await service.start();
    final result = await service.stop();

    expect(result.text, '本地最终结果');
    expect(result.source, SpeechRecognitionSource.local);
    expect(result.fellBackFromCloud, isTrue);
    await service.dispose();
  });

  test('高精度未开启时不发起云端请求', () async {
    var requests = 0;
    final service = createService(
      recorder: _FakeRecorder(Uint8List.fromList(<int>[0, 0])),
      local: _FakeLocalRecognizer(),
      client: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
    );

    await service.start();
    final result = await service.stop();

    expect(result.text, '本地最终结果');
    expect(result.source, SpeechRecognitionSource.local);
    expect(requests, 0);
    await service.dispose();
  });

  test('云端请求丢弃最后一个不完整 PCM 字节', () async {
    await enableCloud();
    Map<String, dynamic>? requestBody;
    final service = createService(
      recorder: _FakeRecorder(Uint8List.fromList(<int>[0, 0, 1])),
      local: _FakeLocalRecognizer(),
      client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"Response":{"Result":"云端结果","RequestId":"id"}}',
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    await service.start();
    final result = await service.stop();

    expect(result.usedTencentCloud, isTrue);
    expect(requestBody?['DataLen'], 2);
    expect(base64Decode(requestBody?['Data'] as String), hasLength(2));
    await service.dispose();
  });

  test('取消录音会等待在途本地识别完成后再释放流', () async {
    final acceptGate = Completer<void>();
    final local = _FakeLocalRecognizer(acceptGate: acceptGate);
    final service = createService(
      recorder: _FakeRecorder(Uint8List.fromList(<int>[0, 0])),
      local: local,
      client: MockClient((_) async => http.Response('', 500)),
    );

    await service.start();
    while (local.acceptedChunks == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final cancelFuture = service.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(local.cancelled, isFalse);
    acceptGate.complete();
    await cancelFuture;
    expect(local.cancelled, isTrue);

    await service.dispose();
  });
}
