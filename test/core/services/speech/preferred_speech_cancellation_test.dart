import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_realtime_asr_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';

class _Settings extends Mock implements SettingsRepository {}

class _LocalHttp extends HttpOverrides {}

class _Recorder implements SpeechAudioRecorder {
  StreamController<Uint8List>? current;
  int starts = 0;
  int cancellations = 0;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<Stream<Uint8List>> startStream() async {
    starts++;
    current = StreamController<Uint8List>.broadcast();
    return current!.stream;
  }

  void emit() => current!.add(Uint8List.fromList(List.filled(32, 1)));
  @override
  Future<void> stop() async => current?.close();
  @override
  Future<void> cancel() async {
    cancellations++;
    if (current != null && !current!.isClosed) await current!.close();
  }

  @override
  Future<void> dispose() async {
    if (current != null && !current!.isClosed) await current!.close();
  }
}

class _Usage extends CloudUsageService {
  Completer<void>? gate;
  final entered = Completer<void>();
  Future<void>? pending;
  @override
  Future<void> reserve(CloudUsageKind kind, {void Function()? check}) {
    final held = gate;
    gate = null;
    return pending = () async {
      check?.call();
      if (held != null) {
        entered.complete();
        await held.future;
      }
      check?.call();
      await super.reserve(kind, check: check);
    }();
  }
}

class _Socket extends Fake implements WebSocket {
  final incoming = StreamController<Object?>();
  final endSent = Completer<void>();
  Completer<void>? closeGate;
  int? errorCode;
  bool holdResult = false;
  bool closed = false;
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = incoming.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    incoming.add(
      jsonEncode({
        'code': errorCode ?? 0,
        'voice_id': 'synthetic-voice',
      }),
    );
    return subscription;
  }

  @override
  void add(dynamic data) {
    if (data is String && data.contains('"end"')) {
      if (!endSent.isCompleted) endSent.complete();
      if (!holdResult) {
        incoming.add(
          jsonEncode({
            'code': 0,
            'result': {'index': 0, 'voice_text_str': '实时新结果', 'slice_type': 2},
            'final': 1,
          }),
        );
      }
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await closeGate?.future;
    closed = true;
    await incoming.close();
  }
}

class _ProbeClient extends http.BaseClient {
  _ProbeClient(this.inner);
  final http.Client inner;
  final aborted = Completer<void>();
  final wireAborted = Completer<void>();
  int sends = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    if (sends == 1) {
      (request as http.AbortableRequest).abortTrigger!.then((_) {
        if (!aborted.isCompleted) aborted.complete();
      });
    }
    try {
      return await inner.send(request);
    } on http.RequestAbortedException {
      if (!wireAborted.isCompleted) wireAborted.complete();
      rethrow;
    }
  }

  @override
  void close() => inner.close();
}

const _credentials =
    TencentAsrCredentials(secretId: 'synthetic-id', secretKey: 'synthetic-key');
