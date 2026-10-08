// test/core/services/tts_service_cloud_test.dart
//
// 云端 TTS 行为测试（自建 Worker）：云优先路由、逐行合成、回退、缓存与中断。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
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

  /// 播放抛错（模拟底层音频失败）：
  /// [throwOnPlay] 所有播放均抛错；[throwOnPlayLimit] 仅前 N 次抛错。
  bool throwOnPlay = false;
  int throwOnPlayLimit = 0;
  int playFailures = 0;

  @override
  Future<void> play(Uint8List bytes) async {
    played.add(bytes);
    events?.add('play');
    if (throwOnPlay || playFailures < throwOnPlayLimit) {
      playFailures++;
      throw Exception('audioplayers failure');
    }
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

final _base = Uri.parse('https://tts.cloudm.cc');
final _config = WorkerTtsConfig(
  base: _base,
  apiKey: 'worker-secret-key-example',
);

final _audioBytes = Uint8List.fromList(List<int>.filled(16, 3));

// dart 不支持闭包捕获计数引用，用可变包装。
class _RequestCounter {
  int value = 0;
}

/// 脚本化 HTTP 客户端：记录请求体，按预设返回结果或抛出网络异常。
class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient({
    required this.counter,
    this.failKind,
    this.failFirstOnly = false,
    this.synthGate,
  });

  final _RequestCounter counter;
  final WorkerTtsErrorKind? failKind;
  final bool failFirstOnly;

  /// 合成闸门：非空时每个请求先挂起直到闸门完成（模拟合成 await 窗口）。
  final Completer<void>? synthGate;

  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  bool get _shouldFail {
    final kind = failKind;
    if (kind == null) return false;
    return !(failFirstOnly && counter.value > 1);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final gate = synthGate;
    if (gate != null) await gate.future;
    counter.value++;
    final body = await request.finalize().bytesToString();
    bodies.add(jsonDecode(body) as Map<String, dynamic>);

    if (_shouldFail) {
      switch (failKind!) {
        case WorkerTtsErrorKind.authentication:
          return _jsonResponse(
            jsonEncode(<String, Object>{'error': '未授权访问: 无效的 API 密钥'}),
            401,
          );
        case WorkerTtsErrorKind.request:
          return _jsonResponse(
            jsonEncode(<String, Object>{'error': '必须提供文本参数'}),
            400,
          );
        case WorkerTtsErrorKind.network:
          throw const SocketException('offline');
        case WorkerTtsErrorKind.response:
          return _plainResponse('server exploded', 500);
      }
    }
    return http.StreamedResponse(
      http.ByteStream.fromBytes(_audioBytes),
      200,
      headers: const {'content-type': 'audio/mpeg'},
    );
  }

  static http.StreamedResponse _jsonResponse(String body, int status) {
    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static http.StreamedResponse _plainResponse(String body, int status) {
    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(body)),
      status,
    );
  }
}

WorkerTtsClient _client(
  _RequestCounter counter, {
  WorkerTtsErrorKind? failKind,
  bool failFirstOnly = false,
  Completer<void>? synthGate,
}) {
  return WorkerTtsClient(
    httpClient: _ScriptedHttpClient(
      counter: counter,
      failKind: failKind,
      failFirstOnly: failFirstOnly,
      synthGate: synthGate,
    ),
  );
}

