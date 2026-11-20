import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/app.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/features/home/practice_resume_section.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/math_adventure_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/adventure/math_adventure_practice_page.dart';
import 'package:poemath/features/math/adventure/math_adventure_providers.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/session_result_dialog.dart';
import 'package:poemath/features/math/widgets/number_keypad.dart';
import 'package:poemath/features/math/adventure/math_adventure_page.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/day_key_override.dart';

class _SilentSound extends SoundService {
  _SilentSound() : super(SettingsRepository());
  @override
  Future<void> playCompletion() async {}
}

class _FailProgressOnce extends MathAdventureRepository {
  bool fail = true;
  @override
  Future<MathAdventureCompletion> complete({
    required MathAdventureNode node,
    required DifficultyLevel difficulty,
    required void Function() ensureCurrent,
  }) async {
    if (fail) {
      fail = false;
      throw StateError('模拟探险进度写失败');
    }
    return super.complete(
      node: node,
      difficulty: difficulty,
      ensureCurrent: ensureCurrent,
    );
  }
}

class _FailRemoveOnce extends PracticeDraftRepository {
  bool fail = true;
  @override
  Future<void> remove(String kind, {String? sessionId, String? scope}) async {
    if (kind == MathAdventureNode.draftKind && fail) {
      fail = false;
      throw StateError('模拟草稿删除失败');
    }
    return super.remove(kind, sessionId: sessionId, scope: scope);
  }
}

const _node = MathAdventureNode(grade: 1, semester: '上', skillId: 'addition');
final _problem = MathProblem(
  operands: [NumberValue.fromInt(2), NumberValue.fromInt(3)],
  operators: const [Operator.add],
  result: NumberValue.fromInt(5),
  mode: ProblemMode.findResult,
  grade: 1,
  semester: '上',
  skillId: 'addition',
);

