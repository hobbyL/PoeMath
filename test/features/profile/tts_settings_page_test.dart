import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/profile/tts_settings_page.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

const _testVoices = <WorkerTtsVoice>[
  WorkerTtsVoice(
    shortName: 'zh-CN-YunxiNeural',
    localName: '云希',
    gender: 'Male',
    styleList: ['narration-relaxed', 'chat'],
  ),
  WorkerTtsVoice(
    shortName: 'zh-CN-XiaoxiaoNeural',
    localName: '晓晓',
    gender: 'Female',
    styleList: ['poetry-reading', 'chat'],
  ),
  WorkerTtsVoice(
    shortName: 'zh-CN-XiaoxiaoDragonHDNeural',
    localName: '晓晓高清',
    gender: 'Female',
    styleList: [],
  ),
];

void _stubBaseSettings(
  _MockSettingsRepository settings, {
  bool verified = false,
  bool cloudEnabled = false,
}) {
  when(() => settings.ttsVoice).thenReturn(null);
  when(() => settings.ttsSpeed).thenReturn(0.5);
  when(() => settings.ttsCloudEnabled).thenReturn(cloudEnabled);
  when(() => settings.ttsCloudVoice).thenReturn(kDefaultWorkerVoice);
  when(() => settings.ttsCloudStyle).thenReturn('poetry-reading');
  when(() => settings.ttsCloudBaseUrl).thenReturn(kDefaultWorkerBaseUrl);
  when(() => settings.isWorkerTtsVerified()).thenAnswer((_) async => verified);
  when(() => settings.readWorkerTtsConfig()).thenAnswer((_) async => null);
}

