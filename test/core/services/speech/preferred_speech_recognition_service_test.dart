import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:poemath/core/services/tencent/tencent_app_id_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../../helpers/tencent_realtime_socket.dart';

class _Settings extends Mock implements SettingsRepository {}

class _Recorder implements SpeechAudioRecorder {
  final _chunks = StreamController<Uint8List>.broadcast();
  int cancelCalls = 0;
  int startCalls = 0;

  void emit(Uint8List bytes) => _chunks.add(bytes);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async {
    startCalls++;
    return _chunks.stream;
  }

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
  const credentials = TencentAsrCredentials(
    secretId: 'AKIDEXAMPLE',
    secretKey: 'SECRETKEYEXAMPLE',
  );
  late _Settings settings;
  late _Recorder recorder;
  late TestTencentRealtimeSocket socket;
  late TencentAppIdClient appIdClient;
  late TencentAsrClient sentenceClient;
  late TencentRealtimeAsrClient realtimeClient;
  late PreferredSpeechRecognitionService service;
  late int sentenceRequests;
  late int realtimeRequests;
  late int appIdRequests;
  late Uri realtimeUri;
  String? appIdError;
  Object? socketError;
  bool expectClosedBeforeSentence = false;
  List<int>? uploadedPcm;

  setUp(() {
    settings = _Settings();
    when(() => settings.readTencentAsrCredentials()).thenAnswer(
      (_) async => credentials,
    );
    recorder = _Recorder();
    socket = TestTencentRealtimeSocket(text: '孩子正在放风筝');
    sentenceRequests = 0;
    realtimeRequests = 0;
    appIdRequests = 0;
    appIdError = null;
    socketError = null;
    uploadedPcm = null;
    expectClosedBeforeSentence = false;
    appIdClient = TencentAppIdClient(
      httpClient: MockClient((request) async {
        appIdRequests++;
        return http.Response(
          jsonEncode({
            'Response': appIdError == null
                ? {'AppId': 1250000000}
                : {
                    'Error': {'Code': appIdError},
                  },
          }),
          200,
        );
      }),
    );
    sentenceClient = TencentAsrClient(
      httpClient: MockClient((request) async {
        sentenceRequests++;
        if (expectClosedBeforeSentence) expect(socket.closed, isTrue);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        uploadedPcm = base64Decode(body['Data'] as String);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object>{
              'Response': <String, String>{'Result': '一句话回退结果'},
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    realtimeClient = TencentRealtimeAsrClient(
      appIdClient: appIdClient,
      connectSocket: (uri) async {
        realtimeRequests++;
        realtimeUri = uri;
        if (socketError != null) throw socketError!;
        return socket;
      },
    );
    service = PreferredSpeechRecognitionService(
      recorder: recorder,
      sentenceClient: sentenceClient,
      realtimeClient: realtimeClient,
      settingsRepository: settings,
    );
  });

  tearDown(() async {
    await service.dispose();
    realtimeClient.close();
    appIdClient.close();
    sentenceClient.close();
  });

  test('仅有 AK/SK 时自动获取 APPID，实时返回文字且不调用一句话', () async {
    await service.start();
    final partial = service.transcriptStream.first;
    socket.receiveText('孩子正在');
    expect(await partial, '孩子正在');
    expect(socket.endSent.isCompleted, isFalse);
    recorder.emit(Uint8List.fromList(List<int>.filled(32, 1)));
    final result = await service.stop();

    expect(result.text, '孩子正在放风筝');
    expect(result.mode, 'realtime');
    expect(result.usedFallback, isFalse);
    expect(service.usedFallback, isFalse);
    expect(appIdRequests, 1);
    expect(realtimeRequests, 1);
    expect(realtimeUri.path, '/asr/v2/1250000000');
    expect(sentenceRequests, 0);
  });

  test('实时连接明确返回 4004 时才复用 PCM 回退一句话', () async {
    socket.errorCode = 4004;
    await service.start();
    expect(service.recognitionMode, 'sentence');
    expect(service.usedFallback, isTrue);
    final pcm = List<int>.filled(32, 1);
    recorder.emit(Uint8List.fromList(pcm));
    final result = await service.stop();
    expect(result.text, '一句话回退结果');
    expect(result.mode, 'sentence');
    expect(result.usedFallback, isTrue);
    expect(realtimeRequests, 1);
    expect(sentenceRequests, 1);
    expect(uploadedPcm, pcm);
  });

  for (final code in [4002, 4003, 4005, 4006, 5001]) {
    test('实时错误 $code 即使含有 quota/limit 文案也不降级、不开始录音', () async {
      socket
        ..errorCode = code
        ..errorMessage = 'quota exhausted, concurrent limit exceeded';
      await expectLater(
        service.start(),
        throwsA(
          isA<TencentRealtimeAsrException>()
              .having((error) => error.code, 'code', code)
              .having(
                (error) => error.kind,
                'kind',
                isNot(TencentRealtimeErrorKind.quota),
              ),
        ),
      );
      expect(sentenceRequests, 0);
      expect(recorder.startCalls, 0);
      expect(service.isRecording, isFalse);
    });
  }

  test('实时连接网络失败不降级，错误提示不包含签名地址或密钥', () async {
    socketError = WebSocketException(
      'failed URL: wss://asr.cloud.tencent.com/?secretid=${credentials.secretId}&signature=${credentials.secretKey}',
    );
    await expectLater(
      service.start(),
      throwsA(
        isA<TencentRealtimeAsrException>()
            .having(
              (error) => error.kind,
              'kind',
              TencentRealtimeErrorKind.network,
            )
            .having(
              (error) => error.message,
              'message',
              allOf(
                isNot(contains(credentials.secretId)),
                isNot(contains(credentials.secretKey)),
              ),
            ),
      ),
    );
    expect(sentenceRequests, 0);
    expect(recorder.startCalls, 0);
  });

  test('自动查询 APPID 失败不降级为一句话', () async {
    appIdError = 'RequestLimitExceeded';
    await expectLater(
      service.start(),
      throwsA(isA<TencentRealtimeAsrException>()),
    );
    expect(appIdRequests, 1);
    expect(realtimeRequests, 0);
    expect(sentenceRequests, 0);
    expect(recorder.startCalls, 0);
  });

  test('实时识别没有有效文字时报告错误，仍不降级', () async {
    socket = TestTencentRealtimeSocket(text: '');
    await service.start();
    recorder.emit(Uint8List.fromList(List<int>.filled(32, 1)));
    await expectLater(
      service.stop(),
      throwsA(isA<TencentRealtimeAsrException>()),
    );
    expect(sentenceRequests, 0);
  });

  test('录音期间实时资源耗尽后停止上传，关闭实时连接并复用完整 PCM', () async {
    expectClosedBeforeSentence = true;
    await service.start();
    final pcm = List<int>.filled(32, 1);
    recorder.emit(Uint8List.fromList(pcm));
    await Future<void>.delayed(Duration.zero);
    socket.receiveError(4004);
    await Future<void>.delayed(Duration.zero);
    recorder.emit(Uint8List.fromList(pcm));
    final result = await service.stop();
    expect(result.usedFallback, isTrue);
    expect(result.mode, 'sentence');
    expect(uploadedPcm, [...pcm, ...pcm]);
    expect(sentenceRequests, 1);
    expect(socket.sentFrames, isEmpty);
  });

  test('实时收尾期间并发超限仍不调用一句话', () async {
    socket.finalErrorCode = 4006;
    await service.start();
    recorder.emit(Uint8List.fromList(List<int>.filled(32, 1)));
    await expectLater(
      service.stop(),
      throwsA(
        isA<TencentRealtimeAsrException>()
            .having((error) => error.code, 'code', 4006),
      ),
    );
    expect(sentenceRequests, 0);
  });
}
