import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

/// stop() 挂在闸门上的假云端播放器（AC3：制造 stop 的平台调用窗口）。
class _HoldingStopCloudPlayer implements CloudAudioPlayer {
  _HoldingStopCloudPlayer(this.gate);

  final Completer<void> gate;
  int stopCalls = 0;

  @override
  Future<void> play(Uint8List bytes) async {}

  @override
  Future<void> stop() async {
    stopCalls++;
    await gate.future;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeFlutterTts extends Fake implements FlutterTts {
  final List<String> calls = <String>[];
  final List<String> spokenTexts = <String>[];
  final List<Completer<dynamic>> controlledSpeaks = <Completer<dynamic>>[];

  Object? awaitCompletionError;
  int? failSpeakAt;
  int awaitCompletionCallCount = 0;
  int stopCallCount = 0;
  int _speakCallCount = 0;

  /// 初始化闸门：非空时 awaitSpeakCompletion 先挂起（模拟冷启动初始化
  /// 的真实异步窗口，AC1）。
  Completer<void>? initGate;

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
    final gate = initGate;
    if (gate != null) await gate.future;
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
    stopCallCount++;
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
      // message 会被页面拼接前缀（如「朗读失败：${message}」），其自身
      // 不得再含前缀字样——否则拼出「朗读失败：朗读失败」式重复文案
      // （缺陷 2 复核补断言）。
      throwsA(
        isA<TtsException>().having(
          (error) => error.message,
          'message',
          isNot(contains('朗读失败')),
        ),
      ),
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

  test('stop 在首段播放发起前抢跑时 onReady 不触发且不发起播放', () async {
    var readyCount = 0;

    await service.speakLines(
      const <String>['第一行', '第二行'],
      // onLineStart 在合成 await 之前回调：在触发点之前抢跑 stop。
      onLineStart: (_) => service.stop(),
      onReady: () => readyCount++,
    );

    // 触发时 _stopRequested 已置位 → 不触发；循环也不再继续。
    // 缺陷 2 修复后段发起有停止守卫：该句连系统 speak 都不发起
    // （旧断言 ['第一行'] 固化了「孤儿音频」缺陷，现翻转为空）。
    expect(readyCount, 0);
    expect(engine.spokenTexts, const <String>[]);
    expect(service.isSpeaking, isFalse);
  });

  test('旧会话挂起中开新会话：旧会话剩余行不再播放（会话令牌，AC1）', () async {
    final firstLine = Completer<dynamic>();
    final newLine = Completer<dynamic>();
    engine.controlledSpeaks.addAll(<Completer<dynamic>>[firstLine, newLine]);
    final oldStarted = <int>[];
    var oldCompleted = false;

    // 旧会话：两行，首行挂起中。
    final oldSession = service.speakLines(
      const <String>['旧行一', '旧行二'],
      onLineStart: oldStarted.add,
      onComplete: () => oldCompleted = true,
    );
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['旧行一']);

    // 旧会话首行仍挂起时直接开新会话（stop 失败后页面直达新朗读的
    // 等价时序：新入口会复位 _stopRequested，但旧会话必须按代际退出）。
    final newSession = service.speakLines(const <String>['新行一']);
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['旧行一', '新行一']);

    // 放行旧会话挂起的 speak：代际失配 → 旧会话不读「旧行二」、
    // 不触发 onComplete；新会话不受影响。
    firstLine.complete(1);
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['旧行一', '新行一']);
    expect(oldStarted, const <int>[0]);
    expect(oldCompleted, isFalse);

    newLine.complete(1);
    await oldSession;
    await newSession;
    expect(engine.spokenTexts, const <String>['旧行一', '新行一']);
    expect(oldCompleted, isFalse);
    expect(service.isSpeaking, isFalse);
  });

  test('未初始化时停止朗读不会调用平台引擎', () async {
    await service.stop();

    expect(engine.calls, isEmpty);
  });

  test('入口初始化挂起期间 stop：resume 后零播放零回调（AC1，缺陷 1）', () async {
    final initGate = Completer<void>();
    engine.initGate = initGate;
    final lineStarts = <int>[];
    var readyCount = 0;
    var completeCount = 0;

    final task = service.speakLines(
      const <String>['第一行', '第二行'],
      onLineStart: lineStarts.add,
      onReady: () => readyCount++,
      onComplete: () => completeCount++,
    );
    await _flushMicrotasks();
    // 初始化挂起窗口：引擎尚未播放任何内容。
    expect(engine.spokenTexts, isEmpty);

    // 窗口内 stop（页面 dispose 的等价时序）：旧实现在 resume 后自成
    // 最新代并复位停止标志 → 整首照播；新实现入口已捕获令牌，
    // 首个循环检查即死。
    await service.stop();
    initGate.complete();
    await task;

    expect(engine.spokenTexts, isEmpty);
    expect(lineStarts, isEmpty);
    expect(readyCount, 0);
    expect(completeCount, 0);
    expect(service.isSpeaking, isFalse);
  });

  test('入口初始化挂起期间 dispose：resume 后零播放零回调（AC1，缺陷 1）', () async {
    final initGate = Completer<void>();
    engine.initGate = initGate;
    final lineStarts = <int>[];
    var readyCount = 0;
    var completeCount = 0;

    final task = service.speakLines(
      const <String>['第一行', '第二行'],
      onLineStart: lineStarts.add,
      onReady: () => readyCount++,
      onComplete: () => completeCount++,
    );
    await _flushMicrotasks();
    expect(engine.spokenTexts, isEmpty);

    // 窗口内 dispose：递增代际使本会话失效——页面已销毁整首不照播。
    service.dispose();
    initGate.complete();
    await task;

    expect(engine.spokenTexts, isEmpty);
    expect(lineStarts, isEmpty);
    expect(readyCount, 0);
    expect(completeCount, 0);
    expect(service.isSpeaking, isFalse);
  });

  test('stop 挂在云端播放器 stop 期间新会话朗读：晚到的引擎 stop 不取消新会话（AC3，缺陷 3）', () async {
    final stopGate = Completer<void>();
    final player = _HoldingStopCloudPlayer(stopGate);
    final cloudService = TtsService(
      settings,
      flutterTts: engine,
      cloudPlayer: player,
    );

    // 预热：完成引擎初始化，后续 stop 才会走引擎分支。
    await cloudService.speak('预热');
    expect(engine.spokenTexts, const <String>['预热']);
    expect(engine.stopCallCount, 0);

    // 旧 stop：挂在 player.stop()（数百 ms 的平台调用窗口）。
    final stopTask = cloudService.stop();
    await Future<void>.delayed(Duration.zero);
    expect(player.stopCalls, 1);

    // 挂起期间新会话入口并开始播放首行（系统路径，受控挂起证明在播）。
    // 预热已消耗 speak 调用序号 0，占位使新会话两行落在序号 1、2。
    final line1Gate = Completer<dynamic>();
    final line2Gate = Completer<dynamic>();
    engine.controlledSpeaks.addAll(<Completer<dynamic>>[
      Completer<dynamic>(), // 序号 0 占位（预热时列表为空，实际不会使用）
      line1Gate,
      line2Gate,
    ]);
    final newSession = cloudService.speakLines(
      const <String>['新行一', '新行二'],
    );
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['预热', '新行一']);

    // 放行旧 stop：挂起期间新会话入口已递增代际 → 晚到的引擎 stop
    // 被代际重校验跳过，不再取消新会话当前句。
    stopGate.complete();
    await stopTask;
    await _flushMicrotasks();
    expect(engine.stopCallCount, 0);
    // 新会话首行未被晚到 stop 打断（仍挂起等待自然播完）。
    expect(engine.spokenTexts, const <String>['预热', '新行一']);

    // 新会话完整跑完：首行自然播完后第二行继续发起并自然播完。
    line1Gate.complete(1);
    await _flushMicrotasks();
    expect(engine.spokenTexts, const <String>['预热', '新行一', '新行二']);
    line2Gate.complete(1);
    await newSession;
    expect(engine.spokenTexts, const <String>['预热', '新行一', '新行二']);
    expect(cloudService.isSpeaking, isFalse);
  });
}
