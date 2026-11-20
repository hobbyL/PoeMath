import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_adventure_progress.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/data/repositories/math_adventure_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/adventure/math_adventure_album_page.dart';
import 'package:poemath/features/math/adventure/adventure_region_scene.dart';
import 'package:poemath/features/math/adventure/math_adventure_page.dart';
import 'package:poemath/features/math/adventure/math_adventure_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

class _ReadFailure extends MathAdventureRepository {
  bool fail = true;
  @override
  List<MathAdventureProgress> getAll() {
    if (fail) throw StateError('模拟进度读取失败');
    return super.getAll();
  }
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForWidgetTesting();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    ProviderContainer? container,
    AppSubject subject = AppSubject.math,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.runAsync(() async {
      final app = MaterialApp(
        theme: AppTheme.resolve(subject: subject, brightness: brightness),
        home: page,
      );
      await tester.pumpWidget(
        container == null
            ? ProviderScope(child: app)
            : UncontrolledProviderScope(container: container, child: app),
      );
      await tester.pump();
    });
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drainHiveWritesForTesting(tester);
    });
  }

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$subject/$brightness 地图和纪念册在 320px / 2倍文字不溢出', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.runAsync(
          () => SettingsRepository().setLearningBackground(5, '上'),
        );
        await mount(
          tester,
          const MathAdventurePage(),
          subject: subject,
          brightness: brightness,
        );
        expect(find.text('当前关卡 · 开始探索'), findsOneWidget);
        expect(find.text('未解锁 · 先走完前一站'), findsWidgets);
        expect(find.textContaining('走过'), findsNothing);
        expect(find.textContaining('每组'), findsNothing);
        expect(find.textContaining('片风景'), findsNothing);
        await tester.tap(find.byTooltip('找到当前关卡'));
        await tester.pump();
        expect(find.text('当前关卡 · 开始探索').hitTestable(), findsOneWidget);
        final node = tester.getSemantics(find.text('当前关卡 · 开始探索'));
        expect(node.label, contains('当前关卡'));
        expect(tester.takeException(), isNull);
        await mount(
          tester,
          const MathAdventureAlbumPage(),
          subject: subject,
          brightness: brightness,
        );
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        // 逐册滚动，覆盖懒构建的全部十二册和长标题。
        for (var i = 0; i < 24; i++) {
          scroll.jumpTo((scroll.pixels + 650).clamp(0, scroll.maxScrollExtent));
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (scroll.pixels == scroll.maxScrollExtent) break;
        }
        expect(find.text('6 年级下册'), findsOneWidget);
        await mount(
          tester,
          const Scaffold(
            body: SingleChildScrollView(child: MathAdventureEntry()),
          ),
          subject: subject,
          brightness: brightness,
        );
        expect(find.text('数学探险'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('大字号下可从顶部定位到最后一片区域的当前关卡', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final route = MathAdventureCatalog.route(
      grade: 6,
      semester: '下',
      difficulty: DifficultyLevel.medium,
    );
    await tester.runAsync(() async {
      await SettingsRepository().setLearningBackground(6, '下');
      final progress = MathAdventureProgress(
        profileId: 'default',
        grade: 6,
        semester: '下',
        completedSkillIds: route.take(route.length - 1).map((s) => s.id),
      );
      await HiveBoxes.mathAdventureProgress.put(progress.key, progress);
    });
    await mount(tester, const MathAdventurePage());
    expect(find.text(route.last.label).hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('找到当前关卡'));
    await tester.pumpAndSettle();
    expect(find.text(route.last.label).hitTestable(), findsOneWidget);
    expect(find.text(MathAdventureRegion.highland.title), findsOneWidget);
    expect(find.text(MathAdventureRegion.highland.subtitle), findsOneWidget);
    expect(find.text(MathAdventureRegion.forest.title), findsNothing);
    final navigationBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    expect(
      tester.getTopLeft(find.text(route.last.label)).dy,
      greaterThan(navigationBottom),
    );
    final current = tester.getSemantics(find.text('当前关卡 · 开始探索'));
    expect(current.label, contains(route.last.label));
    expect(current.rect.height, greaterThanOrEqualTo(44));
    expect(current.rect.width, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('滚动切换区域导航，导航下的关卡不拦截点击', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(
      () => SettingsRepository().setLearningBackground(5, '上'),
    );
    await mount(tester, const MathAdventurePage());
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final navigationBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final skillLabel = find.text('整数加法');
    // Move the real active button behind an otherwise empty part of the
    // transparent navigation. It must be clipped, not just covered by a wash.
    scroll.jumpTo(tester.getCenter(skillLabel).dy - navigationBottom + 8);
    await tester.pumpAndSettle();
    expect(tester.getCenter(skillLabel).dy, lessThan(navigationBottom));
    expect(skillLabel.hitTestable(), findsNothing);

    final visibleRegions = MathAdventureCatalog.regions(
      grade: 5,
      semester: '上',
      difficulty: DifficultyLevel.medium,
    ).keys;
    for (final region in visibleRegions.skip(1)) {
      final scene = find.byWidgetPredicate(
        (widget) => widget is AdventureRegionScene && widget.region == region,
      );
      final offset =
          scroll.pixels + tester.getTopLeft(scene).dy - navigationBottom;
      scroll.jumpTo(
        offset.clamp(scroll.minScrollExtent, scroll.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expect(find.text(region.title), findsOneWidget);
      expect(find.text(region.subtitle), findsOneWidget);
      expect(tester.getBottomLeft(find.byType(AppBar)).dy, navigationBottom);
    }
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text(MathAdventureRegion.forest.title), findsOneWidget);
    expect(skillLabel.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('两节点全通关、收藏跨册保留、切档和统一失效刷新', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final original = MathAdventureProgress(
      profileId: 'default',
      grade: 1,
      semester: '上',
      completedSkillIds: ['addition', 'subtraction'],
      collectedRegionIds: ['arithmetic_forest'],
    );
    await tester.runAsync(
      () => HiveBoxes.mathAdventureProgress.put(original.key, original),
    );
    await mount(tester, const MathAdventurePage(), container: container);
    expect(find.text('本册探索完成！'), findsOneWidget);
    expect(find.text('已获得 · 晨光叶'), findsOneWidget);
    expect(find.text('已完成 · 再玩一组'), findsNWidgets(2));
    await tester.runAsync(
      () => SettingsRepository().setLearningBackground(1, '下'),
    );
    await tester.pump();
    expect(find.text('本册探索完成！'), findsNothing);
    expect(find.text('已获得 · 晨光叶'), findsNothing);
    await mount(tester, const MathAdventureAlbumPage(), container: container);
    expect(find.text('晨光叶 · 已收集'), findsOneWidget);
    await tester.runAsync(() async => ProfileScope.switchTo('child2'));
    await tester.pump();
    expect(find.text('晨光叶 · 已收集'), findsNothing);
    await tester.runAsync(() async => ProfileScope.reset());
    await tester.pump();
    expect(find.text('晨光叶 · 已收集'), findsOneWidget);
    await tester.runAsync(() => HiveBoxes.mathAdventureProgress.clear());
    invalidateAllHiveProviders(container.invalidate);
    await tester.pump();
    expect(find.text('晨光叶 · 已收集'), findsNothing);
    expect(find.text('已收集 0 件纪念物 · 属于当前学习档案'), findsOneWidget);
  });

  testWidgets('读取失败呈现重试，恢复后显示真实路线', (tester) async {
    final repository = _ReadFailure();
    final container = ProviderContainer(
      overrides: [
        mathAdventureRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await mount(tester, const MathAdventurePage(), container: container);
    expect(find.text('旅途记录暂时打不开'), findsOneWidget);
    repository.fail = false;
    await tester.runAsync(() => tester.tap(find.text('重新打开')));
    await tester.pump();
    expect(find.text('四则森林'), findsOneWidget);
    expect(find.text('整数加法'), findsOneWidget);
    expect(find.text('整数减法'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('纪念册目标取十二册所有难度的区域并集，目录覆盖技能唯一', () {
    final mapped = MathAdventureRegion.values.expand((r) => r.skills).toList();
    expect(mapped.toSet().length, mapped.length);
    expect(MathAdventureCatalog.collectible(1, '上'), {
      MathAdventureRegion.forest,
    });
    expect(
      MathAdventureCatalog.collectible(5, '上'),
      contains(MathAdventureRegion.highland),
    );
  });

  test('同一帧切档再切回仍重新创建仓储，不复用过期 revision', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final original = container.read(mathAdventureRepositoryProvider);
    ProfileScope.switchTo('child2');
    ProfileScope.reset();
    expect(original.assertCurrent, throwsStateError);
    final refreshed = container.read(mathAdventureRepositoryProvider);
    expect(identical(original, refreshed), isFalse);
    expect(refreshed.read(1, '上').completedSkillIds, isEmpty);
  });
}
