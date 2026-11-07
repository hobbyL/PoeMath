// fvm flutter test integration_test/picture_story_feedback_test.dart -d emulator-5554
//   --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
// 独立包与临时 Hive；模型为确定性替身，不上传儿童数据或使用云额度。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_history_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_record_detail_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_review_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_scene_scaffold.dart';

import '../test/helpers/hive_test_helper.dart';
import '../test/helpers/parent_access_test_helper.dart';
import '../test/helpers/picture_story_feedback_fixture.dart';
import '../test/helpers/picture_story_fixture.dart';

Future<void> capturePage(GlobalKey capture, String name) async {
  final boundary =
      capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('${Directory.systemTemp.path}/$name.png');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    AppLogger.d('EVIDENCE=${file.path}', tag: 'PictureStoryFeedbackNativeTest');
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('题目卡片进入多次记录、重评不增次数、退出重进与原生显示', (tester) async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
    );
    await setUpHiveForTesting();
    await unlockParentForTesting();
    final repo = PictureStoryRepository();
    final content = PictureStoryCatalog.prompts.first;
    final prompt = await repo.savePrompt(
      prompt: pictureStoryFixture(id: 'local-native-history').copyWith(
        title: content.title,
        sceneFacts: content.sceneFacts,
        questions: content.questions,
        goals: content.goals,
        reference: content.reference,
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
    final original = PictureStoryPracticeRecord(
      id: 'native-review',
      profileId: 'default',
      promptId: prompt.id,
      promptVersion: 1,
      startedAt: DateTime(2026, 1, 2, 15, 30),
      status: 'completed',
      segmentsJson: '[]',
      feedbackJson: '{"source":"unavailable","text":"本次未获得 AI 点评"}',
    );
    original.setSegments([
      const PictureStorySegment(
        id: 'audio',
        position: 0,
        audioPath: '/original.wav',
        durationSeconds: 8,
        transcript: '孩子放风筝。',
      ),
    ]);
    await repo.save(original);
    await repo.save(
      PictureStoryPracticeRecord(
        id: 'native-review-older',
        profileId: 'default',
        promptId: prompt.id,
        promptVersion: 1,
        startedAt: DateTime(2026, 1, 1, 10, 5),
        status: 'completed',
        segmentsJson: '[]',
        answerText: '有一个孩子和一只风筝。',
      ),
    );
    lockParentForTesting();
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      final messages = jsonDecode(request.body)['messages'] as List;
      final input = jsonDecode(
        (messages.last['content'] as List).first['text'] as String,
      );
      final answer = input['answer'] as String;
      final result = pictureStoryFeedbackFixture(
        answer: answer,
        questionCount: 3,
      );
      result['summary'] = '你说清了谁在做什么，还补充了地点。';
      result['dimensions'] = [
        {
          'id': 'picture',
          'status': 'met',
          'evidence': answer,
          'reason': '孩子和风筝与图中的主要内容对应。',
        },
        {
          'id': 'response',
          'status': 'developing',
          'evidence': answer,
          'reason': '说到了地点和动作，还可以看看图里是否有小动物。',
        },
        {
          'id': 'expression',
          'status': 'met',
          'evidence': answer,
          'reason': '一句话中包含人物、地点和动作，意思清楚。',
        },
      ];
      result['suggestions'] = [
        {
          'original': answer,
          'replacement': '公园里，一个孩子牵着风筝线放风筝。',
          'reason': '补上牵着线的动作，让画面更具体。',
        },
      ];
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
    final capture = GlobalKey();
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          llmExplainHttpClientProvider.overrideWithValue(client),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.light,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('练习记录 · 2 次'), findsOneWidget);
    await capturePage(capture, 'picture-story-cards-native');
    await tester.tap(find.text('练习记录 · 2 次'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PictureStoryHistoryPage>(find.byType(PictureStoryHistoryPage))
          .promptId,
      prompt.id,
    );
    expect(find.text('已完成 2 次练习'), findsNothing);
    expect(find.text(prompt.reference), findsOneWidget);
    expect(find.text('题目与参考表达'), findsNothing);
    expect(find.text('修改表达并重新点评'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    await capturePage(capture, 'picture-story-history-native');
    final historyBack = tester.getRect(find.byType(BackButton));
    final historyImage = tester.getRect(find.byType(PictureStoryImageView));
    final historyScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    historyScroll.position.jumpTo(160);
    await tester.pumpAndSettle();
    final movedImage = tester.getRect(find.byType(PictureStoryImageView));
    expect(historyImage.top - movedImage.top, greaterThan(0));
    expect(historyImage.top - movedImage.top, lessThan(160));
    expect(tester.getRect(find.byType(BackButton)), historyBack);
    await capturePage(capture, 'picture-story-history-parallax-native');
    await tester.scrollUntilVisible(find.text('孩子放风筝。'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('孩子放风筝。'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PictureStoryRecordDetailPage>(
            find.byType(PictureStoryRecordDetailPage),
          )
          .recordId,
      original.id,
    );
    expect(find.text('练习详情'), findsOneWidget);
    expect(find.text('第 2 次练习'), findsNothing);
    expect(find.text(prompt.reference), findsNothing);
    expect(find.text('我的表达'), findsOneWidget);
    await tester.tap(find.byTooltip('查看题目'));
    await tester.pumpAndSettle();
    expect(find.text(prompt.reference), findsOneWidget);
    await tester.tap(find.byTooltip('隐藏题目'));
    await tester.pumpAndSettle();
    expect(find.text(prompt.reference), findsNothing);
    expect(requests, 0);
    final edit = find.text('修改表达并重新点评');
    expect(edit.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('第 1 段录音')).dx,
      closeTo(tester.getTopLeft(find.text('我的表达')).dx, 0.01),
    );
    expect(
      tester.getRect(find.text('第 1 段录音')).top,
      greaterThan(tester.getRect(find.text('孩子放风筝。')).bottom),
    );
    expect(
      tester.getRect(find.text('点评')).top,
      greaterThan(tester.getRect(find.text('第 1 段录音')).bottom),
    );
    await tester.scrollUntilVisible(edit, 250);
    await tester.pumpAndSettle();
    await capturePage(capture, 'picture-story-history-expanded-native');
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryReviewPage), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '公园里，一个孩子正在放风筝。');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存并重新点评'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并重新点评'));
    for (var i = 0; i < 100 && repo.find(original.id)!.revisions.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    final saved = repo.find(original.id)!;
    expect(saved.revisions.length, 2);
    expect(saved.segmentsJson, original.segmentsJson);
    expect(saved.revisions.first.answer, '孩子放风筝。');
    expect(requests, 1);
    await capturePage(capture, 'picture-story-feedback-native');
    router.pop();
    await tester.pumpAndSettle();
    await capturePage(capture, 'picture-story-detail-feedback-native');
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('逐题看看'), findsNothing);
    expect(find.text('可以再补充'), findsNothing);
    expect(find.text('说清楚了'), findsNothing);
    for (final question in prompt.questions) {
      expect(find.text(question), findsOneWidget);
    }
    await Scrollable.ensureVisible(
      tester.element(find.text(prompt.questions.first)),
      alignment: 0,
    );
    await tester.pumpAndSettle();
    await capturePage(capture, 'picture-story-questions-native');
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(edit), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      saved.answerText,
    );
    expect(requests, 1);
    expect(repo.records(promptId: prompt.id).length, 2);
    expect(repo.find('native-review-older')!.answerText, '有一个孩子和一只风筝。');
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text(saved.answerText), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('练习记录 · 2 次'), findsOneWidget);
    await tester.tap(find.byTooltip('全部记录'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PictureStoryHistoryPage>(find.byType(PictureStoryHistoryPage))
          .promptId,
      isNull,
    );
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text(prompt.title));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    final practiceBack = tester.getRect(find.byType(BackButton));
    final practiceComplete = tester.getRect(find.byTooltip('完成练习'));
    await capturePage(capture, 'picture-story-practice-native');
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(160);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(BackButton)), practiceBack);
    expect(tester.getRect(find.byTooltip('完成练习')), practiceComplete);
    await capturePage(capture, 'picture-story-practice-parallax-native');
    await tester.tap(find.byTooltip('完成练习'));
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.text('请先点击“说一说”，录制一段表达。'),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(requests, 1);
    expect(
      repo.records(promptId: prompt.id).where((r) => r.status == 'completed'),
      hasLength(2),
    );
    await capturePage(capture, 'picture-story-completion-hint-native');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryPage), findsOneWidget);
    final squareBytes = await pictureStoryPng(width: 200, height: 200);
    final squareClosed =
        Navigator.of(tester.element(find.byType(PictureStoryPage))).push<void>(
          MaterialPageRoute(
            builder: (_) => ProviderScope(
              overrides: [
                pictureStoryImageBytesProvider('square-native')
                    .overrideWith((ref) async => squareBytes),
              ],
              child: const PictureStorySceneScaffold(
                image: PictureStoryImage.local('square-native'),
                semanticLabel: '正方形题图',
                child: Text('正方形题图'),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
    final square = tester.getRect(find.byType(Image));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(square.left, screen.left);
    expect(square.right, screen.right);
    expect(square.width, square.height);
    await capturePage(capture, 'picture-story-square-native');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await squareClosed;
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    production.dispose();
    client.close();
    lockParentForTesting();
    await tearDownHiveForTesting();
  });
}
