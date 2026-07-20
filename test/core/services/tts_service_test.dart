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

  test('未初始化时停止朗读不会调用平台引擎', () async {
    await service.stop();

    expect(engine.calls, isEmpty);
  });
}