const _realtimeCredentials = TencentAsrCredentials(
  secretId: 'synthetic-id',
  secretKey: 'synthetic-key',
  appId: '100000001',
);

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  late _Recorder recorder;
  late _Settings settings;
  late CloudUsageService usage;
  late int sends;

  PreferredSpeechRecognitionService build({
    TencentRealtimeAsrClient? realtime,
    http.Client? transport,
    Uri? endpoint,
  }) {
    final sentence = TencentAsrClient(
      usage: usage,
      endpoint: endpoint,
      httpClient: transport ??
          MockClient((_) async {
            sends++;
            return http.Response(
              '{"Response":{"Result":"正常新结果"}}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
    );
    final service = PreferredSpeechRecognitionService(
      recorder: recorder,
      sentenceClient: sentence,
      realtimeClient: realtime ?? TencentRealtimeAsrClient(usage: usage),
      settingsRepository: settings,
    );
    addTearDown(() async {
      await service.dispose();
      sentence.close();
    });
    return service;
  }

  setUp(() {
    recorder = _Recorder();
    settings = _Settings();
    usage = CloudUsageService();
    sends = 0;
    when(() => settings.readTencentAsrCredentials())
        .thenAnswer((_) async => _credentials);
  });

  Future<void> cancelled(Future<SpeechRecognitionResult> operation) =>
      expectLater(operation, throwsA(isA<SpeechRecognitionCancelled>()));

  test('凭据读取期间取消立即结束识别，晚到凭据不上传且不影响新录音', () async {
    final entered = Completer<void>();
    final credentials = Completer<TencentAsrCredentials?>();
    var reads = 0;
    when(() => settings.readTencentAsrCredentials()).thenAnswer((_) {
      if (++reads == 2) {
        entered.complete();
        return credentials.future;
      }
      return Future.value(_credentials);
    });
    final service = build();
    await service.start();
    recorder.emit();
    final failure = cancelled(service.stop());
    await entered.future;
    await service.cancel();
    await failure.timeout(const Duration(seconds: 2));
    await service.start();
    credentials.complete(_credentials);
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
    expect(usage.used(CloudUsageKind.asr), 0);
    expect(service.isRecording, isTrue);
    expect(service.takeLastAudio(), isNull);
  });

  test('用量预留等待期间取消，晚到预留不计数、不发送', () async {
    final heldUsage = _Usage();
    final gate = Completer<void>();
    heldUsage.gate = gate;
    usage = heldUsage;
    final service = build();
    await service.start();
    recorder.emit();
    final failure = cancelled(service.stop());
    await heldUsage.entered.future;
    await service.cancel();
    await failure.timeout(const Duration(seconds: 2));
    gate.complete();
    await expectLater(
      heldUsage.pending,
      throwsA(isA<SpeechRecognitionCancelled>()),
    );
    expect(sends, 0);
    expect(usage.used(CloudUsageKind.asr), 0);
  });

  test('取消准备期释放状态，旧凭据晚到不能启动或清理新录音', () async {
    final credentials = Completer<TencentAsrCredentials?>();
    var reads = 0;
    when(() => settings.readTencentAsrCredentials()).thenAnswer(
      (_) => ++reads == 1 ? credentials.future : Future.value(_credentials),
    );
    final service = build();
    final old = expectLater(
      service.start(),
      throwsA(isA<SpeechRecognitionCancelled>()),
    );
    await service.cancel();
    await old;
    await service.start();
    credentials.complete(_credentials);
    await Future<void>.delayed(Duration.zero);
    expect(recorder.starts, 1);
    expect(service.isRecording, isTrue);
  });

  test('真实 IOClient 在途请求被 abort，同一连接池仍可完成下一次识别', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final entered = Completer<void>();
    var requests = 0;
    final subscription = server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(base64Decode(body['Data'] as String), List.filled(32, 1));
      requests++;
      if (requests == 1) {
        entered.complete();
        return; // 不发送响应头，只有底层 abort 才能结束 IOClient.send。
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"Response":{"Result":"正常新结果"}}');
      await request.response.close();
    });
    final transport = _ProbeClient(
      HttpOverrides.runWithHttpOverrides(IOClient.new, _LocalHttp()),
    );
    addTearDown(() async {
      transport.close();
      await subscription.cancel();
      await server.close(force: true);
    });
    final service = build(
      transport: transport,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    await service.start();
    recorder.emit();
    final failure = cancelled(service.stop());
    await entered.future;
    await service.cancel();
    await failure.timeout(const Duration(seconds: 2));
    await transport.aborted.future.timeout(const Duration(seconds: 2));
    await transport.wireAborted.future.timeout(const Duration(seconds: 2));
    await service.start();
    recorder.emit();
    expect((await service.stop()).text, '正常新结果');
    expect(transport.sends, 2);
    expect(usage.used(CloudUsageKind.asr), 2);
  });

  test('响应正文等待期间取消底层订阅，旧结果不作为成功返回', () async {
    final entered = Completer<void>();
    final bodyCancelled = Completer<void>();
    final body =
        StreamController<List<int>>(onCancel: () => bodyCancelled.complete());
    final transport = _StreamClient((request) async {
      entered.complete();
      return http.StreamedResponse(body.stream, 200);
    });
    addTearDown(body.close);
    final service = build(transport: transport);
    await service.start();
    recorder.emit();
    final failure = cancelled(service.stop());
    await entered.future;
    body.add(utf8.encode('{"Response":'));
    await Future<void>.delayed(Duration.zero);
    await service.cancel();
    await failure;
    await bodyCancelled.future;
    expect(service.takeLastAudio(), isNull);
  });

  test('旧实时收尾等待关闭时，新实时连接和录音保持独立', () async {
    when(() => settings.readTencentAsrCredentials())
        .thenAnswer((_) async => _realtimeCredentials);
    final closeGate = Completer<void>();
    final oldSocket = _Socket()
      ..holdResult = true
      ..closeGate = closeGate;
    final newSocket = _Socket();
    final sockets = [oldSocket, newSocket];
    final service = build(
      realtime: TencentRealtimeAsrClient(
        usage: usage,
        connectSocket: (_) async => sockets.removeAt(0),
      ),
    );
    addTearDown(() {
      if (!closeGate.isCompleted) closeGate.complete();
    });
    await service.start();
    recorder.emit();
    final oldFailure = cancelled(service.stop());
    await oldSocket.endSent.future;
    await service.start();
    closeGate.complete();
    await oldFailure;
    expect(oldSocket.closed, isTrue);
    expect(newSocket.closed, isFalse);
    expect(service.isRecording, isTrue);
    recorder.emit();
    final result = await service.stop();
    expect(result.text, '实时新结果');
    expect(result.mode, 'realtime');
    expect(sends, 0);
    expect(usage.used(CloudUsageKind.asr), 2);
  });

  test('腾讯实时额度耗尽才回退一句话，共用一次本地用量', () async {
    when(() => settings.readTencentAsrCredentials())
        .thenAnswer((_) async => _realtimeCredentials);
    final socket = _Socket()..errorCode = 4004;
    final service = build(
      realtime: TencentRealtimeAsrClient(
        usage: usage,
        connectSocket: (_) async => socket,
      ),
    );
    await service.start();
    recorder.emit();
    final result = await service.stop();
    expect(result.text, '正常新结果');
    expect(result.usedFallback, isTrue);
    expect(sends, 1);
    expect(usage.used(CloudUsageKind.asr), 1);
  });

  test('本地额度耗尽不会通过实时回退绕过保护', () async {
    when(() => settings.readTencentAsrCredentials())
        .thenAnswer((_) async => _realtimeCredentials);
    await usage.reserve(CloudUsageKind.asr);
    // 将临时测试库中的每日额度设为一次。
    await unlockParentForTesting();
    addTearDown(lockParentForTesting);
    await usage.setLimit(CloudUsageKind.asr, 1);
    var connections = 0;
    final service = build(
      realtime: TencentRealtimeAsrClient(
        usage: usage,
        connectSocket: (_) async {
          connections++;
          return _Socket();
        },
      ),
    );
    await expectLater(
      service.start(),
      throwsA(
        isA<TencentRealtimeAsrException>().having((e) => e.code, 'code', -1),
      ),
    );
    expect(connections, 0);
    expect(recorder.starts, 0);
    expect(sends, 0);
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
