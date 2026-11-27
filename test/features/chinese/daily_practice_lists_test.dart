import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_tab_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

const _poemId = 'poem_core_004';
final _today = DateTime(2026, 11, 27, 12);

Future<void> _seedCatalogs({bool withSecond = false}) async {
  for (final id in [_poemId, if (withSecond) 'second-poem']) {
    await HiveBoxes.poems.put(
      id,
      Poem(
        id: id,
        title: id == _poemId ? '静夜思' : '春晓',
        author: '李白',
        dynasty: '唐',
        content: '床前明月光，疑是地上霜。',
        pinyin: '',
        layer: 'core',
        grade: 1,
        semester: '上',
        isRequired: true,
      ),
    );
  }
  final prompts = [
    pictureStoryFixture(id: 'picture'),
    pictureStoryFixture(id: 'picture').copyWith(version: 2),
    if (withSecond) pictureStoryFixture(id: 'second-picture', title: '另一张图片'),
  ];
  final repository = PictureStoryRepository();
  await PictureStoryRepository.exclusive(
    () =>
        repository.replaceCatalogForRestore(PictureStoryCatalogState(prompts), {
          for (final profile in ['default', 'other'])
            profile: prompts.map((p) => p.id).toSet().toList(),
        }),
  );
}

Future<void> _complete(DateTime date, {String suffix = ''}) async {
  final activityId = 'poem:$suffix:${date.toIso8601String()}';
  // 使用旧别名与旧题目版本，验证稳定内容身份。
  await PoemProgressRepository().recordStudy(
    'poem_exp_661',
    activityId: activityId,
    completedAt: date,
  );
  await LearningActivityRepository().record(
    id: activityId,
    activityType: LearningActivityType.poemRecitation,
    totalItems: 1,
    successfulItems: 1,
    poemId: 'poem_exp_661',
    starsEarned: 0,
    durationSeconds: 30,
    completedAt: date,
  );
  await PictureStoryRepository().save(
    PictureStoryPracticeRecord(
      id: 'picture:$suffix:${date.toIso8601String()}',
      profileId: ProfileScope.currentId,
      promptId: 'picture',
      promptVersion: 1,
      startedAt: date,
      completedAt: date,
      status: 'completed',
      segmentsJson: '[]',
      answerText: '小猫在看书。',
    ),
  );
}

