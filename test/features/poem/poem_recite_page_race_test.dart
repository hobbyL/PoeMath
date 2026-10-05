// test/features/poem/poem_recite_page_race_test.dart
//
// 背诵页竞态守卫回归测试（batch2 R1-R5）：
// - R1 默写提交连点只结算一次；
// - R2 结算途中退出页面，repo 层数据完整落库且无 ref dispose 断言；
// - R3 完成页双击返回，pop 结果为 recitationCompleted 且不重复 pop；
// - R4 冷却期内误点候选字不降星；
// - R5 完成结算后 filteredPoemsProvider 被失效（列表状态及时刷新）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/achievement_repository.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/poem_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_practice_result.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

import '../../helpers/hive_test_helper.dart';

const _poemId = 'recite-race-poem';

/// 单字单行诗：easy 模式唯一空即该字，正确字确定（'床'）。
final _poem = Poem(
  id: _poemId,
  title: '竞态测试诗',
  author: '测试作者',
  dynasty: '唐',
  content: '床',
  pinyin: '',
  layer: 'core',
  grade: 1,
);

/// 三字同字诗：medium 模式 2 个空且正确字恒为 '一'，
/// 填对第一个空后候选区仍在，适合冷却期误点断言（R4）。
const _multiPoemId = 'recite-race-multi';
final _multiPoem = Poem(
  id: _multiPoemId,
  title: '多空测试诗',
  author: '测试作者',
  dynasty: '唐',
  content: '一一一',
  pinyin: '',
  layer: 'core',
  grade: 1,
);

/// 阻塞型进度仓储：recordRecitation 挂起，模拟结算首个 await 期间退出页面。
class _BlockingReciteProgressRepository extends PoemProgressRepository {
  final _release = Completer<PoemProgress>();
  var recordCalls = 0;

  @override
  Future<PoemProgress> recordRecitation(
    String poemId, {
    required int level,
  }) {
    recordCalls++;
    return _release.future;
  }

  void release() => _release.complete(
        PoemProgress(poemId: _poemId, profileId: 'test'),
      );

  @override
  int get learnedCount => 1;
}

class _CountingStatsRepository extends UserStatsRepository {
  var poemStatCalls = 0;
  var starsAdded = 0;

  @override
  UserStats get() => UserStats(profileId: 'test');

  @override
  Future<void> updatePoemStats({int? learned, int? mastered}) async {
    poemStatCalls++;
  }

  @override
  Future<void> addStars(int count, {String? activityId}) async {
    starsAdded += count;
  }
}

class _CountingCheckInRepository extends CheckInRepository {
  var updateCalls = 0;
  int poemsAdded = 0;
  int starsAdded = 0;

  @override
  Future<void> updateToday({
    String? activityId,
    int? addPoems,
    int? addMathTotal,
    int? addMathCorrect,
    int? addStars,
    int? addDuration,
  }) async {
    updateCalls++;
    poemsAdded += addPoems ?? 0;
    starsAdded += addStars ?? 0;
  }
}

class _CountingActivityRepository extends LearningActivityRepository {
  var recordCalls = 0;
  final List<LearningActivity> recorded = [];

  @override
  Future<bool> record({
    required String id,
    required LearningActivityType activityType,
    required int totalItems,
    required int successfulItems,
    required int starsEarned,
    required int durationSeconds,
    required DateTime completedAt,
    String? poemId,
  }) async {
    recordCalls++;
    recorded.add(
      LearningActivity(
        id: id,
        profileId: 'test',
        activityType: activityType.name,
        totalItems: totalItems,
        successfulItems: successfulItems,
        poemId: poemId,
        starsEarned: starsEarned,
        durationSeconds: durationSeconds,
        completedAt: completedAt,
      ),
    );
    return true;
  }
}

class _UnlockedAchievementRepository extends AchievementRepository {
  @override
  Achievement? getById(String id) {
    return Achievement(
      id: id,
      profileId: 'test',
      title: id,
      isUnlocked: true,
    );
  }

  @override
  int get unlockedCount => 0;
}

/// 挂起型成就仓储：getById 返回 null 强制 check() 走 await save() 路径，
/// save 在 release 前挂起——模拟「成就检查 await 期间退出页面」
/// （R2 成就检查分支回归：await 后不得再触 ref）。
class _HangingAchievementRepository extends AchievementRepository {
  final _release = Completer<void>();
  var saveCalls = 0;
  bool _released = false;

  @override
  Achievement? getById(String id) => null;

  @override
  Future<void> save(Achievement achievement) {
    saveCalls++;
    if (_released) return Future<void>.value();
    return _release.future;
  }

  // no-op：避免默认实现写 Hive box 在 FakeAsync 中挂起。
  @override
  Future<void> updateProgress(String id, double progress) async {}

  @override
  int get unlockedCount => 0;

  void release() {
    _released = true;
    _release.complete();
  }
}

/// 纯内存诗词仓储：filteredPoemsProvider 监听测试用。
class _StubPoemRepository extends PoemRepository {
  _StubPoemRepository(this.poems);

  final List<Poem> poems;

  @override
  Future<void> buildIndices() async {}

