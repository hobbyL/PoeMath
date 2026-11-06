import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_review_page.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';
import '../../../helpers/picture_story_feedback_fixture.dart';
import '../../../helpers/picture_story_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late PictureStoryRepository repo;
  late SettingsRepository settings;
  late PictureStoryPracticeRecord original;
  final navigator = GlobalKey<NavigatorState>();
  setUp(() async {
    ProfileScope.reset();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await setUpHiveForTesting();
    await unlockParentForTesting();
    repo = PictureStoryRepository();
    final prompt = await repo.savePrompt(
      prompt: pictureStoryFixture(),
      profileId: 'default',
    );
    settings = SettingsRepository();
    await settings.saveLlmProviderConfig(
      id: 'review',
      name: 'review',
      baseUrl: 'https://review.example.com/v1',
      model: 'gpt-4o',
      apiKey: '',
    );
    await settings.setScenarioSelection(
      LlmScenario.pictureStoryFeedback,
      providerId: 'review',
      model: 'gpt-4o',
    );
    original = PictureStoryPracticeRecord(
      id: 'record',
      profileId: 'default',
      promptId: prompt.id,
      promptVersion: prompt.version,
      startedAt: DateTime(2026),
      status: 'completed',
      segmentsJson: '[]',
      revisionDraft: '小猫在窗前。',
      feedbackJson: '{"source":"vision","text":"这是最初的点评"}',
    );
    original.setSegments([
      const PictureStorySegment(
        id: 'audio',
        position: 0,
        audioPath: '/original.wav',
        durationSeconds: 8,
        transcript: '最初的答案',
      ),
    ]);
    await repo.save(original);
    lockParentForTesting();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 250 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  Future<void> mount(
    WidgetTester tester,
    http.Client client, {
    bool narrow = false,
  }) async {
    tester.view.physicalSize = narrow
        ? const Size(320, 900)
        : const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
      client.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          llmExplainHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const PictureStoryReviewPage(recordId: 'record'),
                  ),
                ),
                child: const Text('打开记录'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开记录'));
    await tester.pumpAndSettle();
  }

  Future<void> evaluate(WidgetTester tester) async {
    await tester.ensureVisible(find.text('保存并重新点评'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('保存并重新点评')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('保存并重新点评')));
    await tester.pump();
  }

  http.Response valid(http.Request request) {
    final body = jsonDecode(request.body) as Map;
    final parts = (body['messages'] as List).last['content'] as List;
    final answer =
        jsonDecode(parts.first['text'] as String)['answer'] as String;
    final image = base64Decode(
      (parts.last['image_url']['url'] as String).split(',').last,
    );
    final header = ByteData.sublistView(image);
    expect((header.getUint32(16), header.getUint32(20)), (1024, 768));
    return http.Response.bytes(
      utf8.encode(pictureStoryFeedbackResponse(answer: answer)),
      200,
    );
  }

  testWidgets('窄屏大字重评保留原录音与旧版，双击只提交一版', (tester) async {
    var requests = 0;
    final held = Completer<http.Response>();
    late http.Request incoming;
    await mount(
      tester,
      MockClient((request) {
        requests++;
        incoming = request;
        return held.future;
      }),
      narrow: true,
    );
    await evaluate(tester);
    await waitFor(tester, () => requests == 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '正在点评…'))
          .onPressed,
      isNull,
    );
    held.complete(valid(incoming));
    await waitFor(
      tester,
      () =>
          repo.find('record')!.revisions.isNotEmpty &&
          find.byType(TextField).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    final saved = repo.find('record')!;
    expect(saved.answerText, '小猫在窗前。');
    expect(saved.segmentsJson, original.segmentsJson);
    expect(saved.revisions.length, 2);
    expect(saved.revisions.first.answer, '最初的答案');
    expect(saved.revisions.first.feedbackJson, original.feedbackJson);
    expect(
      jsonDecode(saved.revisions.last.feedbackJson)['answer'],
      saved.answerText,
    );
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('清空文字持久化为空草稿，不请求模型；重新进入不恢复原答案', (tester) async {
    var requests = 0;
    await mount(
      tester,
      MockClient((request) async {
        requests++;
        return valid(request);
      }),
    );
    await tester.runAsync(() => tester.enterText(find.byType(TextField), ''));
    await waitFor(tester, () => repo.find('record')!.revisionDraft == '');
    await evaluate(tester);
    expect(find.text('请先填写表达文字，再重新点评。'), findsOneWidget);
    expect(requests, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开记录'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(repo.find('record')!.answerText, '最初的答案');
    expect(requests, 0);
  });

  testWidgets('无效反馈保留修改草稿及旧版，可主动重试成功', (tester) async {
    var requests = 0;
    await mount(
      tester,
      MockClient((request) async {
        requests++;
        return requests == 1
            ? http.Response(
                '{"choices":[{"message":{"content":"invalid"}}]}',
                200,
              )
            : valid(request);
      }),
    );
    await evaluate(tester);
    await waitFor(
      tester,
      () => find.textContaining('本次未获得 AI 点评。').evaluate().isNotEmpty,
    );
    expect(repo.find('record')!.revisionDraft, '小猫在窗前。');
    expect(repo.find('record')!.feedbackJson, original.feedbackJson);
    expect(repo.find('record')!.revisions, isEmpty);
    await evaluate(tester);
    await waitFor(
      tester,
      () =>
          repo.find('record')!.revisions.length == 2 &&
          find.byType(TextField).evaluate().isEmpty,
    );
    expect(requests, 2);
  });

  for (final interruption in ['离页', '后台', '切换档案后切回']) {
    testWidgets('$interruption 后晚到的点评不覆盖草稿或旧答案', (tester) async {
      final held = Completer<http.Response>();
      http.Request? incoming;
      await mount(
        tester,
        MockClient((request) {
          incoming = request;
          return held.future;
        }),
      );
      await evaluate(tester);
      await waitFor(tester, () => incoming != null);
      if (interruption == '离页') {
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      } else if (interruption == '后台') {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      } else {
        ProfileScope.switchTo('another');
        ProfileScope.reset();
      }
      held.complete(valid(incoming!));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(repo.find('record')!.revisionDraft, '小猫在窗前。');
      expect(repo.find('record')!.answerText, '最初的答案');
      expect(repo.find('record')!.revisions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