void _stubTtsIdle(_MockTtsService tts, {List<WorkerTtsVoice>? cloudVoices}) {
  when(() => tts.stop()).thenAnswer((_) async {});
  when(() => tts.getChineseVoices())
      .thenAnswer((_) async => const <Map<String, String>>[]);
  when(() => tts.listCloudVoices())
      .thenAnswer((_) async => cloudVoices ?? _testVoices);
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

/// 点击指定音色 tile 的试听按钮。
Future<void> _tapVoicePlay(WidgetTester tester, String voiceName) async {
  final playButton = find.descendant(
    of: find.ancestor(
      of: find.text(voiceName),
      matching: find.byType(AppTile),
    ),
    matching: find.byIcon(Icons.play_circle_outline),
  );
  await tester.ensureVisible(playButton);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(playButton);
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WorkerTtsConfig(
        base: Uri.parse('https://fallback.example'),
        apiKey: '',
      ),
    );
  });

  testWidgets('音色加载失败后退出加载状态并可重试', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    var loadAttempts = 0;

    _stubBaseSettings(settings);
    _stubTtsIdle(tts);
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

    final reloadButton = find.text('重新加载');
    await tester.ensureVisible(reloadButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(reloadButton);
    await tester.pumpAndSettle();

    expect(find.text('音色加载失败，请检查系统语音服务'), findsNothing);
    expect(find.text('系统默认'), findsOneWidget);
    expect(find.text('普通话语音'), findsOneWidget);
    expect(loadAttempts, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC1 未配置服务时开关禁用并展示配置表单', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: false);
    _stubTtsIdle(tts);

    await _pumpPage(tester, tts: tts, settings: settings);

    expect(find.text('云端朗读音色（自建服务）'), findsOneWidget);
    expect(find.text('服务地址'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('保存并验证'), findsOneWidget);
    expect(find.text('已连接 · tts.cloudm.cc'), findsNothing);
    final cloudSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(cloudSwitch.onChanged, isNull);
    // 未开启时不加载音色目录。
    verifyNever(() => tts.listCloudVoices());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC2+AC3 填入地址与 Key 验证成功后开关可用且不产生合成', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: false);
    _stubTtsIdle(tts);
    when(() => tts.verifyCloud(any())).thenAnswer((_) async {});
    when(
      () => settings.saveWorkerTtsConfig(
        baseUrl: any(named: 'baseUrl'),
        apiKey: any(named: 'apiKey'),
      ),
    ).thenAnswer((_) async {});
    when(() => settings.markWorkerTtsVerified()).thenAnswer((_) async {});

    await _pumpPage(tester, tts: tts, settings: settings);

    await tester.enterText(
      find.byType(TextField).at(0),
      'https://tts.cloudm.cc',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-key');

    final saveButton = find.text('保存并验证');
    await tester.ensureVisible(saveButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // 验证通过：展示已连接 + 开关可用。
    expect(find.text('已连接 · tts.cloudm.cc'), findsOneWidget);
    final cloudSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(cloudSwitch.onChanged, isNotNull);

    // 验证走零成本探测：携带 Key 的 config、无真实合成请求。
    final captured = verify(() => tts.verifyCloud(captureAny()))
        .captured
        .cast<WorkerTtsConfig>();
    expect(captured, hasLength(1));
    expect(captured.single.base, Uri.parse('https://tts.cloudm.cc'));
    expect(captured.single.apiKey, 'test-key');
    verifyNever(() => tts.previewCloud(any()));

    // 通过后才持久化并标记已验证。
    verify(
      () => settings.saveWorkerTtsConfig(
        baseUrl: 'https://tts.cloudm.cc',
        apiKey: 'test-key',
      ),
    ).called(1);
    verify(() => settings.markWorkerTtsVerified()).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC2 填错 Key 时提示具体原因且不落盘、开关保持禁用', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: false);
    _stubTtsIdle(tts);
    when(() => tts.verifyCloud(any())).thenThrow(
      const WorkerTtsException(
        'API Key 无效或未授权，请检查后重试',
        kind: WorkerTtsErrorKind.authentication,
      ),
    );

    await _pumpPage(tester, tts: tts, settings: settings);

    await tester.enterText(
      find.byType(TextField).at(0),
      'https://tts.cloudm.cc',
    );
    await tester.enterText(find.byType(TextField).at(1), 'wrong-key');

    final saveButton = find.text('保存并验证');
    await tester.ensureVisible(saveButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('API Key 无效或未授权，请检查后重试'),
      findsOneWidget,
    );
    expect(find.text('已连接 · tts.cloudm.cc'), findsNothing);
    final cloudSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(cloudSwitch.onChanged, isNull);
    // 验证失败不持久化。
    verifyNever(
      () => settings.saveWorkerTtsConfig(
        baseUrl: any(named: 'baseUrl'),
        apiKey: any(named: 'apiKey'),
      ),
    );
    verifyNever(() => settings.markWorkerTtsVerified());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC9 已验证开启后按标准/DragonHD 分组展示动态音色', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: true, cloudEnabled: true);
    _stubTtsIdle(tts);
    when(() => settings.setTtsCloudVoice(any())).thenAnswer((_) async {});
    when(() => settings.setTtsCloudStyle(any())).thenAnswer((_) async {});
    when(() => tts.previewCloud(any())).thenAnswer((_) async {});

    await _pumpPage(tester, tts: tts, settings: settings);

    expect(find.text('已连接 · tts.cloudm.cc'), findsOneWidget);
    expect(find.text('标准音色（Neural）', skipOffstage: false), findsOneWidget);
    expect(
      find.text('高清音色（DragonHD）', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('晓晓', skipOffstage: false), findsOneWidget);
    expect(find.text('云希', skipOffstage: false), findsOneWidget);
    expect(find.text('晓晓高清', skipOffstage: false), findsOneWidget);
    expect(find.text('在线音色获取失败，已展示内置精选'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC9 拉取失败回退内置精选且可试听', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: true, cloudEnabled: true);
    _stubTtsIdle(tts, cloudVoices: kWorkerFallbackVoices);
    when(() => tts.listCloudVoices()).thenThrow(
      const WorkerTtsException(
        '网络不可用，请检查网络后重试',
        kind: WorkerTtsErrorKind.network,
      ),
    );
    when(() => settings.setTtsCloudVoice(any())).thenAnswer((_) async {});
    when(() => settings.setTtsCloudStyle(any())).thenAnswer((_) async {});
    when(() => tts.previewCloud(any())).thenAnswer((_) async {});

    await _pumpPage(tester, tts: tts, settings: settings);

    expect(find.text('在线音色获取失败，已展示内置精选'), findsOneWidget);
    expect(find.text('晓晓', skipOffstage: false), findsOneWidget);
    expect(find.text('云希', skipOffstage: false), findsOneWidget);
    // 兜底目录全部为标准 Neural 音色，无 DragonHD 分组。
    expect(
      find.text('高清音色（DragonHD）', skipOffstage: false),
      findsNothing,
    );

    // 兜底目录仍可选择并试听。
    await _tapVoicePlay(tester, '晓晓');
    verify(() => settings.setTtsCloudVoice('zh-CN-XiaoxiaoNeural')).called(1);
    verify(() => settings.setTtsCloudStyle('poetry-reading')).called(1);
    verify(() => tts.previewCloud(any())).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC10 选晓晓持久化诗词范读，无匹配风格回落通用', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: true, cloudEnabled: true);
    _stubTtsIdle(tts);
    when(() => settings.setTtsCloudVoice(any())).thenAnswer((_) async {});
    when(() => settings.setTtsCloudStyle(any())).thenAnswer((_) async {});
    when(() => tts.previewCloud(any())).thenAnswer((_) async {});

    await _pumpPage(tester, tts: tts, settings: settings);

    // 晓晓支持 poetry-reading → 风格随音色持久化为诗词范读。
    await _tapVoicePlay(tester, '晓晓');
    verify(() => settings.setTtsCloudStyle('poetry-reading')).called(1);

    // 晓晓高清 styleList 为空 → bestStyle 回落 general。
    await _tapVoicePlay(tester, '晓晓高清');
    verify(
      () => settings.setTtsCloudVoice('zh-CN-XiaoxiaoDragonHDNeural'),
    ).called(1);
    verify(() => settings.setTtsCloudStyle('general')).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('云端试听失败时显示具体原因', (tester) async {
    final tts = _MockTtsService();
    final settings = _MockSettingsRepository();
    _stubBaseSettings(settings, verified: true, cloudEnabled: true);
    _stubTtsIdle(tts);
    when(() => settings.setTtsCloudVoice(any())).thenAnswer((_) async {});
    when(() => settings.setTtsCloudStyle(any())).thenAnswer((_) async {});
    when(() => tts.previewCloud(any())).thenThrow(
      const WorkerTtsException(
        '语音服务未返回有效音频',
        kind: WorkerTtsErrorKind.response,
      ),
    );

    await _pumpPage(tester, tts: tts, settings: settings);

    await _tapVoicePlay(tester, '晓晓');

    expect(find.text('语音服务未返回有效音频'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
