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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_history_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_review_page.dart';

import '../test/helpers/hive_test_helper.dart';
import '../test/helpers/parent_access_test_helper.dart';
import '../test/helpers/picture_story_feedback_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('历史入口重评、保留原版本、退出重进与原生显示', (tester) async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
    );
    await setUpHiveForTesting();
    await unlockParentForTesting();
    final repo = PictureStoryRepository();
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
      promptId: 'kite-in-the-park',
      promptVersion: 1,
      startedAt: DateTime(2026),
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
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          llmExplainHttpClientProvider.overrideWithValue(client),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.light,
            ),
            home: const PictureStoryHistoryPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('修改表达并重新点评'));
    await tester.tap(find.text('修改表达并重新点评'));
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
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File(
        '${Directory.systemTemp.path}/picture-story-feedback-native.png',
      );
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      AppLogger.d(
        'EVIDENCE=${file.path}',
        tag: 'PictureStoryFeedbackNativeTest',
      );
    } finally {
      image.dispose();
    }
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('修改表达并重新点评'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('修改表达并重新点评')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改表达并重新点评'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      saved.answerText,
    );
    expect(requests, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    lockParentForTesting();
    await tearDownHiveForTesting();
  });
}
