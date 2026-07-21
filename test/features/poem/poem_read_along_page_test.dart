import 'dart:async';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/hybrid_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/poem/poem_read_along_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/widgets/read_along_voice_status_button.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

final class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  _FakeSpeechRecognitionService({
    this.initializeCompleter,
    this.startCompleter,
    this.stopCompleter,
    this.startError,
  });

  final Completer<void>? initializeCompleter;
  final Completer<void>? startCompleter;
  final Completer<SpeechRecognitionResult>? stopCompleter;
  final Object? startError;

  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    await initializeCompleter?.future;
  }

  @override
  Future<void> start({void Function(String text)? onPartialResult}) async {
    startCalls++;
    await startCompleter?.future;
    if (startError != null) throw startError!;
    _isRecording = true;
  }

  @override
  Future<SpeechRecognitionResult> stop({
    bool requireTencentCloud = false,
  }) async {
    stopCalls++;
    final result = await (stopCompleter?.future ??
        Future.value(
          const SpeechRecognitionResult(
            text: '床前明月光',
            localText: '床前明月光',
            source: SpeechRecognitionSource.local,
          ),
        ));
    _isRecording = false;
    return result;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _isRecording = false;
  }

  @override
  Future<void> dispose() async {}
}

const _poemId = 'read-along-test-poem';

final _poem = Poem(
  id: _poemId,
  title: '静夜思',
  author: '李白',
  dynasty: '唐',
  content: '床前明月光，\n疑是地上霜。',
  pinyin: '',
  layer: 'core',
);

void main() {
  late _MockTtsService tts;
  late _MockSettingsRepository settings;

  setUp(() {
    tts = _MockTtsService();
    settings = _MockSettingsRepository();
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => settings.hapticEnabled).thenReturn(false);
    when(() => settings.soundEnabled).thenReturn(false);
  });

  testWidgets('跟读页首帧应直接显示诗句内容', (tester) async {
    final speech = _FakeSpeechRecognitionService();

    await _pumpPage(
      tester,
      speech,
      tts,
      settings,
      settleAnimations: false,
    );
    await tester.pump();

    expect(find.text('床前明月光，'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('点击读一读立即显示准备状态并复用初始化任务', (tester) async {
    final initialization = Completer<void>();
    final speech = _FakeSpeechRecognitionService(
      initializeCompleter: initialization,
    );

    await _pumpPage(tester, speech, tts, settings);
    await tester.tap(find.text('读一读'));
    await tester.tap(find.text('读一读'));
    await tester.pump();

    expect(find.text('准备录音'), findsOneWidget);
    expect(find.text('听一听'), findsNothing);
    expect(find.text('读一读'), findsNothing);
    expect(speech.initializeCalls, 1);

    initialization.complete();
    await tester.pump();
    await tester.pump();

    expect(speech.startCalls, 1);
    expect(find.text('录音中'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('录音状态显示秒数，点击后进入识别状态并展示结果', (tester) async {
    final recognition = Completer<SpeechRecognitionResult>();
    final speech = _FakeSpeechRecognitionService(
      stopCompleter: recognition,
    );

    await _pumpPage(tester, speech, tts, settings);
    await tester.pump();
    await tester.tap(find.text('读一读'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('read-along-voice-bars')), findsOneWidget);
    expect(find.text('录音中'), findsOneWidget);
    expect(find.text('0秒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1秒'), findsOneWidget);

    await tester.tap(find.text('录音中'));
    await tester.pump();
    expect(find.text('识别中'), findsOneWidget);
    expect(find.byKey(const ValueKey('read-along-voice-dots')), findsOneWidget);
    expect(speech.stopCalls, 1);

    recognition.complete(
      const SpeechRecognitionResult(
        text: '床前明月光',
        localText: '床前明月光',
        source: SpeechRecognitionSource.local,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final renderedTexts = tester
        .widgetList<Text>(find.byType(Text, skipOffstage: false))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(
      find.text('100分', skipOffstage: false),
      findsOneWidget,
      reason: '$renderedTexts',
    );
    expect(find.text('床前明月光', skipOffstage: false), findsOneWidget);
  });

  testWidgets('页面退出后录音启动完成会继续取消服务', (tester) async {
    final start = Completer<void>();
    final speech = _FakeSpeechRecognitionService(startCompleter: start);

    await _pumpPage(tester, speech, tts, settings);
    await tester.pump();
    await tester.tap(find.text('读一读'));
    await tester.pump();
    expect(find.text('准备录音'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(speech.cancelCalls, 1);

    start.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(speech.cancelCalls, 2);
    expect(speech.isRecording, isFalse);
  });

  testWidgets('录音启动失败后恢复空闲操作并提示原因', (tester) async {
    final speech = _FakeSpeechRecognitionService(
      startError: const SpeechRecognitionException('录音设备不可用'),
    );

    await _pumpPage(tester, speech, tts, settings);
    await tester.tap(find.text('读一读'));
    await tester.pump();
    await tester.pump();

    expect(find.text('听一听'), findsOneWidget);
    expect(find.text('读一读'), findsOneWidget);
    expect(find.text('录音设备不可用'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('录音达到十五秒后自动进入识别状态', (tester) async {
    final recognition = Completer<SpeechRecognitionResult>();
    final speech = _FakeSpeechRecognitionService(
      stopCompleter: recognition,
    );

    await _pumpPage(tester, speech, tts, settings);
    await tester.tap(find.text('读一读'));
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 15));

    expect(speech.stopCalls, 1);
    expect(find.text('识别中'), findsOneWidget);

    recognition.complete(
      const SpeechRecognitionResult(
        text: '床前明月光',
        localText: '床前明月光',
        source: SpeechRecognitionSource.local,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('减少动画时状态按钮仍显示稳定的语义和图形', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: Scaffold(
            body: ReadAlongVoiceStatusButton(
              status: ReadAlongVoiceStatus.recording,
              elapsedSeconds: 3,
              onPressed: null,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('read-along-voice-bars')), findsOneWidget);
    expect(find.text('录音中'), findsOneWidget);
    expect(find.text('3秒'), findsOneWidget);
    final semantics = tester.getSemantics(
      find.byType(ReadAlongVoiceStatusButton),
    );
    expect(semantics.label, '录音中，已录制 3 秒');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  SpeechRecognitionService speech,
  TtsService tts,
  SettingsRepository settings, {
  bool settleAnimations = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        ttsServiceProvider.overrideWithValue(tts),
        poemByIdProvider(_poemId).overrideWith((ref) => _poem),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: PoemReadAlongPage(
            poemId: _poemId,
            speechRecognitionService: speech,
          ),
        ),
      ),
    ),
  );
  if (settleAnimations) {
    await tester.pump(const Duration(seconds: 1));
  }
}
