import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _FakeFlutterTts extends Fake implements FlutterTts {
  final List<String> calls = <String>[];
  final List<String> spokenTexts = <String>[];
  final List<Completer<dynamic>> controlledSpeaks = <Completer<dynamic>>[];

  Object? awaitCompletionError;
  int? failSpeakAt;
  int awaitCompletionCallCount = 0;
  int _speakCallCount = 0;

  @override
  VoidCallback? cancelHandler;

  @override
  ErrorHandler? errorHandler;

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage:$language');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('setSpeechRate:$rate');
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    calls.add('setVolume:$volume');
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add('setPitch:$pitch');
    return 1;
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    calls.add('setVoice:${voice['name']}');
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    calls.add('awaitSpeakCompletion:$awaitCompletion');
    awaitCompletionCallCount++;
    final error = awaitCompletionError;
    if (error != null) throw error;
    return 1;
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    calls.add('setCancelHandler');
    cancelHandler = callback;
  }

  @override
  void setErrorHandler(ErrorHandler handler) {
    calls.add('setErrorHandler');
    errorHandler = handler;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    final callIndex = _speakCallCount++;
    calls.add('speak:$text');
    spokenTexts.add(text);
    if (failSpeakAt == callIndex) {
      throw Exception('speak failed at $callIndex');
    }
    if (callIndex < controlledSpeaks.length) {
      return controlledSpeaks[callIndex].future;
    }
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
    for (final completer in controlledSpeaks) {
      if (!completer.isCompleted) {
        completer.complete(1);
        break;
      }
    }
    return 1;
  }
}

Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _MockSettingsRepository settings;
  late _FakeFlutterTts engine;
  late TtsService service;

  setUp(() {
    settings = _MockSettingsRepository();
    engine = _FakeFlutterTts();
    when(() => settings.ttsSpeed).thenReturn(0.5);
    when(() => settings.ttsVoice).thenReturn(null);
    service = TtsService(settings, flutterTts: engine);
  });

  test('首次 speak 前启用完成等待，且只初始化一次', () async {
    await service.speak('第一句');
    await service.speak('第二句');

    final awaitIndex = engine.calls.indexOf('awaitSpeakCompletion:true');
    final firstSpeakIndex = engine.calls.indexOf('speak:第一句');
    expect(awaitIndex, greaterThanOrEqualTo(0));
    expect(awaitIndex, lessThan(firstSpeakIndex));
    expect(engine.awaitCompletionCallCount, 1);
    expect(service.isSpeaking, isFalse);
  });

  test('逐行朗读严格等待上一行完成', () async {
    final first = Completer<dynamic>();
    final second = Completer<dynamic>();
    engine.controlledSpeaks.addAll(<Completer<dynamic>>[first, second]);
    final started = <int>[];
    var completeCount = 0;

    final speaking = service.speakLines(
      const <String>['第一行', '第二行'],
      onLineStart: started.add,
      onComplete: () => completeCount++,
    );
    await _flushMicrotasks();

    expect(engine.spokenTexts, const <String>['第一行']);
    expect(started, const <int>[0]);
    expect(service.isSpeaking, isTrue);

    first.complete(1);
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['第一行', '第二行']);
    expect(started, const <int>[0, 1]);
    expect(completeCount, 0);

    second.complete(1);
    await speaking;
    expect(completeCount, 1);
    expect(service.isSpeaking, isFalse);
  });

  test('初始化失败后状态可恢复并允许重试', () async {
    engine.awaitCompletionError = Exception('engine missing');

    await expectLater(
      service.speak('失败'),
      throwsA(
        isA<TtsException>().having(
          (error) => error.message,
          'message',
          '语音引擎初始化失败',
        ),
      ),
    );
    expect(service.isSpeaking, isFalse);

    engine.awaitCompletionError = null;
    await service.speak('重试成功');

    expect(engine.awaitCompletionCallCount, 2);
    expect(engine.spokenTexts, const <String>['重试成功']);
    expect(service.isSpeaking, isFalse);
  });

  test('中途 speak 异常后停止循环并恢复状态', () async {
    engine.failSpeakAt = 1;
    final started = <int>[];
    var completed = false;

    await expectLater(
      service.speakLines(
        const <String>['第一行', '第二行', '第三行'],
        onLineStart: started.add,
        onComplete: () => completed = true,
      ),
      throwsA(isA<TtsException>()),
    );

    expect(engine.spokenTexts, const <String>['第一行', '第二行']);
    expect(started, const <int>[0, 1]);
    expect(completed, isFalse);
    expect(service.isSpeaking, isFalse);
  });

  test('主动停止后不继续下一行且不触发完成回调', () async {
    final first = Completer<dynamic>();
    engine.controlledSpeaks.add(first);
    var completed = false;

    final speaking = service.speakLines(
      const <String>['第一行', '第二行'],
      onComplete: () => completed = true,
    );
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['第一行']);

    await service.stop();
    await speaking;

    expect(engine.spokenTexts, const <String>['第一行']);
    expect(completed, isFalse);
    expect(service.isSpeaking, isFalse);
  });

  test('系统路径 onReady 在首行 speak 发起前触发一次', () async {
    final first = Completer<dynamic>();
    engine.controlledSpeaks.add(first);
    var readyCount = 0;

    final speaking = service.speakLines(
      const <String>['第一行', '第二行'],
      onReady: () => readyCount++,
    );
    await _flushMicrotasks();

    // 首行 speak 仍挂起（音频未播完），onReady 已在播放动作发起时触发。
    expect(engine.spokenTexts, const <String>['第一行']);
    expect(readyCount, 1);
    expect(service.isSpeaking, isTrue);

    first.complete(1);
    await speaking;
    expect(readyCount, 1);
  });

  test('speak 的 onReady 在播放动作发起时触发（speak 未完成前）', () async {
    final gate = Completer<dynamic>();
    engine.controlledSpeaks.add(gate);
    var readyCount = 0;

    final speaking = service.speak('单句', onReady: () => readyCount++);
    await _flushMicrotasks();

    // speak 仍挂起，onReady 已触发——遮罩在出声前解除。
    expect(engine.spokenTexts, const <String>['单句']);
    expect(readyCount, 1);

    gate.complete(1);
    await speaking;
    expect(readyCount, 1);
  });

  test('speakSentences 的 onReady 在首句播放动作发起时触发一次', () async {
    var readyCount = 0;
    await service.speakSentences(
      '第一句。第二句！',
      onReady: () => readyCount++,
    );

    expect(engine.spokenTexts, const <String>['第一句', '第二句']);
    expect(readyCount, 1);
  });

  test('首行朗读异常时状态恢复（onReady 已在发起时触发，不锁遮罩）', () async {
    engine.failSpeakAt = 0;
    var readyCount = 0;

    await expectLater(
      service.speakLines(
        const <String>['第一行', '第二行'],
        onReady: () => readyCount++,
      ),
      throwsA(isA<TtsException>()),
    );

    // 新契约：onReady 在 speak 发起前触发；speak 随后抛错由调用方
    // 异常路径 finally 兜底清理，遮罩不锁死。
    expect(readyCount, 1);
    expect(service.isSpeaking, isFalse);
  });

  test('首段播出中 stop：onReady 已在发起时触发（出声期间遮罩可解除）', () async {
    final first = Completer<dynamic>();
    engine.controlledSpeaks.add(first);
    var readyCount = 0;

    final speaking = service.speakLines(
      const <String>['第一行', '第二行'],
      onReady: () => readyCount++,
    );
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['第一行']);
    // 旧缺陷：onReady 等整句播完才触发，出声期间遮罩锁死且无法停止。
    // 新契约：发起时已触发，用户在出声期间即可点击停止。
    expect(readyCount, 1);

    await service.stop();
    await speaking;

    expect(engine.spokenTexts, const <String>['第一行']);
    expect(readyCount, 1);
    expect(service.isSpeaking, isFalse);
  });

  test('stop 在首段播放发起前抢跑时 onReady 不触发', () async {
    var readyCount = 0;

    await service.speakLines(
      const <String>['第一行', '第二行'],
      // onLineStart 在合成 await 之前回调：在触发点之前抢跑 stop。
      onLineStart: (_) => service.stop(),
      onReady: () => readyCount++,
    );

    // 触发时 _stopRequested 已置位 → 不触发；循环也不再继续。
    expect(readyCount, 0);
    expect(engine.spokenTexts, const <String>['第一行']);
    expect(service.isSpeaking, isFalse);
  });

  test('未初始化时停止朗读不会调用平台引擎', () async {
    await service.stop();

    expect(engine.calls, isEmpty);
  });
}