  @override
  List<Poem> getAll() => List.of(poems); // 每次新实例，模拟真实筛选重算

  @override
  Poem? getById(String id) {
    for (final poem in poems) {
      if (poem.id == id) return poem;
    }
    return null;
  }
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  ProviderContainer createContainer({
    required _CountingStatsRepository statsRepo,
    required _CountingCheckInRepository checkInRepo,
    required _CountingActivityRepository activityRepo,
    required _BlockingReciteProgressRepository progressRepo,
    String poemId = _poemId,
    Poem? poem,
  }) {
    final resolvedPoem = poem ?? _poem;
    return ProviderContainer(
      overrides: [
        poemByIdProvider(poemId).overrideWith((ref) => resolvedPoem),
        poemRepoProvider
            .overrideWith((ref) => _StubPoemRepository([resolvedPoem])),
        poemProgressRepoProvider.overrideWith((ref) => progressRepo),
        userStatsRepoProvider.overrideWith((ref) => statsRepo),
        checkInRepoProvider.overrideWith((ref) => checkInRepo),
        learningActivityRepositoryProvider.overrideWith((ref) => activityRepo),
        achievementRepoProvider.overrideWith(
          (ref) => _UnlockedAchievementRepository(),
        ),
      ],
    );
  }

  Future<void> pumpHost(
    WidgetTester tester,
    ProviderContainer container, {
    Widget? home,
    String poemId = _poemId,
  }) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // 故意非 const：需要时可再次 pump 触发 didUpdateWidget 重建
          // （保留 State），用于提交按钮按最新输入重新求值启用态。
          home: home ?? PoemRecitePage(poemId: poemId),
        ),
      ),
    );
  }

  /// 页面就绪并切到默写模式、输入全文；结束于提交按钮已启用。
  /// [home] 非空时先点击其中的「打开背诵」推入页面（R3 记录 pop 结果用）。
  Future<void> prepareDictation(
    WidgetTester tester,
    ProviderContainer container, {
    Widget? home,
  }) async {
    await pumpHost(tester, container, home: home);
    await tester.pump();
    if (home != null) {
      await tester.tap(find.text('打开背诵'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('默写'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), '床');
    // 重挂载同构树触发页面重建（State 保留），使提交按钮按非空文本启用。
    await pumpHost(tester, container, home: home);
    await tester.pump();
  }

  testWidgets('R1 默写提交连点：进度/活动/打卡只结算一次，列表 Provider 失效', (tester) async {
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();
    final progressRepo = _BlockingReciteProgressRepository();
    final container = createContainer(
      statsRepo: statsRepo,
      checkInRepo: checkInRepo,
      activityRepo: activityRepo,
      progressRepo: progressRepo,
    );
    addTearDown(container.dispose);

    // R5：监听 filteredPoemsProvider，结算后应被失效并重算。
    var filteredRebuilds = 0;
    container.listen(
      filteredPoemsProvider,
      (_, __) => filteredRebuilds++,
    );

    await prepareDictation(tester, container);

    // 两次点击之间不重建，模拟快速连点提交。
    final submit = find.text('提交默写');
    await tester.tap(submit);
    await tester.tap(submit);

    progressRepo.release();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(progressRepo.recordCalls, 1);
    expect(activityRepo.recordCalls, 1);
    expect(checkInRepo.updateCalls, 1);
    expect(checkInRepo.poemsAdded, 1);
    // 全对默写：3 颗星。
    expect(statsRepo.starsAdded, 3);
    expect(checkInRepo.starsAdded, 3);
    expect(activityRepo.recorded.single.activityType, 'poemRecitation');
    expect(activityRepo.recorded.single.starsEarned, 3);
    expect(tester.takeException(), isNull);
    expect(find.text('太棒了！完美背诵！'), findsOneWidget);
    expect(filteredRebuilds, 1, reason: 'R5 完成结算后 filteredPoemsProvider 应失效');
  });

  testWidgets('R2 结算途中退出页面：repo 层四通道仍完整落库，无 ref dispose 断言', (tester) async {
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();
    final progressRepo = _BlockingReciteProgressRepository();
    final container = createContainer(
      statsRepo: statsRepo,
      checkInRepo: checkInRepo,
      activityRepo: activityRepo,
      progressRepo: progressRepo,
    );
    addTearDown(container.dispose);

    await prepareDictation(tester, container);

    // 提交后立即整树替换，模拟结算首个 await 挂起期间退出页面。
    await tester.tap(find.text('提交默写'));
    await tester.pumpWidget(const SizedBox.shrink());

    progressRepo.release();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 数据结算完整：progress/stats/activity/stars/checkIn 全部落库。
    expect(progressRepo.recordCalls, 1);
    expect(statsRepo.poemStatCalls, 1);
    expect(activityRepo.recordCalls, 1);
    expect(statsRepo.starsAdded, 3);
    expect(checkInRepo.updateCalls, 1);
    // 未挂载时不得再触 ref（否则抛 "Cannot use ref after dispose"）。
    expect(tester.takeException(), isNull);
  });

  testWidgets('R2 成就检查挂起期间退出页面：不再触 ref，数据已完整落库', (tester) async {
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();
    final progressRepo = _BlockingReciteProgressRepository();
    final achievementRepo = _HangingAchievementRepository();
    final container = ProviderContainer(
      overrides: [
        poemByIdProvider(_poemId).overrideWith((ref) => _poem),
        poemRepoProvider
            .overrideWith((ref) => _StubPoemRepository([_poem])),
        poemProgressRepoProvider.overrideWith((ref) => progressRepo),
        userStatsRepoProvider.overrideWith((ref) => statsRepo),
        checkInRepoProvider.overrideWith((ref) => checkInRepo),
        learningActivityRepositoryProvider.overrideWith((ref) => activityRepo),
        achievementRepoProvider.overrideWith((ref) => achievementRepo),
      ],
    );
    addTearDown(container.dispose);

    await prepareDictation(tester, container);

    await tester.tap(find.text('提交默写'));
    progressRepo.release(); // 结算链推进到成就检查并在 save 上挂起
    await tester.pump();
    await tester.pump();
    expect(achievementRepo.saveCalls, greaterThanOrEqualTo(1));

    // 成就检查 await 挂起期间整树替换，模拟退出页面。
    await tester.pumpWidget(const SizedBox.shrink());

    achievementRepo.release();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 结算数据完整；成就检查返回后 mounted 为 false，不得再触 ref
    // （否则抛 "Cannot use ref after the widget was disposed"）。
    expect(activityRepo.recordCalls, 1);
    expect(checkInRepo.updateCalls, 1);
    expect(statsRepo.starsAdded, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R3 完成页双击返回：仅 pop 一次且结果为 recitationCompleted', (tester) async {
    final popResults = <PoemPracticeResult?>[];
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();
    final progressRepo = _BlockingReciteProgressRepository();
    final container = createContainer(
      statsRepo: statsRepo,
      checkInRepo: checkInRepo,
      activityRepo: activityRepo,
      progressRepo: progressRepo,
    );
    addTearDown(container.dispose);

    final recorderHome = Builder(
      builder: (context) => TextButton(
        onPressed: () {
          unawaited(
            Navigator.of(context)
                .push<PoemPracticeResult>(
                  MaterialPageRoute(
                    // 非 const：配合重挂载触发 didUpdateWidget 重建。
                    // ignore: prefer_const_constructors
                    builder: (_) => PoemRecitePage(poemId: _poemId),
                  ),
                )
                .then((result) => popResults.add(result)),
          );
        },
        child: const Text('打开背诵'),
      ),
    );

    await prepareDictation(tester, container, home: recorderHome);

    await tester.tap(find.text('提交默写'));
    progressRepo.release();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    final backButton = find.text('返回');
    expect(backButton, findsOneWidget);
    // 双击返回：第一次同步 pop 即刻拆除路由（第二次 tap 甚至不再命中
    // 活动按钮，即 warnIfMissed 的来源），防重入守卫兜底第二击。
    await tester.tap(backButton);
    await tester.tap(backButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(popResults, hasLength(1));
    expect(popResults.single, PoemPracticeResult.recitationCompleted);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R4 冷却期内误点候选字：不计错误，满星结算', (tester) async {
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();
    final progressRepo = _BlockingReciteProgressRepository();
    final container = createContainer(
      statsRepo: statsRepo,
      checkInRepo: checkInRepo,
      activityRepo: activityRepo,
      progressRepo: progressRepo,
      poemId: _multiPoemId,
      poem: _multiPoem,
    );
    addTearDown(container.dispose);

    await pumpHost(tester, container, poemId: _multiPoemId);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // medium 模式：'一一一' 共 2 个空，正确字恒为 '一'。
    await tester.tap(find.text('中等'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 候选区在行文本之后渲染，取最后一个 '一' 即候选键。
    await tester.tap(find.text('一').last);
    await tester.pump();

    // 冷却期内（350ms 延迟推进前）点击兜底干扰字：应被已填守卫忽略。
    const fallbackPool = {
      '山',
      '水',
      '风',
      '月',
      '花',
      '云',
      '雨',
      '春',
      '秋',
      '雪',
      '天',
      '地',
      '日',
      '夜',
      '人',
      '心',
      '梦',
      '鸟',
      '树',
      '石',
    };
    final wrongCandidate = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data?.length ?? 0) == 1 &&
          fallbackPool.contains(widget.data),
    );
    expect(wrongCandidate, findsWidgets);
    await tester.tap(wrongCandidate.first);

    await tester.pump(const Duration(milliseconds: 400)); // 350ms 推进到下一空
    await tester.tap(find.text('一').last); // 第二个空
    await tester.pump(const Duration(milliseconds: 400)); // 本句填完
    await tester.pump(const Duration(milliseconds: 900)); // 800ms 换句触发结算
    progressRepo.release();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // 0 错误 0 提示：3 颗星；若冷却误点被计入则降为 2 星（标题不同）。
    expect(find.text('太棒了！完美背诵！'), findsOneWidget);
    expect(statsRepo.starsAdded, 3);
    expect(tester.takeException(), isNull);
  });
}
