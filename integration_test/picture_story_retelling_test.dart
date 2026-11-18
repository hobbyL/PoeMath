// fvm flutter test integration_test/picture_story_retelling_test.dart -d emulator-5554
// --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
// 独立应用和临时 Hive；录音转写与模型使用替身，不请求麦克风或云服务。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';

import '../test/helpers/hive_test_helper.dart';
import '../test/helpers/parent_access_test_helper.dart';
import '../test/helpers/picture_story_feedback_fixture.dart';
import '../test/helpers/picture_story_fixture.dart';

class _Speech
    implements SpeechRecognitionService, RetainedAudioSpeechRecognitionService {
  _Speech(this.text);
  final String text;
  bool _active = false;
  @override
  bool get isRecording => _active;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> start() async => _active = true;
  @override
  Future<SpeechRecognitionResult> stop() async {
    _active = false;
    return SpeechRecognitionResult(text: text);
  }

  @override
  Uint8List takeLastAudio() => Uint8List(64000);
  @override
  Future<void> cancel() async => _active = false;
  @override
  Future<void> dispose() async => _active = false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('分步引导、重讲续练、独立点评对比和完成次数在 Android 贯通', (tester) async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
    );
    await setUpHiveForTesting();
    await unlockParentForTesting();
    final repo = PictureStoryRepository();
    final base = PictureStoryCatalog.prompts.first;
    final prompt = await repo.savePrompt(
      prompt: pictureStoryFixture(id: 'local-native-retelling').copyWith(
        title: base.title,
        theme: base.theme,
        sceneFacts: base.sceneFacts,
        questions: base.questions,
        goals: base.goals,
        reference: base.reference,
      ),
      profileId: 'default',
    );
    final settings = SettingsRepository();
    await settings.saveLlmProviderConfig(
      id: 'fixture',
      name: 'fixture',
      baseUrl: 'https://fixture.example.com/v1',
      model: 'gpt-4o',
      apiKey: '',
    );
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: 'fixture',
      model: 'gpt-4o',
    );
    lockParentForTesting();
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      final messages = jsonDecode(request.body)['messages'] as List;
      final input = jsonDecode(
        (messages.last['content'] as List).first['text'] as String,
      );
      final result = pictureStoryFeedbackFixture(
        answer: input['answer'] as String,
        questionCount: prompt.questions.length,
      );
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(result)},
              },
            ],
          }),
        ),
        200,
      );
    });
    final production = createAppRouter();
    final router = GoRouter(
      initialLocation: '/test-expression',
      routes: [
        GoRoute(
          path: '/test-expression',
          builder: (_, _) => const PictureStoryPage(),
        ),
        for (final route in production.configuration.routes)
          if (route is GoRoute &&
              {
                AppRoutes.pictureStoryPractice,
                AppRoutes.pictureStoryHistory,
                AppRoutes.pictureStoryPromptHistory,
                AppRoutes.pictureStoryRecordDetail,
              }.contains(route.path))
            route,
      ],
    );
    var recording = 0;
    final capture = GlobalKey();
    var dark = false;
    var scale = 1.0;
    StateSetter? appearance;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          llmExplainHttpClientProvider.overrideWithValue(client),
          speechRecognitionServiceFactoryProvider.overrideWithValue(
            () => _Speech(recording++ == 0 ? '孩子在放风筝。' : '公园里，一个孩子带着小狗放风筝。'),
          ),
        ],
        child: StatefulBuilder(
          builder: (context, setState) {
            appearance = setState;
            return RepaintBoundary(
              key: capture,
              child: MaterialApp.router(
                routerConfig: router,
                theme: AppTheme.resolve(
                  subject: AppSubject.poem,
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
            );
          },
        ),
      ),
    );

    Future<void> tap(String text) async {
      final finder = find.text(text);
      await tester.ensureVisible(finder.last);
      await tester.pumpAndSettle();
      await tester.tap(finder.last);
      await tester.pumpAndSettle();
    }

    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue);
      await tester.pumpAndSettle();
    }

    Future<void> screenshot(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${Directory.systemTemp.path}/picture-retelling-$name.png',
        ).writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    }

    await tester.pumpAndSettle();
    await tap(prompt.title);
    expect(requests, 0);
    await screenshot('observe');
    await tap('下一问');
    expect(find.text(prompt.questions[1]), findsOneWidget);
    await tap('打开词句帮手');
    await tap('把事情讲顺');
    expect(find.text(prompt.reference), findsNothing);
    await screenshot('help');
    await tap('说一说');
    await tap('说好了');
    await waitFor(
      () => HiveBoxes.pictureStoryPractice.values.single.segments.length == 1,
    );
    await tester.tap(find.byTooltip('完成练习').first);
    await waitFor(
      () => requests == 1 && find.text('练习已完成').evaluate().isNotEmpty,
    );
    final first = repo.records().single.copy();
    expect(HiveBoxes.learningActivities.values.length, 1);
    await tap('再讲一遍');
    await tap('完整模式');
    await tap('说一说');
    await tap('说好了');
    await waitFor(
      () => repo.find(first.id)!.retellingDraft?.segments.length == 1,
    );
    expect(repo.records().single.answerText, '孩子在放风筝。');
    expect(requests, 1);
    router.pop();
    await tester.pumpAndSettle();
    await tap('继续未完成的重讲');
    expect(find.widgetWithText(TextField, '公园里，一个孩子带着小狗放风筝。'), findsOneWidget);
    await tester.tap(find.byTooltip('完成练习').first);
    await waitFor(
      () => requests == 2 && find.text('练习已完成').evaluate().isNotEmpty,
    );
    final completed = repo.records().single;
    expect(completed.id, first.id);
    expect(completed.takes.map((t) => t.answerText), [
      '孩子在放风筝。',
      '公园里，一个孩子带着小狗放风筝。',
    ]);
    expect(completed.completedAt, first.completedAt);
    expect(
      completed.takes.map((t) => t.feedbackJson),
      everyElement(contains('"source":"vision"')),
    );
    expect(HiveBoxes.learningActivities.values.length, 1);
    await tap('比较两遍表达');
    await screenshot('compare');
    appearance!(() {
      dark = true;
      scale = 2;
    });
    await tester.pumpAndSettle();
    await screenshot('compare-dark-large');
    expect(tester.takeException(), isNull);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    for (
      var i = 0;
      i < 30 &&
          tester.view.physicalSize.width < tester.view.physicalSize.height;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await screenshot('landscape');
    expect(tester.takeException(), isNull);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    production.dispose();
    client.close();
    await tearDownHiveForTesting();
  });
}
