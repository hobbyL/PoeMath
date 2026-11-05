import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_audio_service.dart';
import 'package:poemath/features/chinese/expression/picture_story_practice_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';
import '../../../helpers/picture_story_fixture.dart';

class _VisionSettings extends SettingsRepository {
  @override
  Future<LlmConfig?> readLlmConfigForScenario(LlmScenario scenario) async =>
      const LlmConfig(
        baseUrl: 'https://llm.example.com',
        apiKey: '',
        model: 'gpt-4o-mini',
      );
}

class _Speech
    implements
        SpeechRecognitionService,
        StreamingSpeechRecognitionService,
        RetainedAudioSpeechRecognitionService {
  final partials = StreamController<String>.broadcast();
  Completer<void>? initialization;
  Completer<void>? starting;
  Completer<SpeechRecognitionResult>? stopping;
  Object? initializationError;
  int initialized = 0;
  int starts = 0;
  int stops = 0;
  int cancellations = 0;
  int disposals = 0;
  bool active = false;

  @override
  bool get isRecording => active;
  @override
  Stream<String> get transcriptStream => partials.stream;
  @override
  String get recognitionMode => 'sentence';
  @override
  bool get usedFallback => false;

  @override
  Future<void> initialize() async {
    initialized++;
    await initialization?.future;
    if (initializationError != null) throw initializationError!;
  }

  @override
  Future<void> start() async {
    starts++;
    await starting?.future;
    active = true;
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    stops++;
    active = false;
    return await stopping?.future ??
        const SpeechRecognitionResult(text: '孩子的表达');
  }

  @override
  Uint8List takeLastAudio() => Uint8List(64);

  @override
  Future<void> cancel() async {
    cancellations++;
    active = false;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    active = false;
    await partials.close();
  }

  void release() {
    if (initialization != null && !initialization!.isCompleted) {
      initialization!.complete();
    }
    if (starting != null && !starting!.isCompleted) {
      starting!.complete();
    }
    if (stopping != null && !stopping!.isCompleted) {
      stopping!.complete(const SpeechRecognitionResult(text: 'late result'));
    }
  }
}

