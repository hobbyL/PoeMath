import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/app.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/theme_providers.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/math/widgets/practice_entry_card.dart';
import 'package:poemath/features/math/word_problem/word_problem_library_page.dart';
import 'package:poemath/features/home/playful_check_in_content.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/domain/daily_goal_activity.dart';

import '../helpers/day_key_override.dart';
import '../helpers/hive_test_helper.dart';
import '../helpers/theme_contrast.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  for (final preset in [AppSubject.candy, AppSubject.space]) {
    for (final (width, scale, mode) in [
      (411.0, 1.0, ThemeMode.light),
      (411.0, 1.0, ThemeMode.dark),
      (320.0, 2.0, ThemeMode.light),
    ]) {
      testWidgets('$preset/$mode/$width/$scale 布局有独立轮廓且入口可用', (tester) async {
        tester.view.physicalSize = Size(width, 914);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = ProviderContainer(
          overrides: [staticDayKeyOverride()],
        );
        addTearDown(container.dispose);
        container.read(activeSubjectProvider.notifier).setSubject(preset);
        container.read(themeModeProvider.notifier).setMode(mode);
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const App()),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 3));
        await drainHiveWritesForTesting(tester);

        Finder goal(String title) => find.byWidgetPredicate(
          (widget) => widget is AppTile && widget.title.startsWith(title),
        );
        final poem = tester.getRect(goal('诗词 0/1'));
        final math = tester.getRect(goal('口算 0/10'));
        if (preset == AppSubject.candy && scale == 1) {
          expect(poem.top, math.top);
          expect(math.left, greaterThan(poem.right));
        } else {
          expect(math.top, greaterThan(poem.bottom));
          expect(math.left, poem.left);
        }

        final selected = find.byKey(const ValueKey('navigation-tab-首页'));
        final navIcon = find.descendant(
          of: selected,
          matching: find.byType(Icon),
        );
        final navLabel = find.descendant(
          of: selected,
          matching: find.text('首页'),
        );
        if (preset == AppSubject.space) {
          expect(
            tester.getRect(navIcon).bottom,
            lessThan(tester.getRect(navLabel).top),
          );
        } else {
          expect(
            tester.getCenter(navIcon).dy,
            closeTo(tester.getCenter(navLabel).dy, 1),
          );
          expect(
            tester.getRect(find.byType(NavigationBar)).left,
            greaterThan(0),
          );
        }
        final button = tester.widget<TextButton>(
          find.descendant(of: selected, matching: find.byType(TextButton)),
        );
        expect(
          contrastRatio(
            button.style!.foregroundColor!.resolve({})!,
            button.style!.backgroundColor!.resolve({})!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        for (final label in ['首页', '语文', '数学', '我的']) {
          final tab = find.byKey(ValueKey('navigation-tab-$label'));
          final bounds = tester.getRect(
            find.descendant(of: tab, matching: find.byType(TextButton)),
          );
          expect(bounds.width, greaterThanOrEqualTo(44));
          expect(bounds.height, greaterThanOrEqualTo(44));
        }

        await tester.tap(find.byKey(const ValueKey('navigation-tab-数学')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        final router = container.read(appRouterProvider);
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.mathTab,
        );
        final mathScroll = find
            .descendant(
              of: find.byType(MathTabPage),
              matching: find.byType(Scrollable),
            )
            .first;
        if (scale > 1) {
          await tester.scrollUntilVisible(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget is PracticeEntryCard && widget.title == '竖式计算',
                )
                .hitTestable(),
            120,
            scrollable: mathScroll,
          );
          await tester.pump();
        }
        final entries = find.byType(PracticeEntryCard);
        final first = tester.getRect(entries.at(0));
        final second = tester.getRect(entries.at(1));
        if (preset == AppSubject.candy && scale == 1) {
          expect(first.top, second.top);
          expect(second.left, greaterThan(first.right));
        } else {
          expect(second.top, greaterThan(first.bottom));
        }
        final wordProblem = find.byWidgetPredicate(
          (widget) => widget is PracticeEntryCard && widget.title == '应用题',
        );
        await tester.scrollUntilVisible(
          wordProblem.hitTestable(),
          180,
          scrollable: find
              .descendant(
                of: find.byType(MathTabPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pump();
        await tester.tap(wordProblem);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(WordProblemLibraryPage), findsOneWidget);
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const ValueKey('navigation-tab-我的')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.text(preset == AppSubject.candy ? '我的成长手账' : '探索员档案'),
          findsOneWidget,
        );
        expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
        expect(container.read(activeSubjectProvider), preset);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await drainHiveWritesForTesting(tester);
      });
    }
  }

  testWidgets('探索舷窗进度来自当天目标，完成与修改目标都会更新', (tester) async {
    final poems = StateProvider<int>((ref) => 0);
    final math = StateProvider<int>((ref) => 4);
    final goals = StateProvider<Set<DailyGoalActivity>>(
      (ref) => {DailyGoalActivity.poem, DailyGoalActivity.math},
    );
    final container = ProviderContainer(
      overrides: [
        staticDayKeyOverride(),
        todayPoemCountProvider.overrideWith((ref) => ref.watch(poems)),
        todayMathCountProvider.overrideWith((ref) => ref.watch(math)),
        dailyGoalTypesProvider.overrideWith((ref) => ref.watch(goals)),
      ],
    );
    addTearDown(container.dispose);
    container.read(activeSubjectProvider.notifier).setSubject(AppSubject.space);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pump(const Duration(seconds: 1));
    await drainHiveWritesForTesting(tester);
    final ring = find.descendant(
      of: find.byType(PlayfulCheckInContent),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(find.text('0 / 2 目标完成'), findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0);
    container.read(poems.notifier).state = 1;
    await tester.pump();
    expect(find.text('1 / 2 目标完成'), findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(ring).value, .5);
    expect(find.widgetWithText(FilledButton, '去练口算'), findsOneWidget);
    container.read(goals.notifier).state = {DailyGoalActivity.math};
    await tester.pump();
    expect(find.text('0 / 1 目标完成'), findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0);
    container.read(math.notifier).state = 12;
    await tester.pump();
    expect(find.text('1 / 1 目标完成'), findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 1);
    expect(find.widgetWithText(FilledButton, '打卡'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await drainHiveWritesForTesting(tester);
  });
}
