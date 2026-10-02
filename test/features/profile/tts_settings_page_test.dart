import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/tts_settings_page.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

const _verifiedSettings = SpeechRecognitionSettingsState(
  hasCredentials: true,
  isVerified: true,
);

const _unverifiedSettings = SpeechRecognitionSettingsState(
  hasCredentials: false,
  isVerified: false,
);

void _stubBaseSettings(
  _MockSettingsRepository settings, {
  bool verified = false,
  bool cloudEnabled = false,
}) {
  when(() => settings.ttsVoice).thenReturn(null);
  when(() => settings.ttsSpeed).thenReturn(0.5);
  when(() => settings.ttsCloudEnabled).thenReturn(cloudEnabled);
  when(() => settings.ttsCloudVoiceType).thenReturn(kDefaultTencentVoiceType);
  when(() => settings.loadSpeechRecognitionSettings()).thenAnswer(
    (_) async => verified ? _verifiedSettings : _unverifiedSettings,
  );
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _MockTtsService tts,
  required _MockSettingsRepository settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        ttsServiceProvider.overrideWithValue(tts),
      ],
      child: const MaterialApp(home: TtsSettingsPage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('音色加载失败后退出加载状态并可重试', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    var loadAttempts = 0;

    _stubBaseSettings(settings);
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => tts.getChineseVoices()).thenAnswer((_) async {
      loadAttempts++;
      if (loadAttempts == 1) {
        throw const TtsException('系统音色不可用');
      }
      return const <Map<String, String>>[
        <String, String>{'name': 'zh-cn', 'locale': 'zh-CN'},
      ];
    });

    await _pumpPage(tester, tts: tts, settings: settings);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('音色加载失败，请检查系统语音服务'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(find.text('音色加载失败，请检查系统语音服务'), findsNothing);
    expect(find.text('系统默认'), findsOneWidget);
    expect(find.text('普通话语音'), findsOneWidget);
    expect(loadAttempts, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('未验证时云端开关置灰并显示配置引导', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: false);
    when(() => tts.getChineseVoices())
        .thenAnswer((_) async => const <Map<String, String>>[]);
    when(() => tts.stop()).thenAnswer((_) async {});

    await _pumpPage(tester, tts: tts, settings: settings);

    expect(find.text('云端朗读音色（腾讯云）'), findsOneWidget);
    expect(
      find.text('需先在语音识别设置中配置密钥并通过真实录音测试'),
      findsOneWidget,
    );
    expect(find.text('去配置密钥'), findsOneWidget);
    final cloudSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(cloudSwitch.onChanged, isNull);
    // 未开启时不显示音色列表。
    expect(find.text('智瑜'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('已验证时开启云端朗读显示音色并可试听', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    var cloudEnabled = false;
    _stubBaseSettings(settings, verified: true);
    when(() => settings.setTtsCloudEnabled(any())).thenAnswer((invocation) {
      cloudEnabled = invocation.positionalArguments[0] as bool;
      return Future.value();
    });
    when(() => settings.setTtsCloudVoiceType(any()))
        .thenAnswer((_) async {});
    when(() => tts.getChineseVoices())
        .thenAnswer((_) async => const <Map<String, String>>[]);
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => tts.previewCloud(any())).thenAnswer((_) async {});

    await _pumpPage(tester, tts: tts, settings: settings);

    final cloudSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(cloudSwitch).onChanged, isNotNull);

    await tester.ensureVisible(cloudSwitch);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(cloudSwitch);
    await tester.pump();

    expect(cloudEnabled, isTrue);
    expect(find.text('智瑜', skipOffstage: false), findsOneWidget);
    expect(find.text('智灵', skipOffstage: false), findsOneWidget);
    expect(find.text('系统音色（离线可用）', skipOffstage: false), findsOneWidget);

    // 音色 tile 由 trailing 试听按钮触发选择（与系统音色一致），
    // 列表顺序 = kTencentPremiumVoices：智瑜、智灵、……
    final playButtons = find.byIcon(Icons.play_circle_outline);
    expect(playButtons, findsAtLeast(2));
    final zhilingPlay = playButtons.at(1);
    await tester.ensureVisible(zhilingPlay);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(zhilingPlay);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    verify(() => tts.previewCloud(any())).called(greaterThan(0));
    verify(() => settings.setTtsCloudVoiceType(101002)).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('云端试听失败时显示具体原因', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: true, cloudEnabled: true);
    when(() => settings.setTtsCloudVoiceType(any()))
        .thenAnswer((_) async {});
    when(() => tts.getChineseVoices())
        .thenAnswer((_) async => const <Map<String, String>>[]);
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => tts.previewCloud(any())).thenThrow(
      const TencentTtsException(
        '腾讯云语音合成额度已用尽或账户欠费',
        kind: TencentTtsErrorKind.quota,
      ),
    );

    await _pumpPage(tester, tts: tts, settings: settings);

    expect(find.text('智瑜'), findsOneWidget);

    final playButton = find.byIcon(Icons.play_circle_outline).first;
    await tester.ensureVisible(playButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(playButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.text('腾讯云语音合成额度已用尽或账户欠费'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
