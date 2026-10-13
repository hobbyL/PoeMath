import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_practice_score.dart';
import 'package:poemath/features/poem/poem_review_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

import '../../helpers/hive_test_helper.dart';

/// 内存版复习仓储：绕开 fake-async 区内的真实 Hive 文件 IO
/// （pumpAndSettle 挂起问题的既有解法），断言直接读内存。
class _FakeReviewRepository extends ReviewRepository {
  final Map<String, ReviewSchedule> _store = {};

  @override
  ReviewSchedule? get(String poemId) => _store[poemId];

  @override
  Future<void> save(ReviewSchedule schedule) async {
    _store[schedule.poemId] = schedule;
  }

  @override
  List<ReviewSchedule> getDueToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _store.values
        .where(
          (s) =>
              !s.isCompleted &&
              !s.nextReviewDate.isAfter(today.add(const Duration(days: 1))),
        )
        .toList();
  }

  @override
  List<ReviewSchedule> getActive() =>
      _store.values.where((s) => !s.isCompleted).toList();
}

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
    final reviewRepo = _FakeReviewRepository();
    await tester.runAsync(() => _seedReview(reviewRepo, 'poem_1', '静夜思'));
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router, reviewRepo: reviewRepo));
    await _openFillQuiz(tester, '静夜思');
    await tester.tap(find.text('直接返回'));
    await _pumpUi(tester);

    expect(reviewRepo.get('poem_1')!.currentRound, 0);
  });

  testWidgets('测试失败不推进复习轮次', (tester) async {
    _setViewport(tester);
    final reviewRepo = _FakeReviewRepository();
    await tester.runAsync(() => _seedReview(reviewRepo, 'poem_1', '静夜思'));
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router, reviewRepo: reviewRepo));
    await _openFillQuiz(tester, '静夜思');
    await tester.tap(find.text('测试失败'));
    await _pumpUi(tester);

    expect(reviewRepo.get('poem_1')!.currentRound, 0);
  });

  testWidgets('测试失败写入 lastScore 且明天到期', (tester) async {
    _setViewport(tester);
    final reviewRepo = _FakeReviewRepository();
    await tester.runAsync(() => _seedReview(reviewRepo, 'poem_1', '静夜思'));
    final router = _buildRouter();
    addTearDown(router.dispose);

    // 受控 container：_PracticeResultPage pop 前由测试预置侧信道得分（<0.8），
    // 模拟 quiz 页 pop 前写入最终得分的纪律。
    final container = ProviderContainer(
      overrides: [reviewRepoProvider.overrideWith((_) => reviewRepo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_buildApp(router, container: container));
    container.read(lastPracticeScoreProvider.notifier).state = 0.5;
    await _openFillQuizAndTapFail(tester, '静夜思');
    await _pumpUi(tester);

    final schedule = reviewRepo.get('poem_1')!;
    expect(schedule.currentRound, 0);
    expect(schedule.lastScore, 0.5);
    // 未达及格线：明天重测（0 或 1 天内到期）。
    expect(
      schedule.nextReviewDate.difference(DateTime.now()).inDays,
      inInclusiveRange(0, 1),
    );
    // 消费端纪律：读取即清空。
    expect(container.read(lastPracticeScoreProvider), isNull);
  });

  testWidgets('批量复习遇到失败后停止且不推进后续诗词', (tester) async {
    _setViewport(tester);
    final reviewRepo = _FakeReviewRepository();
    await tester.runAsync(() async {
      await _seedReview(reviewRepo, 'poem_1', '静夜思');
      await _seedReview(reviewRepo, 'poem_2', '春晓');
    });
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router, reviewRepo: reviewRepo));
    await _pumpUi(tester);
    await tester.tap(find.text('一键复习今日全部（2 首）'));
    await _pumpUi(tester);
    await tester.tap(find.text('测试失败'));
    await _pumpUi(tester);

    expect(find.text('测试失败'), findsNothing);
    // SnackBar 队列：先「未达 80%」（2 秒 + 退出动画），随后才轮到批量汇总
    // 提示。逐帧推进（一次大步 pump 不触发动画链），3 秒后汇总提示可见。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已完成 0/2 首，剩余复习未记录'), findsOneWidget);
    expect(reviewRepo.get('poem_1')!.currentRound, 0);
    expect(reviewRepo.get('poem_2')!.currentRound, 0);
  });
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _seedReview(
  _FakeReviewRepository repo,
  String poemId,
  String title,
) async {
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
  await repo.save(
    ReviewSchedule(
      poemId: poemId,
      profileId: 'default',
      nextReviewDate: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  );
}

Widget _buildApp(
  GoRouter router, {
  ProviderContainer? container,
  _FakeReviewRepository? reviewRepo,
}) {
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }
  return ProviderScope(
    overrides: [
      if (reviewRepo != null)
        reviewRepoProvider.overrideWith((_) => reviewRepo),
    ],
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

/// 打开填空测试后点「测试失败」（调用前由测试预置侧信道得分）。
Future<void> _openFillQuizAndTapFail(
  WidgetTester tester,
  String poemTitle,
) async {
  await _pumpUi(tester);
  expect(find.text(poemTitle), findsOneWidget);
  await tester.tap(find.text('复习'));
  await _pumpUi(tester);
  await tester.tap(find.text('填空测试'));
  await _pumpUi(tester);
  await tester.tap(find.text('测试失败'));
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