SettingsRepository _stubSettings({
  required bool cloudEnabled,
  bool verified = true,
}) {
  final settings = _MockSettingsRepository();
  when(() => settings.ttsCloudEnabled).thenReturn(cloudEnabled);
  when(() => settings.ttsCloudVoice).thenReturn(kDefaultWorkerVoice);
  when(() => settings.ttsCloudStyle).thenReturn('poetry-reading');
  when(() => settings.ttsSpeed).thenReturn(0.5);
  when(() => settings.ttsVoice).thenReturn(null);
  when(() => settings.isWorkerTtsVerified()).thenAnswer((_) async => verified);
  when(() => settings.readWorkerTtsConfig())
      .thenAnswer((_) async => verified ? _config : null);
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

  test('服务未验证时走系统引擎且不发起云请求', () async {
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
      onLineStart: (index, _) => lineStarts.add(index),
    );

    expect(lineStarts, [0, 1, 2]);
    expect(player.played.length, 3);
    expect(tts.spokenTexts, isEmpty);
    // 播放交错：每行回调后紧跟一次播放，无系统朗读。
    expect(events, ['play', 'play', 'play']);
    expect(counter.value, 3);
  });

  test('云端路径 onReady 在首段播放发起前触发一次', () async {
    final counter = _RequestCounter();
    final player = _FakeCloudAudioPlayer(holdPlayback: true);
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient: _client(counter),
      cloudPlayer: player,
    );
    var readyCount = 0;

    final task = service.speakLines(
      ['床前明月光', '疑是地上霜'],
      onReady: (_) => readyCount++,
    );
    // 等第一行播放挂起。
    await Future<void>.delayed(Duration.zero);

    // 首段 play 仍挂起（未播完），onReady 已在播放动作发起前触发——
    // 音频出声期间遮罩即解除（旧缺陷：play 播完才触发，遮罩锁死）。
    expect(player.played.length, 1);
    expect(readyCount, 1);
    expect(service.isSpeaking, isTrue);

    await service.stop();
    await task;
    expect(readyCount, 1);
  });

  test('云端合成失败回退系统后 onReady 在系统播放发起时触发', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient:
          _client(counter, failKind: WorkerTtsErrorKind.network),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );
    var readyCount = 0;

    await service.speak('床前明月光', onReady: (_) => readyCount++);

    // 云合成失败 → 系统朗读兜底发起 → onReady 仍触发（遮罩语义覆盖回退过程）。
    expect(tts.spokenTexts, ['床前明月光']);
    expect(readyCount, 1);
  });

  test('云端合成挂起期间 stop：合成返回后不播放且不触发 onReady（AC2）', () async {
    final counter = _RequestCounter();
    final synthGate = Completer<void>();
    final tts = _FakeFlutterTts();
    final player = _FakeCloudAudioPlayer(events: <String>[]);
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter, synthGate: synthGate),
      cloudPlayer: player,
    );
    var readyCount = 0;

    final task = service.speak('床前明月光', onReady: (_) => readyCount++);
    // 等待进入合成 await 窗口。
    await Future<void>.delayed(Duration.zero);
    expect(player.played, isEmpty);

    // 合成挂起期间用户请求停止，随后合成才返回字节。
    await service.stop();
    synthGate.complete();
    await task;

    // 孤儿音频消除：不发起播放、不触发 onReady、不回退系统朗读。
    expect(player.played, isEmpty);
    expect(readyCount, 0);
    expect(tts.spokenTexts, isEmpty);
  });

  test('云端播放抛错跳过该句时 onReady 仍触发且会话上抛（AC4）', () async {
    final counter = _RequestCounter();
    final player = _FakeCloudAudioPlayer()..throwOnPlay = true;
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient: _client(counter),
      cloudPlayer: player,
    );
    var readyCount = 0;

    // R3：单段会话「合成成功但播放失败」= 全跳句 → 上抛 TtsException，
    // 页面按朗读失败提示，不再静默会话。
    await expectLater(
      service.speak('床前明月光', onReady: (_) => readyCount++),
      throwsA(
        isA<TtsException>().having(
          (error) => error.message,
          'message',
          contains('云端音频播放失败'),
        ),
      ),
    );

    // 旧缺陷一：play 抛错走「跳过该句」return，onReady 永不触发 → 遮罩
    // 锁死整个会话。新契约：发起前已触发。
    expect(player.playFailures, 1);
    expect(readyCount, 1);
  });

  test('云端首段 play 抛错跳句后：onReady 已触发且后续行继续播放', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final player = _FakeCloudAudioPlayer()..throwOnPlayLimit = 1;
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter),
      cloudPlayer: player,
    );
    var readyCount = 0;

    await service.speakLines(
      ['床前明月光', '疑是地上霜'],
      onReady: (_) => readyCount++,
    );

    // 第一行 play 抛错被跳过，第二行正常播放；系统引擎不补读（无双读）。
    expect(player.playFailures, 1);
    expect(player.played.length, 2);
    expect(tts.spokenTexts, isEmpty);
    // 回归：跳句分支 onReady 已触发，整个会话不锁遮罩。
    expect(readyCount, 1);
  });

  test('语速映射为 Worker rate 并写入请求体', () async {
    final counter = _RequestCounter();
    final scripted = _ScriptedHttpClient(counter: counter);
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient: WorkerTtsClient(httpClient: scripted),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speak('床前明月光');

    // ttsSpeed = 0.5 → rate "0"。
    expect(scripted.bodies, isNotEmpty);
    expect(scripted.bodies.last['rate'], '0');
    expect(scripted.bodies.last['voice'], kDefaultWorkerVoice);
    expect(scripted.bodies.last['style'], 'poetry-reading');
    expect(scripted.bodies.last['format'], kWorkerAudioFormat);
    expect(scripted.bodies.last['pitch'], '0');
  });

  test('单行网络失败回退系统引擎完成当句', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter, failKind: WorkerTtsErrorKind.network),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speak('床前明月光');

    expect(counter.value, 1);
    expect(tts.spokenTexts, ['床前明月光']);
  });

  test('网络失败仅影响当前行，后续行继续尝试云端', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final player = _FakeCloudAudioPlayer();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter, failKind: WorkerTtsErrorKind.network),
      cloudPlayer: player,
    );

    await service.speakLines(['床前明月光', '疑是地上霜']);

    // 每行都尝试云端（各失败一次），但均回退系统完成。
    expect(counter.value, 2);
    expect(tts.spokenTexts, ['床前明月光', '疑是地上霜']);
    expect(player.played, isEmpty);
  });

  test('401 鉴权错误整段降级且只请求一次', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient:
          _client(counter, failKind: WorkerTtsErrorKind.authentication),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await service.speakLines(['床前明月光', '疑是地上霜', '举头望明月']);

    expect(counter.value, 1);
    expect(tts.spokenTexts, ['床前明月光', '疑是地上霜', '举头望明月']);
  });

  test('云端播放抛错时跳过该行且不回退系统朗读，全跳句上抛（AC4）', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final player = _FakeCloudAudioPlayer()..throwOnPlay = true;
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter),
      cloudPlayer: player,
    );

    // 两行均合成并尝试播放，播放失败仅跳过该行；所有段全跳句 →
    // R3：会话结束上抛（静默会话缺陷修复）。
    await expectLater(
      service.speakLines(['床前明月光', '疑是地上霜']),
      throwsA(isA<TtsException>()),
    );

    expect(counter.value, 2);
    expect(player.playFailures, 2);
    // 系统引擎不得补读，避免同一句被读两遍。
    expect(tts.spokenTexts, isEmpty);
  });

  test('云端部分行播放成功：跳句保持静默续播不上抛（AC4）', () async {
    final counter = _RequestCounter();
    final tts = _FakeFlutterTts();
    final player = _FakeCloudAudioPlayer()..throwOnPlayLimit = 1;
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: tts,
      cloudClient: _client(counter),
      cloudPlayer: player,
    );
    var completed = false;

    await service.speakLines(
      ['床前明月光', '疑是地上霜'],
      onComplete: (_) => completed = true,
    );

    // 第一行跳句、第二行播成：部分成功 → 不上抛、完成回调正常。
    expect(player.playFailures, 1);
    expect(player.played.length, 2);
    expect(completed, isTrue);
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
      onComplete: (_) => completed = true,
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
      cloudClient: _client(counter, failKind: WorkerTtsErrorKind.request),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    await expectLater(
      service.previewCloud('床前明月光'),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.request,
        ),
      ),
    );
  });

  test('previewCloud 未验证时抛出引导配置异常', () async {
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
        isA<WorkerTtsException>()
            .having(
              (error) => error.kind,
              'kind',
              WorkerTtsErrorKind.authentication,
            )
            .having(
              (error) => error.message,
              'message',
              contains('保存并验证'),
            ),
      ),
    );
    expect(counter.value, 0);
  });

  test('previewCloud 异常不包含 API Key（AC12）', () async {
    final counter = _RequestCounter();
    final service = TtsService(
      _stubSettings(cloudEnabled: true),
      flutterTts: _FakeFlutterTts(),
      cloudClient:
          _client(counter, failKind: WorkerTtsErrorKind.authentication),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    try {
      await service.previewCloud('床前明月光');
      fail('expected throw');
    } on Object catch (error) {
      expect(error.toString(), isNot(contains('worker-secret-key-example')));
      expect(error.toString(), isNot(contains(_config.apiKey)));
    }
  });

  test('语速 0.1 / 1.0 映射为 -50 / +100（AC11）', () async {
    final counter = _RequestCounter();
    final scripted = _ScriptedHttpClient(counter: counter);
    final settings = _stubSettings(cloudEnabled: true);

    final service = TtsService(
      settings,
      flutterTts: _FakeFlutterTts(),
      cloudClient: WorkerTtsClient(httpClient: scripted),
      cloudPlayer: _FakeCloudAudioPlayer(),
    );

    when(() => settings.ttsSpeed).thenReturn(0.1);
    await service.speak('慢速');
    expect(scripted.bodies.last['rate'], '-50');

    when(() => settings.ttsSpeed).thenReturn(1.0);
    await service.speak('快速');
    expect(scripted.bodies.last['rate'], '+100');
  });
}
