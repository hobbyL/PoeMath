import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_review_page.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  test('只有完成背诵或测试通过才允许推进复习', () {
    expect(PoemPracticeResult.recitationCompleted.completesReview, isTrue);
    expect(PoemPracticeResult.quizPassed.completesReview, isTrue);
    expect(PoemPracticeResult.quizFailed.completesReview, isFalse);
    expect(PoemPracticeResult.cancelled.completesReview, isFalse);
  });

  testWidgets('直接返回不推进复习轮次', (tester) async {
    _setViewport(tester);
    await tester.runAsync(() => _seedReview('poem_1', '静夜思'));
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router));
    await _openFillQuiz(tester, '静夜思');
    await tester.tap(find.text('直接返回'));
    await _pumpUi(tester);

    expect(ReviewRepository().get('poem_1')!.currentRound, 0);
  });

  testWidgets('测试失败不推进复习轮次', (tester) async {
    _setViewport(tester);
    await tester.runAsync(() => _seedReview('poem_1', '静夜思'));
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router));
    await _openFillQuiz(tester, '静夜思');
    await tester.tap(find.text('测试失败'));
    await _pumpUi(tester);

    expect(ReviewRepository().get('poem_1')!.currentRound, 0);
  });

  testWidgets('批量复习遇到失败后停止且不推进后续诗词', (tester) async {
    _setViewport(tester);
    await tester.runAsync(() async {
      await _seedReview('poem_1', '静夜思');
      await _seedReview('poem_2', '春晓');
    });
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router));
    await _pumpUi(tester);
    await tester.tap(find.text('一键复习今日全部（2 首）'));
    await _pumpUi(tester);
    await tester.tap(find.text('测试失败'));
    await _pumpUi(tester);

    expect(find.text('测试失败'), findsNothing);
    expect(find.text('已完成 0/2 首，剩余复习未记录'), findsOneWidget);
    expect(ReviewRepository().get('poem_1')!.currentRound, 0);
    expect(ReviewRepository().get('poem_2')!.currentRound, 0);
  });
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _seedReview(String poemId, String title) async {
  await HiveBoxes.poems.put(
    poemId,
    Poem(
      id: poemId,
      title: title,
      author: '测试作者',
      dynasty: '唐',
      content: '白日依山尽，\n黄河入海流。',
      pinyin: '',
      layer: 'core',
      grade: 1,
    ),
  );
  await PoemProgressRepository().save(
    PoemProgress(
      poemId: poemId,
      profileId: 'default',
      status: LearningStatus.reviewing,
    ),
  );
  await ReviewRepository().save(
    ReviewSchedule(
      poemId: poemId,
      profileId: 'default',
      nextReviewDate: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  );
}

Widget _buildApp(GoRouter router) {
  return ProviderScope(
    child: MaterialApp.router(routerConfig: router),
  );
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.poemReview,
    routes: [
      GoRoute(
        path: AppRoutes.poemReview,
        builder: (context, state) => const PoemReviewPage(),
      ),
      GoRoute(
        path: AppRoutes.poemQuiz,
        builder: (context, state) => const _PracticeResultPage(),
      ),
      GoRoute(
        path: AppRoutes.poemRecite,
        builder: (context, state) => const _PracticeResultPage(),
      ),
    ],
  );
}

Future<void> _openFillQuiz(WidgetTester tester, String poemTitle) async {
  await _pumpUi(tester);
  expect(find.text(poemTitle), findsOneWidget);
  await tester.tap(find.text('复习'));
  await _pumpUi(tester);
  await tester.tap(find.text('填空测试'));
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

class _PracticeResultPage extends StatelessWidget {
  const _PracticeResultPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: context.pop,
              child: const Text('直接返回'),
            ),
            TextButton(
              onPressed: () => context.pop(PoemPracticeResult.quizFailed),
              child: const Text('测试失败'),
            ),
            TextButton(
              onPressed: () => context.pop(PoemPracticeResult.quizPassed),
              child: const Text('测试通过'),
            ),
          ],
        ),
      ),
    );
  }
}