Map<String, dynamic> _draft({bool finished = true, bool correct = false}) => {
  'sessionId': 'adventure-checkpoint',
  'startedAt': DateTime(2026, 11, 20, 10).toIso8601String(),
  if (finished) 'completedAt': DateTime(2026, 11, 20, 10, 1).toIso8601String(),
  'elapsedMilliseconds': 60000,
  'index': 0,
  'input': '4',
  'request': const MathPracticeRequest(
    grade: 1,
    semester: '上',
    count: 1,
    difficulty: DifficultyLevel.medium,
    skillId: 'addition',
    adventureProfileId: 'default',
  ).toJson(),
  'problems': [_problem.toJson()],
  'records': [
    if (finished)
      ProblemRecord(
        problemText: _problem.problemText,
        answerText: '5',
        userAnswer: correct ? '5' : '4',
        isCorrect: correct,
        problem: _problem.toJson(),
      ).toJson(),
  ],
};

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  Future<void> saveDraft(Map<String, dynamic> draft) async {
    final drafts = PracticeDraftRepository();
    drafts.claim(MathAdventureNode.draftKind, scope: _node.scope);
    await drafts.save(MathAdventureNode.draftKind, draft, scope: _node.scope);
    await drafts.save('math', {
      'sessionId': 'ordinary',
      'problems': <dynamic>[],
      'records': <dynamic>[],
    });
  }

  Future<void> mount(
    WidgetTester tester, {
    MathAdventureRepository? repository,
    PracticeDraftRepository? drafts,
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            soundServiceProvider.overrideWithValue(_SilentSound()),
            if (repository != null)
              mathAdventureRepositoryProvider.overrideWithValue(repository),
            if (drafts != null)
              mathAdventureDraftRepositoryProvider.overrideWithValue(
                () => drafts,
              ),
          ],
          child: const MaterialApp(
            home: MathAdventurePracticePage(node: _node, resume: true),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final failure in ['none', 'progress', 'draft']) {
    testWidgets('探险整组 $failure：全错可推进、失败重开幂等且普通草稿保留', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await drainHiveWritesForTesting(tester);
      });
      await tester.runAsync(
        () => saveDraft(_draft(correct: failure != 'none')),
      );
      await mount(
        tester,
        repository: failure == 'progress' ? _FailProgressOnce() : null,
        drafts: failure == 'draft' ? _FailRemoveOnce() : null,
      );
      final stars = HiveBoxes.userStats.values.first.totalStars;
      if (failure != 'none') {
        expect(find.byType(SessionResultDialog), findsNothing);
        expect(
          PracticeDraftRepository().get(
            MathAdventureNode.draftKind,
            scope: _node.scope,
          ),
          isNotNull,
        );
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await mount(tester);
        expect(HiveBoxes.userStats.values.first.totalStars, stars);
      }
      expect(MathAdventureRepository().read(1, '上').completedSkillIds, {
        'addition',
      });
      expect(find.byType(SessionResultDialog), findsOneWidget);
      expect(find.text('回到探险地图'), findsOneWidget);
      expect(PracticeDraftRepository().get('math')!['sessionId'], 'ordinary');
      expect(
        PracticeDraftRepository().get(
          MathAdventureNode.draftKind,
          scope: _node.scope,
        ),
        isNull,
      );
      expect(HiveBoxes.mathSessions.length, 1);
    });
  }

  testWidgets('未完成续练不推进且局部题目不覆盖外部普通题组', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
    await tester.runAsync(() => saveDraft(_draft(finished: false)));
    await mount(tester);
    expect(MathAdventureRepository().read(1, '上').completedSkillIds, isEmpty);
    expect(find.byType(SessionResultDialog), findsNothing);
    final outer = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(outer.read(mathProblemsProvider), isEmpty);
    expect(PracticeDraftRepository().get('math')!['sessionId'], 'ordinary');
  });

  test('草稿工厂实例独立，旧页面不能覆盖或删除同节点的新草稿', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final factory = container.read(mathAdventureDraftRepositoryProvider);
    final first = factory();
    final second = factory();
    expect(identical(first, second), isFalse);
    first.claim(MathAdventureNode.draftKind, scope: _node.scope);
    await first.save(MathAdventureNode.draftKind, _draft(), scope: _node.scope);
    second.claim(MathAdventureNode.draftKind, scope: _node.scope);
    await second.save(MathAdventureNode.draftKind, {
      ..._draft(),
      'sessionId': 'new-page',
    }, scope: _node.scope);
    await expectLater(
      first.save(MathAdventureNode.draftKind, _draft(), scope: _node.scope),
      throwsStateError,
    );
    await expectLater(
      first.remove(MathAdventureNode.draftKind, scope: _node.scope),
      throwsStateError,
    );
    expect(
      second.get(MathAdventureNode.draftKind, scope: _node.scope)!['sessionId'],
      'new-page',
    );
  });

  testWidgets('新开使用持久设置，不消耗普通入口的临时题量与专项', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
    await tester.runAsync(() async {
      await SettingsRepository().setMathBatchSize(3);
      await SettingsRepository().setMathDifficulty('easy');
      await SettingsRepository().setMathPracticeMode('vertical');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const ordinary = MathPracticeRequest(
      grade: 1,
      semester: '上',
      count: 7,
      difficulty: DifficultyLevel.hard,
      mode: ProblemMode.vertical,
    );
    container.read(nextMathPracticeRequestProvider.notifier).setNext(ordinary);
    container.read(mathBatchSizeOverrideProvider.notifier).setNext(7);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MathAdventurePracticePage(node: _node)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await drainHiveWritesForTesting(tester);
    final draft = PracticeDraftRepository().get(
      MathAdventureNode.draftKind,
      scope: _node.scope,
    )!;
    final request = MathPracticeRequest.fromJson(
      draft['request'] as Map<String, dynamic>,
    );
    expect(request.count, 3);
    expect(request.difficulty, DifficultyLevel.easy);
    expect(request.mode, isNull);
    expect((draft['problems'] as List).length, 3);
    expect(
      container.read(nextMathPracticeRequestProvider.notifier).peek(),
      same(ordinary),
    );
    expect(container.read(mathBatchSizeOverrideProvider), 7);
  });

  testWidgets('续练保留原组难度题量；切档再切回令旧页失效', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
      ProfileScope.reset();
    });
    await tester.runAsync(() async {
      await saveDraft(_draft(finished: false));
      await SettingsRepository().setLearningBackground(6, '下');
      await SettingsRepository().setMathDifficulty('easy');
      await SettingsRepository().setMathBatchSize(100);
    });
    await mount(tester);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.textContaining('无法恢复'), findsNothing);
    ProfileScope.switchTo('child2');
    ProfileScope.reset();
    await tester.pump();
    expect(find.text('学习档案已切换，请返回地图重新进入'), findsOneWidget);
    expect(find.text('回到探险地图'), findsOneWidget);
    expect(MathAdventureRepository().read(1, '上').completedSkillIds, isEmpty);
  });

  test('首页同时枚举普通和两个探险草稿，损坏草稿可识别并单独放弃', () async {
    await saveDraft(_draft(finished: false));
    const second = MathAdventureNode(
      grade: 1,
      semester: '上',
      skillId: 'subtraction',
    );
    final drafts = PracticeDraftRepository();
    drafts.claim(MathAdventureNode.draftKind, scope: second.scope);
    await drafts.save(MathAdventureNode.draftKind, {
      'bad': true,
    }, scope: second.scope);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final list = await container.read(practiceDraftsProvider.future);
    expect(list.length, 3);
    final adventure = list.singleWhere((d) => d['scope'] == _node.scope);
    expect(adventure['label'], contains('1 年级上册'));
    expect(adventure['route'], contains('resume=1'));
    expect(
      list.singleWhere((d) => d['scope'] == second.scope)['invalid'],
      isTrue,
    );
    await PracticeDraftRepository().remove(
      MathAdventureNode.draftKind,
      scope: second.scope,
    );
    expect(
      drafts.get(MathAdventureNode.draftKind, scope: _node.scope),
      isNotNull,
    );
    expect(drafts.get('math'), isNotNull);
  });

  testWidgets('真实路由两站全错走通、返回保留地图位置、纪念册可达且可重玩', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await SettingsRepository().setMathBatchSize(1);
      await SettingsRepository().setSoundEnabled(false);
      await SettingsRepository().setHapticEnabled(false);
      await SettingsRepository().setPageAnimationsEnabled(false);
    });
    final container = ProviderContainer(overrides: [staticDayKeyOverride()]);
    addTearDown(container.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.mathAdventure);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pump();
    });
    await tester.pump(const Duration(seconds: 1));

    for (final label in ['整数加法', '整数减法']) {
      await tester.ensureVisible(find.text(label));
      await tester.pump();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final position = scroll.pixels;
      await tester.runAsync(() => tester.tap(find.text(label)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      for (
        var attempt = 0;
        attempt < 30 && find.text('1 / 1').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        find.text('1 / 1'),
        findsOneWidget,
        reason:
            '$label: ${router.routeInformationProvider.value.uri}, ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data)}',
      );
      for (var digit = 0; digit < 3; digit++) {
        await tester.tap(
          find.descendant(
            of: find.byType(NumberKeypad),
            matching: find.text('9'),
          ),
        );
        await tester.pump();
      }
      await tester.runAsync(
        () => tester.tap(
          find.descendant(
            of: find.byType(NumberKeypad),
            matching: find.byIcon(Icons.check_rounded),
          ),
        ),
      );
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('math-next-problem-button')),
        );
        if (button.onPressed != null) break;
      }
      await tester.runAsync(() => tester.tap(find.text('查看成绩')));
      for (
        var attempt = 0;
        attempt < 80 && find.byType(SessionResultDialog).evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SessionResultDialog), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('回到探险地图')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(find.byType(MathAdventurePage), findsOneWidget);
      expect(scroll.pixels, closeTo(position, 1));
    }
    expect(MathAdventureRepository().read(1, '上').collectedRegionIds, {
      'arithmetic_forest',
    });
    expect(find.text('本册探索完成！'), findsOneWidget);
    await tester.tap(find.byTooltip('打开纪念册'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('晨光叶 · 已收集'), findsOneWidget);
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('整数加法'));
    await tester.runAsync(() => tester.tap(find.text('整数加法')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 / 1'), findsOneWidget);
    expect(HiveBoxes.mathSessions.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => tester.tap(find.byType(BackButton)));
    for (
      var attempt = 0;
      attempt < 30 &&
          find.byType(MathAdventurePracticePage).evaluate().isNotEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MathAdventurePage), findsOneWidget);
    expect(
      PracticeDraftRepository().get(
        MathAdventureNode.draftKind,
        scope: _node.scope,
      ),
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await drainHiveWritesForTesting(tester);
  });
}