void main() {
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  test('可练列表和推荐按内容隐藏，完整筛选、家长启用及历史仍保留', () async {
    await _seedCatalogs(withSecond: true);
    await _complete(DateTime(2026, 11, 26));
    final container = ProviderContainer(
      overrides: [staticDayKeyOverride('2026-11-27')],
    );
    addTearDown(container.dispose);

    expect(container.read(availablePoemsProvider).map((p) => p.id), [
      'second-poem',
    ]);
    expect(
      container.read(availablePictureStoryPromptsProvider).map((p) => p.id),
      ['second-picture'],
    );
    expect(container.read(dailyRecommendedPoemProvider)?.id, 'second-poem');
    expect(container.read(filteredPoemsProvider).map((p) => p.id), [
      _poemId,
      'second-poem',
    ]);
    expect(container.read(pictureStoryPromptCountProvider), 2);
    expect(container.read(pictureStoryCatalogProvider), hasLength(2));
    expect(
      container.read(pictureStoryPromptHistoryProvider('picture')),
      hasLength(1),
    );
    expect(container.read(poemByIdProvider(_poemId))?.title, '静夜思');
    expect(
      container.read(pictureStoryPromptByIdProvider('picture'))?.version,
      2,
    );

    container.read(poemSearchQueryProvider.notifier).state = '静夜思';
    expect(container.read(filteredPoemsProvider), hasLength(1));
    expect(container.read(availablePoemsProvider), isEmpty);
  });

  test('当天完成仍显示且不重复计数，次日起隐藏，到期、档案和备份刷新正确', () async {
    await _seedCatalogs();
    final container = ProviderContainer(
      overrides: [staticDayKeyOverride('2026-11-27')],
    );
    addTearDown(container.dispose);
    final poems = <int>[];
    final pictures = <int>[];
    final poemSub = container.listen(
      availablePoemsProvider,
      (_, value) => poems.add(value.length),
      fireImmediately: true,
    );
    final pictureSub = container.listen(
      availablePictureStoryPromptsProvider,
      (_, value) => pictures.add(value.length),
      fireImmediately: true,
    );
    addTearDown(poemSub.close);
    addTearDown(pictureSub.close);
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 1);
    expect(pictures.last, 1);
    await _complete(_today);
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 1);
    expect(pictures.last, 1);
    await _complete(_today, suffix: 'repeat');
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 1);
    expect(pictures.last, 1);
    expect(container.read(todayPoemCountProvider), 1);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      1,
    );
    expect(container.read(dailyRecommendedPoemProvider)?.id, _poemId);

    container.read(dayKeyProvider.notifier).state = '2026-11-28';
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 0);
    expect(pictures.last, 0);
    expect(container.read(todayPoemCountProvider), 0);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      0,
    );
    expect(container.read(dailyRecommendedPoemProvider), isNull);

    ProfileScope.switchTo('other');
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 1);
    expect(pictures.last, 1);
    ProfileScope.reset();
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 0);
    expect(pictures.last, 0);

    for (final (day, count) in [('2026-12-01', 0), ('2026-12-02', 1)]) {
      container.read(dayKeyProvider.notifier).state = day;
      await Future<void>.delayed(Duration.zero);
      expect(poems.last, count, reason: day);
      expect(pictures.last, count, reason: day);
    }
    expect(container.read(dailyRecommendedPoemProvider)?.id, _poemId);
    await _complete(DateTime(2026, 12, 2));
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 1);
    expect(pictures.last, 1);
    expect(container.read(todayPoemCountProvider), 1);
    expect(
      container
          .read(todayLearningActivityCountsProvider)
          .pictureStoryExpression,
      1,
    );
    container.read(dayKeyProvider.notifier).state = '2026-12-03';
    await Future<void>.delayed(Duration.zero);
    expect(poems.last, 0);
    expect(pictures.last, 0);
    await HiveBoxes.learningActivities.clear();
    await HiveBoxes.poemProgress.clear();
    await HiveBoxes.pictureStoryPractice.clear();
    invalidateAllHiveProviders(container.invalidate);
    expect(container.read(availablePoemsProvider), hasLength(1));
    expect(container.read(availablePictureStoryPromptsProvider), hasLength(1));
  });

  testWidgets('当天已练的诗词与看图题目仍展示，次日页面自动隐藏', (tester) async {
    await tester.runAsync(() async {
      await _seedCatalogs();
      await _complete(_today);
    });
    final container = ProviderContainer(
      overrides: [staticDayKeyOverride('2026-11-27')],
    );
    addTearDown(container.dispose);
    for (final isPoem in [true, false]) {
      container.read(dayKeyProvider.notifier).state = '2026-11-27';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: isPoem ? const PoemTabPage() : const PictureStoryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = isPoem ? '静夜思' : '窗前的小猫';
      final hiddenTitle = isPoem ? '这些诗词最近已经练过了' : '这些题目最近已经练过了';
      expect(find.text(title), findsOneWidget);
      expect(find.text(hiddenTitle), findsNothing);
      container.read(dayKeyProvider.notifier).state = '2026-11-28';
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
      expect(find.text(hiddenTitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('看图全隐藏显示恢复提示并可打开历史，家长启用开关保持打开', (tester) async {
    await tester.runAsync(() async {
      await _seedCatalogs();
      await _complete(DateTime(2026, 11, 26, 12));
    });
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PictureStoryPage()),
        GoRoute(
          path: AppRoutes.pictureStoryHistory,
          builder: (_, __) => const Scaffold(body: Text('已保存的历史')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [staticDayKeyOverride('2026-11-27')],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这些题目最近已经练过了'), findsOneWidget);
    expect(find.text('窗前的小猫'), findsNothing);
    expect(find.text('请家长在设置中添加或启用看图说话题目。'), findsNothing);
    await tester.tap(find.text('查看练习记录'));
    await tester.pumpAndSettle();
    expect(find.text('已保存的历史'), findsOneWidget);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        child: const MaterialApp(home: PictureStoryManagementPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('窗前的小猫'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$subject/$brightness 两类全隐藏空态支持窄屏大字和横屏', (tester) async {
        await tester.runAsync(() async {
          await _seedCatalogs();
          await _complete(DateTime(2026, 11, 26, 12));
        });
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final size in [const Size(320, 800), const Size(800, 320)]) {
          tester.view.physicalSize = size;
          for (final isPoem in [true, false]) {
            await tester.pumpWidget(
              ProviderScope(
                key: UniqueKey(),
                overrides: [staticDayKeyOverride('2026-11-27')],
                child: MaterialApp(
                  theme: AppTheme.resolve(
                    subject: subject,
                    brightness: brightness,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: isPoem ? const PoemTabPage() : const PictureStoryPage(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text(isPoem ? '这些诗词最近已经练过了' : '这些题目最近已经练过了'),
              findsOneWidget,
            );
            expect(find.text(isPoem ? '静夜思' : '窗前的小猫'), findsNothing);
            expect(find.textContaining('5 天间隔结束后自动显示'), findsOneWidget);
            final action = find.text(isPoem ? '调整筛选' : '查看练习记录');
            await tester.ensureVisible(action);
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
