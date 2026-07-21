import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/speech/hybrid_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/speech_recognition_settings_page.dart';

final class _FakeSettingsRepository extends SettingsRepository {
  TencentAsrCredentials? _credentials;
  bool _verified = false;
  bool _highAccuracyEnabled = false;
  DateTime? _verifiedAt;

  @override
  DateTime? get tencentAsrVerifiedAt => _verifiedAt;

  @override
  Future<void> saveTencentAsrCredentials({
    required String secretId,
    required String secretKey,
  }) async {
    final changed = _credentials?.secretId != secretId ||
        _credentials?.secretKey != secretKey;
    _credentials = TencentAsrCredentials(
      secretId: secretId,
      secretKey: secretKey,
    );
    if (changed) await invalidateTencentAsrVerification();
  }

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async {
    return _credentials;
  }

  @override
  Future<SpeechRecognitionSettingsState> loadSpeechRecognitionSettings() async {
    return SpeechRecognitionSettingsState(
      hasCredentials: _credentials != null,
      isVerified: _verified,
      highAccuracyEnabled: _highAccuracyEnabled,
      verifiedAt: _verifiedAt,
    );
  }

  @override
  Future<void> markTencentAsrCredentialsVerified({
    required TencentAsrCredentials testedCredentials,
    DateTime? verifiedAt,
  }) async {
    if (_credentials?.secretId != testedCredentials.secretId ||
        _credentials?.secretKey != testedCredentials.secretKey) {
      throw StateError('credentials changed');
    }
    _verified = true;
    _verifiedAt = verifiedAt ?? DateTime.now();
  }

  @override
  Future<void> setTencentAsrHighAccuracyEnabled(bool enabled) async {
    if (enabled && !_verified) throw StateError('not verified');
    _highAccuracyEnabled = enabled;
  }

  @override
  Future<void> invalidateTencentAsrVerification() async {
    _verified = false;
    _highAccuracyEnabled = false;
    _verifiedAt = null;
  }

  @override
  Future<void> deleteTencentAsrCredentials() async {
    _credentials = null;
    await invalidateTencentAsrVerification();
  }
}

final class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  _FakeSpeechRecognitionService({
    this.failCloud = false,
    this.startGate,
  });

  final bool failCloud;
  final Completer<void>? startGate;
  bool _recording = false;
  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> start({void Function(String text)? onPartialResult}) async {
    startCalls++;
    await startGate?.future;
    _recording = true;
    onPartialResult?.call('床前明月光');
  }

  @override
  Future<SpeechRecognitionResult> stop({
    bool requireTencentCloud = false,
  }) async {
    stopCalls++;
    _recording = false;
    if (failCloud) {
      throw const TencentAsrException(
        '腾讯云密钥无效或没有识别权限',
        kind: TencentAsrErrorKind.authentication,
      );
    }
    return const SpeechRecognitionResult(
      text: '床前明月光',
      localText: '床前明月光',
      source: SpeechRecognitionSource.tencentCloud,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _recording = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late _FakeSettingsRepository settings;

  setUp(() {
    settings = _FakeSettingsRepository();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    SpeechRecognitionService service,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(settings),
          speechRecognitionServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: SpeechRecognitionSettingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> enterCredentialsAndStart(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'SecretId (AK)'),
      'AKID-test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'SecretKey (SK)'),
      'SK-test',
    );
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final startButton = find.text('开始真实录音测试');
    await tester.ensureVisible(startButton);
    await tester.pump(const Duration(milliseconds: 500));
    final buttonFinder = find.widgetWithText(FilledButton, '开始真实录音测试');
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
    expect(buttonFinder.hitTestable(), findsOneWidget);
    await tester.tap(buttonFinder.hitTestable());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('真实录音测试成功后才能开启高精度识别', (tester) async {
    final service = _FakeSpeechRecognitionService();
    await pumpPage(tester, service);
    await enterCredentialsAndStart(tester);

    expect(find.text('请填写 SecretId 和 SecretKey'), findsNothing);
    expect(find.text('无法开始录音，请检查麦克风权限'), findsNothing);
    expect(service.initializeCalls, 1);
    expect(service.startCalls, 1);
    expect(service.isRecording, isTrue);
    expect(find.text('结束并验证'), findsOneWidget);
    expect(find.text('床前明月光'), findsWidgets);

    final endButton = find.widgetWithText(FilledButton, '结束并验证');
    await tester.ensureVisible(endButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(endButton.hitTestable(), findsOneWidget);
    await tester.tap(endButton.hitTestable());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(service.stopCalls, 1);
    expect(settings.tencentAsrVerifiedAt, isNotNull);
    final state = await settings.loadSpeechRecognitionSettings();
    expect(state.isVerified, isTrue);
    expect(state.highAccuracyEnabled, isFalse);

    final highAccuracySwitch = find.byType(Switch);
    await tester.ensureVisible(highAccuracySwitch);
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.widget<Switch>(highAccuracySwitch).onChanged != null) break;
    }
    expect(tester.widget<Switch>(highAccuracySwitch).onChanged, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('腾讯测试失败时撤销验证并保持离线模式', (tester) async {
    await pumpPage(
      tester,
      _FakeSpeechRecognitionService(failCloud: true),
    );
    await enterCredentialsAndStart(tester);

    final endButton = find.widgetWithText(FilledButton, '结束并验证');
    await tester.ensureVisible(endButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(endButton.hitTestable(), findsOneWidget);
    await tester.tap(endButton.hitTestable());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 2));

    final state = await settings.loadSpeechRecognitionSettings();
    expect(state.isVerified, isFalse);
    expect(state.highAccuracyEnabled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('录音启动期间退出页面会在启动完成后取消录音', (tester) async {
    final startGate = Completer<void>();
    final service = _FakeSpeechRecognitionService(startGate: startGate);
    await pumpPage(tester, service);

    await tester.enterText(
      find.widgetWithText(TextField, 'SecretId (AK)'),
      'AKID-test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'SecretKey (SK)'),
      'SK-test',
    );
    final startButton = find.widgetWithText(
      FilledButton,
      '开始真实录音测试',
    );
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();
    expect(service.startCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    startGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(service.cancelCalls, 1);
    expect(service.isRecording, isFalse);
  });
}
