// fvm flutter test integration_test/picture_story_feedback_test.dart -d emulator-5554
//   --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
// 独立包与临时 Hive；模型为确定性替身，不上传儿童数据或使用云额度。
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
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/color_tokens.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
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
import 'package:poemath/features/chinese/expression/widgets/picture_story_history_prompt_card.dart';
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
    Future<void> rotate(DeviceOrientation orientation) async {
      await SystemChrome.setPreferredOrientations([orientation]);
      final landscape = orientation == DeviceOrientation.landscapeLeft;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final size = tester.view.physicalSize;
        if ((size.width > size.height) == landscape) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('设备未切换到 $orientation');
    }

    addTearDown(
      () => SystemChrome.setPreferredOrientations(DeviceOrientation.values),
    );
    await rotate(DeviceOrientation.portraitUp);
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
            // 实际应用关闭转场/入场动画时，仍须支持跟随手势的视差和下拉。
            builder: (context, child) =>
                PageAnimationScope(enabled: false, child: child!),
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.light,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('练习记录 · 2 次'), findsOneWidget);
    await capturePage(capture, 'picture-story-cards-native');
    await tester.tap(find.byTooltip('练习记录 · 2 次'));
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
    try {
      await rotate(DeviceOrientation.landscapeLeft);
      final card = tester.getRect(find.byType(PictureStoryHistoryPromptCard));
      final viewport = tester.getRect(find.byType(Scaffold));
      expect(card.left, closeTo(SpacingTokens.md, .01));
      expect(viewport.right - card.right, closeTo(SpacingTokens.md, .01));
      expect(find.byType(ImageFiltered), findsOneWidget);
      await capturePage(capture, 'picture-story-history-landscape-native');
    } finally {
      await rotate(DeviceOrientation.portraitUp);
    }
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
    final detailEdit = find.widgetWithText(FilledButton, '修改表达并重新点评');
    final detailEditRect = tester.getRect(detailEdit);
    await tester.tap(find.byTooltip('查看题目'));
    await tester.pumpAndSettle();
    expect(find.text(prompt.reference), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    final detailScene = find.byKey(const ValueKey('picture-story-scene-image'));
    final detailImage = tester.getRect(detailScene);
    final detailBack = tester.getRect(find.byType(BackButton));
    final detailToggle = tester.getRect(find.byTooltip('隐藏题目'));
    expect(detailImage.top, closeTo(0, .01));
    expect(detailImage.left, closeTo(0, .01));
    expect(tester.getRect(detailEdit), detailEditRect);
    await capturePage(capture, 'picture-story-record-expanded-native');
    final detailScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    detailScroll.position.jumpTo(120);
    await tester.pumpAndSettle();
    expect(detailImage.top - tester.getRect(detailScene).top, closeTo(36, .01));
    expect(tester.getRect(find.byType(BackButton)), detailBack);
    expect(tester.getRect(find.byTooltip('隐藏题目')), detailToggle);
    expect(tester.getRect(detailEdit), detailEditRect);
    detailScroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    final detailGesture = await tester.startGesture(detailImage.center);
    await detailGesture.moveBy(const Offset(0, 50));
    await tester.pump(const Duration(milliseconds: 16));
    await detailGesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(detailScene).width, greaterThan(detailImage.width));
    expect(tester.getRect(detailScene).top, closeTo(0, .01));
    expect(tester.getRect(detailEdit), detailEditRect);
    await tester.pump(const Duration(milliseconds: 200));
    await detailGesture.up();
    await tester.pumpAndSettle();
    try {
      await rotate(DeviceOrientation.landscapeLeft);
      final landscape = tester.getRect(detailScene);
      final screen = tester.getRect(find.byType(Scaffold));
      expect(landscape.width / landscape.height, closeTo(4 / 3, .01));
      expect(landscape.center.dx, closeTo(screen.center.dx, .01));
      expect(find.byType(ImageFiltered), findsOneWidget);
      final card = tester.getRect(find.byType(PictureStoryHistoryPromptCard));
      expect(card.left, closeTo(SpacingTokens.md, .01));
      expect(screen.right - card.right, closeTo(SpacingTokens.md, .01));
      expect(detailEdit.hitTestable(), findsOneWidget);
      await capturePage(
        capture,
        'picture-story-record-expanded-landscape-native',
      );
    } finally {
      await rotate(DeviceOrientation.portraitUp);
    }
    await tester.tap(find.byTooltip('隐藏题目'));
    await tester.pumpAndSettle();
    expect(find.text(prompt.reference), findsNothing);
    expect(find.text('练习详情'), findsOneWidget);
    expect(tester.getRect(detailEdit), detailEditRect);
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
    expect(find.byTooltip('练习记录 · 2 次'), findsOneWidget);
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
    final sceneRaster = find.descendant(
      of: find.byKey(const ValueKey('picture-story-scene-image')),
      matching: find.byType(Image),
    );
    final squareBytes = await pictureStoryContrastPng();
    final squareClosed =
        Navigator.of(tester.element(find.byType(PictureStoryPage))).push<void>(
          MaterialPageRoute(
            builder: (_) => ProviderScope(
              overrides: [
                pictureStoryImageBytesProvider('square-native')
                    .overrideWith((ref) async => squareBytes),
              ],
              child: PictureStorySceneScaffold(
                image: const PictureStoryImage.local('square-native'),
                semanticLabel: '正方形题图',
                actions: [
                  IconButton(
                    tooltip: '隐藏提示',
                    isSelected: true,
                    onPressed: () {},
                    icon: const Icon(Icons.lightbulb_outline),
                    selectedIcon: const Icon(Icons.tips_and_updates_outlined),
                  ),
                  IconButton(
                    tooltip: '完成练习',
                    onPressed: () {},
                    icon: const Icon(Icons.check_outlined),
                  ),
                ],
                child: const Text('正方形题图'),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
    final square = tester.getRect(sceneRaster);
    final screen = tester.getRect(find.byType(Scaffold));
    expect(square.left, screen.left);
    expect(square.right, screen.right);
    expect(square.width, square.height);
    final adaptiveBack = find.descendant(
      of: find.byType(BackButton),
      matching: find.byType(Icon),
    );
    final adaptiveHint = find.byIcon(Icons.tips_and_updates_outlined);
    final adaptiveComplete = find.byIcon(Icons.check_outlined);
    Color? iconColor(Finder icon) => IconTheme.of(tester.element(icon)).color;
    for (
      var i = 0;
      i < 60 && iconColor(adaptiveBack) != ColorTokens.mathSurface;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(iconColor(adaptiveBack), ColorTokens.mathSurface);
    expect(iconColor(adaptiveHint), ColorTokens.hintAmber);
    expect(iconColor(adaptiveComplete), ColorTokens.mathSurface);
    await capturePage(capture, 'picture-story-square-native');
    final adaptiveBackRect = tester.getRect(find.byType(BackButton));
    final adaptiveCompleteRect = tester.getRect(find.byTooltip('完成练习'));
    final gesture = await tester.startGesture(square.center);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 100));
    final stretched = tester.getRect(sceneRaster);
    expect(stretched.top, closeTo(0, .01));
    expect(stretched.width, greaterThan(square.width));
    expect(stretched.height, greaterThan(square.height));
    expect(stretched.width / stretched.height, closeTo(1, .01));
    expect(tester.getRect(find.byType(BackButton)), adaptiveBackRect);
    expect(tester.getRect(find.byTooltip('完成练习')), adaptiveCompleteRect);
    expect(iconColor(adaptiveBack), ColorTokens.mathSurface);
    await capturePage(capture, 'picture-story-stretched-native');
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    final restored = tester.getRect(sceneRaster);
    expect(restored.top, closeTo(square.top, .1));
    expect(restored.width, closeTo(square.width, .1));
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(220);
    await tester.pumpAndSettle();
    expect(iconColor(adaptiveBack), ColorTokens.poemInk);
    expect(iconColor(adaptiveHint), ColorTokens.mathYellow);
    expect(iconColor(adaptiveComplete), ColorTokens.poemInk);
    expect(tester.getRect(find.byType(BackButton)), adaptiveBackRect);
    await capturePage(capture, 'picture-story-contrast-scrolled-native');
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();

    try {
      await rotate(DeviceOrientation.landscapeLeft);
      final landscapeImage = tester.getRect(sceneRaster);
      final landscapeScreen = tester.getRect(find.byType(Scaffold));
      expect(landscapeImage.width, closeTo(landscapeImage.height, .01));
      expect(landscapeImage.center.dx, closeTo(landscapeScreen.center.dx, .01));
      expect(landscapeImage.left, greaterThan(landscapeScreen.left));
      expect(landscapeImage.right, lessThan(landscapeScreen.right));
      expect(landscapeImage.top, closeTo(0, .01));
      expect(iconColor(adaptiveBack), ColorTokens.poemInk);
      expect(iconColor(adaptiveComplete), ColorTokens.poemInk);
      expect(IconTheme.of(tester.element(adaptiveBack)).shadows, isNotEmpty);
      expect(find.byType(ImageFiltered), findsOneWidget);
      await capturePage(capture, 'picture-story-landscape-native');
      final landscapeBack = tester.getRect(find.byType(BackButton));
      final landscapeGesture = await tester.startGesture(landscapeImage.center);
      await landscapeGesture.moveBy(const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 16));
      await landscapeGesture.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 100));
      final landscapeStretch = tester.getRect(sceneRaster);
      expect(landscapeStretch.top, closeTo(0, .01));
      expect(landscapeStretch.width, greaterThan(landscapeImage.width));
      expect(landscapeStretch.width / landscapeStretch.height, closeTo(1, .01));
      expect(tester.getRect(find.byType(BackButton)), landscapeBack);
      await tester.pump(const Duration(milliseconds: 200));
      await landscapeGesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(sceneRaster).width,
        closeTo(landscapeImage.width, .1),
      );
    } finally {
      await rotate(DeviceOrientation.portraitUp);
    }
    expect(tester.getRect(sceneRaster).width, closeTo(square.width, .1));
    expect(iconColor(adaptiveBack), ColorTokens.mathSurface);
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