class _Audio extends PictureStoryAudioService {
  Completer<String>? nextSave;
  final held = <Completer<String>>[];
  final deleted = <String>[];
  int saves = 0;
  @override
  Future<String> savePcm16({required String id, required Uint8List pcm}) async {
    expect(pcm, Uint8List(64));
    saves++;
    final pending = nextSave;
    nextSave = null;
    if (pending != null) {
      held.add(pending);
      return pending.future;
    }
    return '/synthetic-audio/$id.wav';
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

class _Repository extends PictureStoryRepository {
  _Repository(this.ioZone);
  final Zone ioZone;
  Completer<void>? nextSave;
  bool failHeldSave = false;
  int completedSaves = 0;
  bool failAiSave = false;
  final held = <Completer<void>>[];
  final writes = <Future<void>>[];
  @override
  Future<void> save(
    PictureStoryPracticeRecord record, {
    void Function()? check,
  }) {
    final completion = Completer<void>();
    final snapshot = record.copy();
    if (snapshot.status == 'completed') completedSaves++;
    final pending = nextSave;
    nextSave = null;
    final fail = pending != null && failHeldSave;
    if (pending != null) held.add(pending);
    final saving = ioZone.run<Future<void>>(() async {
      try {
        await pending?.future;
        if (fail) throw StateError('synthetic delayed write failure');
        if (failAiSave && snapshot.feedbackJson.contains('"vision"')) {
          throw StateError('synthetic AI feedback write failure');
        }
        await super.save(snapshot, check: check);
        completion.complete();
      } on Object catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    writes.add(saving);
    return completion.future;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channels = <String>{};
  late _Repository repository;
  late _Audio audio;
  late List<_Speech> speeches;
  late List<_Speech> queued;
  late String promptId;

  void changeLifecycle(AppLifecycleState target) {
    if (binding.lifecycleState == target) return;
    if (target == AppLifecycleState.resumed) {
      if (binding.lifecycleState == AppLifecycleState.paused) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      if (binding.lifecycleState == AppLifecycleState.hidden) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      binding.handleAppLifecycleStateChanged(target);
      return;
    }
    if (binding.lifecycleState == AppLifecycleState.detached) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    if (binding.lifecycleState == AppLifecycleState.resumed) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    if (target == AppLifecycleState.inactive) return;
    if (binding.lifecycleState == AppLifecycleState.inactive) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (target == AppLifecycleState.hidden) return;
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }
    if (target == AppLifecycleState.detached) {
      binding.handleAppLifecycleStateChanged(target);
    }
  }

  void mockChannel(String name) {
    channels.add(name);
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  setUpAll(() {
    mockChannel('xyz.luan/audioplayers.global');
    mockChannel('xyz.luan/audioplayers.global/events');
    channels.add('xyz.luan/audioplayers');
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id =
              (call.arguments as Map<dynamic, dynamic>)['playerId'] as String;
          mockChannel('xyz.luan/audioplayers/events/$id');
        }
        if (call.method == 'getCurrentPosition' ||
            call.method == 'getDuration') {
          return 0;
        }
        return null;
      },
    );
  });
  tearDownAll(() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });
  setUp(() async {
    changeLifecycle(AppLifecycleState.resumed);
    await setUpHiveForTesting();
    await unlockParentForTesting();
    repository = _Repository(Zone.current);
    promptId = (await repository.savePrompt(
      prompt: pictureStoryFixture(),
      profileId: 'default',
    )).id;
    lockParentForTesting();
    audio = _Audio();
    speeches = [];
    queued = [];
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  Future<void> mount(
    WidgetTester tester, {
    http.Client? client,
    SettingsRepository? settings,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final speech in speeches) {
        speech.release();
      }
      for (final pending in audio.held) {
        if (!pending.isCompleted) {
          pending.complete('/synthetic-audio/cleanup.wav');
        }
      }
      for (final pending in repository.held) {
        if (!pending.isCompleted) pending.complete();
      }
      await tester.pump();
      await tester.runAsync(() async {
        for (final saving in repository.writes) {
          try {
            await saving;
          } on Object {
            /* The page handles write failures. */
          }
        }
      });
      await tester.pump();
      await drainHiveWritesForTesting(tester);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (client != null)
            llmExplainHttpClientProvider.overrideWithValue(client),
          if (client != null)
            settingsRepositoryProvider.overrideWithValue(settings ?? _VisionSettings()),
          pictureStoryRepositoryProvider.overrideWithValue(repository),
          pictureStoryAudioServiceProvider.overrideWithValue(audio),
          speechRecognitionServiceFactoryProvider.overrideWithValue(() {
            final speech = queued.isEmpty ? _Speech() : queued.removeAt(0);
            speeches.add(speech);
            return speech;
          }),
        ],
        child: MaterialApp(home: PictureStoryPracticePage(promptId: promptId)),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => repository.writes.first);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 50 && !ready(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  Future<void> background(
    WidgetTester tester, [
    AppLifecycleState state = AppLifecycleState.paused,
  ]) async {
    changeLifecycle(state);
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    changeLifecycle(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('所有非前台状态取消录音和60秒计时，回来后须再次主动开始', (tester) async {
    await mount(tester);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      await foreground(tester);
      await tap(tester, '说一说');
      final speech = speeches.last;
      expect(speech.active, isTrue);
      await background(tester, state);
      expect(speech.cancellations, greaterThanOrEqualTo(1));
      expect(speech.active, isFalse);
      await tester.pump(const Duration(seconds: 65));
      expect(speech.stops, 0);
      await foreground(tester);
      expect(find.widgetWithText(FilledButton, '说好了'), findsNothing);
      expect(speech.active, isFalse);
    }
    expect(audio.saves, 0);
  });

  testWidgets('准备态阻止双击，初始化晚到不能在后台开始录音', (tester) async {
    final speech = _Speech()..initialization = Completer<void>();
    queued.add(speech);
    await mount(tester);
    await tap(tester, '说一说');
    await tap(tester, '正在准备…');
    expect(speeches, [speech]);
    expect(speech.initialized, 1);
    await background(tester);
    speech.initialization!.complete();
    await tester.pump();
    expect(speech.starts, 0);
    expect(speech.active, isFalse);
    await foreground(tester);
    await tap(tester, '说一说');
    expect(speeches.last.active, isTrue);
  });

  testWidgets('旧启动晚完成会再次取消自身，不影响前台新录音', (tester) async {
    final old = _Speech()..starting = Completer<void>();
    queued.add(old);
    await mount(tester);
    await tap(tester, '说一说');
    await background(tester);
    await foreground(tester);
    await tap(tester, '说一说');
    final current = speeches.last;
    old.starting!.complete();
    await tester.pump();
    expect(old.active, isFalse);
    expect(current.active, isTrue);
    expect(current.cancellations, 0);
    expect(find.widgetWithText(FilledButton, '说好了'), findsOneWidget);
  });

  testWidgets('旧识别结果晚到不能保存音频或结束新录音', (tester) async {
    final old = _Speech()..stopping = Completer<SpeechRecognitionResult>();
    queued.add(old);
    await mount(tester);
    await tap(tester, '说一说');
    await tap(tester, '说好了');
    await background(tester);
    await foreground(tester);
    await tap(tester, '说一说');
    old.stopping!.complete(const SpeechRecognitionResult(text: '过期识别文本'));
    await tester.pump();
    expect(audio.saves, 0);
    expect(find.text('过期识别文本'), findsNothing);
    expect(speeches.last.active, isTrue);
    expect(find.widgetWithText(FilledButton, '说好了'), findsOneWidget);
  });

  testWidgets('音频保存晚到只清理未引用新文件，不改变当前录音与草稿', (tester) async {
    final pending = Completer<String>();
    audio.nextSave = pending;
    await mount(tester);
    await tap(tester, '说一说');
    await tap(tester, '说好了');
    expect(audio.saves, 1);
    await background(tester);
    await foreground(tester);
    await tap(tester, '说一说');
    pending.complete('/synthetic-audio/late.wav');
    await tester.pump();
    expect(audio.deleted, ['/synthetic-audio/late.wav']);
    expect(HiveBoxes.pictureStoryPractice.values.single.segments, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(speeches.last.active, isTrue);
  });

  testWidgets('已经保存的片段在后续录音后台取消后完整保留', (tester) async {
    await mount(tester);
    await tap(tester, '说一说');
    await tap(tester, '说好了');
    await waitUntil(
      tester,
      () => HiveBoxes.pictureStoryPractice.values.single.segments.length == 1,
    );
    final before = HiveBoxes.pictureStoryPractice.values.single.segmentsJson;
    await tap(tester, '说一说');
    await background(tester);
    await foreground(tester);
    await tester.runAsync(() => repository.writes.last);
    expect(HiveBoxes.pictureStoryPractice.values.single.segmentsJson, before);
    expect(audio.deleted, isEmpty);
    expect(find.text('第 1 段 · 1 秒'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '说好了'), findsNothing);
  });

  testWidgets('旧草稿保存失败晚返回不覆盖新录音状态和消息', (tester) async {
    final pending = Completer<void>();
    await mount(tester);
    repository.nextSave = pending;
    repository.failHeldSave = true;
    await tap(tester, '说一说');
    await tap(tester, '说好了');
    await tap(tester, '说一说');
    pending.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(speeches.last.active, isTrue);
    expect(find.widgetWithText(FilledButton, '说好了'), findsOneWidget);
    expect(find.text('练习暂时没有保存，请检查设备空间后重试'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('离页期间启动晚返回取消自身，不能setState或留下计时器', (tester) async {
    final speech = _Speech()..starting = Completer<void>();
    queued.add(speech);
    await mount(tester);
    await tap(tester, '说一说');
    await tester.pumpWidget(const SizedBox.shrink());
    speech.starting!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 65));
    expect(speech.active, isFalse);
    expect(speech.disposals, 1);
    expect(speech.stops, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初始化失败释放准备状态，可用新会话重试', (tester) async {
    queued.add(
      _Speech()
        ..initializationError = const SpeechRecognitionException('合成初始化失败'),
    );
    await mount(tester);
    await tap(tester, '说一说');
    expect(find.widgetWithText(FilledButton, '说一说'), findsOneWidget);
    expect(find.text('合成初始化失败'), findsOneWidget);
    await tap(tester, '说一说');
    expect(speeches.last.active, isTrue);
    expect(find.widgetWithText(FilledButton, '说好了'), findsOneWidget);
  });

  Future<void> recordSegment(
    WidgetTester tester, {
    http.Client? client,
    SettingsRepository? settings,
  }) async {
    await mount(tester, client: client, settings: settings);
    await tap(tester, '说一说');
    await tap(tester, '说好了');
    await waitUntil(
      tester,
      () =>
          HiveBoxes.pictureStoryPractice.values.single.segments.length == 1 &&
          tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, '说一说'),
                  )
                  .onPressed !=
              null,
    );
  }

  testWidgets('完成后留在已保存的反馈，重复点击只完成一次，缺录音保留文字', (tester) async {
    await recordSegment(tester);
    final complete = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.check_outlined),
        )
        .onPressed!;
    complete();
    complete();
    await tester.pump();
    await waitUntil(tester, () => find.text('练习已完成').evaluate().isNotEmpty);
    final saved = HiveBoxes.pictureStoryPractice.values.single;
    final feedback = jsonDecode(saved.feedbackJson) as Map<String, dynamic>;
    expect(saved.status, 'completed');
    expect(repository.completedSaves, 1);
    expect(
      find.text((feedback['highlights'] as List).first as String),
      findsOneWidget,
    );
    expect(find.text(feedback['suggestion'] as String), findsOneWidget);
    expect(find.text('孩子的表达'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('孩子的表达'));
    await waitUntil(
      tester,
      () => find.text('录音文件已清理，文字记录仍然保留').evaluate().isNotEmpty,
    );
    await background(tester);
    await foreground(tester);
    expect(find.text('练习已完成'), findsOneWidget);
    expect(repository.completedSaves, 1);
  });

  testWidgets('完成保存失败保留草稿及重试，成功后才显示结果', (tester) async {
    await recordSegment(tester);
    final pending = Completer<void>();
    repository.nextSave = pending;
    repository.failHeldSave = true;
    await tester.tap(find.byTooltip('完成练习').first);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    pending.complete();
    await waitUntil(
      tester,
      () => find.text('练习暂时没有保存，请检查设备空间后重试').evaluate().isNotEmpty,
    );
    expect(HiveBoxes.pictureStoryPractice.values.single.status, 'draft');
    expect(find.text('练习已完成'), findsNothing);
    await tester.tap(find.byTooltip('完成练习').first);
    await waitUntil(tester, () => find.text('练习已完成').evaluate().isNotEmpty);
    expect(HiveBoxes.pictureStoryPractice.values.single.status, 'completed');
  });

  testWidgets('完成写入前退后台取消旧结果，回来可重新完成', (tester) async {
    await recordSegment(tester);
    final pending = Completer<void>();
    repository.nextSave = pending;
    await tester.tap(find.byTooltip('完成练习').first);
    await tester.pump();
    await background(tester);
    pending.complete();
    await tester.runAsync(() => repository.writes.last);
    await foreground(tester);
    expect(HiveBoxes.pictureStoryPractice.values.single.status, 'draft');
    expect(find.text('练习已完成'), findsNothing);
    await tester.tap(find.byTooltip('完成练习').first);
    await waitUntil(tester, () => find.text('练习已完成').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('家长锁定时练习反馈仍保存成功备用模型，下次直接读取已成功的选择', (tester) async {
    final settings = SettingsRepository();
    await tester.runAsync(() async {
      await unlockParentForTesting();
      for (final (id, model) in [('bad', 'gpt-4o-bad'), ('good', 'gpt-4o-mini')]) {
        await settings.saveLlmProviderConfig(
          id: id,
          name: id,
          baseUrl: 'https://$id.example.com/v1',
          model: model,
          apiKey: 'synthetic-$id-key',
        );
      }
      await settings.setScenarioSelection(
        LlmScenario.assistant,
        providerId: 'bad',
        model: 'gpt-4o-bad',
      );
      lockParentForTesting();
    });
    final requests = <(String, String)>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add((request.url.host, body['model'] as String));
      if (request.url.host == 'bad.example.com') return http.Response('', 503);
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'choices': [
            {'message': {'content': '你说清了地点。再补充一个动作。'}},
          ],
        })),
        200,
      );
    });
    addTearDown(client.close);
    await recordSegment(tester, client: client, settings: settings);
    await tester.runAsync(() => tester.tap(find.byTooltip('完成练习').first));
    await waitUntil(tester, () => find.text('练习已完成').evaluate().isNotEmpty);
    expect(find.text('你说清了地点。再补充一个动作。'), findsOneWidget);
    expect(ParentAccessService.instance.isUnlocked, isFalse);
    expect(requests, [
      ('bad.example.com', 'gpt-4o-bad'),
      ('good.example.com', 'gpt-4o-mini'),
    ]);
    expect(settings.llmActiveProviderId, 'bad');
    expect(settings.providerIdForScenario(LlmScenario.assistant), 'good');
    expect(settings.modelForScenario(LlmScenario.assistant), 'gpt-4o-mini');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PictureStoryPracticePage)),
    );
    expect(container.read(llmSelectionVersionProvider), 1);
    final next = await tester.runAsync(
      () => settings.readLlmConfigForScenario(LlmScenario.assistant),
    );
    expect(next!.selection!.providerId, 'good');
    expect(next.model, 'gpt-4o-mini');
  });

  for (final failSave in [false, true]) {
    testWidgets('完成结果仅展示成功保存的反馈（AI保存失败：$failSave）', (tester) async {
      repository.failAiSave = failSave;
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '你说清了地点。再补充一个动作。'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await recordSegment(tester, client: client);
      await tester.runAsync(() => tester.tap(find.byTooltip('完成练习').first));
      await waitUntil(tester, () => find.text('练习已完成').evaluate().isNotEmpty);
      final saved = HiveBoxes.pictureStoryPractice.values.single;
      expect(requests, 1);
      expect(
        find.text('你说清了地点。再补充一个动作。'),
        failSave ? findsNothing : findsOneWidget,
      );
      expect(
        (jsonDecode(saved.feedbackJson) as Map)['source'],
        failSave ? 'local' : 'vision',
      );
      if (failSave) {
        expect(find.text('练习已保存，AI 反馈未能保存，先看看本地反馈。'), findsOneWidget);
        expect(find.text('你愿意把看到的内容说出来了。'), findsOneWidget);
      }
    });
  }
}
