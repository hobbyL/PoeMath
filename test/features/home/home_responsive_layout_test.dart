import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/today_plan.dart';
import 'package:poemath/features/home/home_page.dart';
import 'package:poemath/features/home/practice_resume_section.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/home/providers/today_plan_providers.dart';
import 'package:poemath/features/home/textbook_resume_section.dart';
import 'package:poemath/features/home/today_plan_section.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  testWidgets('首页三组卡片随宽度切换列数，续读与草稿共同排列且空内容不占位', (tester) async {
    final book = textbookFixture();
    final drafts = [
      for (final kind in ['math', 'word'])
        <String, dynamic>{
          'kind': kind,
          'sessionId': 'resume-$kind',
          'records': [<String, dynamic>{}],
          'problems': List.filled(10, <String, dynamic>{}),
        },
    ];
    final draftState = StateProvider((ref) => drafts);
    final readingState = StateProvider<({Textbook book, int page})?>(
      (ref) => (book: book, page: 2),
    );
    final container = ProviderContainer(
      overrides: [
        staticDayKeyOverride(),
        isCheckedInProvider.overrideWithValue(true),
        dailyPoemGoalProvider.overrideWithValue(2),
        dailyMathGoalProvider.overrideWithValue(10),
        todayPoemCountProvider.overrideWithValue(0),
        todayMathCountProvider.overrideWithValue(0),
        practiceDraftsProvider.overrideWith(
          (ref) => Stream.value(ref.watch(draftState)),
        ),
        recentTextbookProvider.overrideWith((ref) => ref.watch(readingState)),
        textbookPathProvider(book.pdfSha256)
            .overrideWith((ref) async => '/book.pdf'),
        todayPlanProvider.overrideWith(
          (ref) async => const TodayPlan(
            dateKey: '2026-11-08',
            profileId: 'default',
            grade: 3,
            semester: '上',
            tasks: [
              TodayPlanTask(
                kind: TodayTaskKind.newPoem,
                targetId: 'a',
                title: '静夜思',
                baseline: 0,
                completed: true,
              ),
              TodayPlanTask(
                kind: TodayTaskKind.review,
                targetId: 'b',
                title: '登鹳雀楼',
                baseline: 0,
                completed: true,
              ),
              TodayPlanTask(
                kind: TodayTaskKind.mistake,
                targetId: 'c',
                title: '口算错题',
                baseline: 0,
                completed: true,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pumpHome(double contentWidth, double scale) async {
      tester.view.physicalSize = Size(
        contentWidth + SpacingTokens.md * 2,
        1000,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: PageAnimationScope(enabled: false, child: child!),
            ),
            home: const HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect cardRect(String title) => tester.getRect(
      find.ancestor(of: find.text(title), matching: find.byType(AppTile)),
    );

    void checkGrid(List<String> titles, double width, int maxColumns) {
      final columns = math.min(maxColumns, titles.length);
      final cardWidth = (width - SpacingTokens.sm * (columns - 1)) / columns;
      final cards = titles.map(cardRect).toList();
      for (var i = 0; i < cards.length; i++) {
        expect(cards[i].width, closeTo(cardWidth, .01));
        if (i < columns) {
          expect(cards[i].top, closeTo(cards.first.top, .01));
          expect(
            cards[i].left,
            closeTo(SpacingTokens.md + i * (cardWidth + SpacingTokens.sm), .01),
          );
        }
        if (columns == 1 && i > 0) {
          expect(
            cards[i].top - cards[i - 1].bottom,
            closeTo(SpacingTokens.sm, .01),
          );
        }
        for (var j = 0; j < i; j++) {
          expect(cards[i].overlaps(cards[j]), isFalse);
        }
      }
    }

    final readingTitle = '继续读《${book.title}》';
    const goals = ['诗词 0/2 首', '口算 0/10 题'];
    const tasks = ['新学 · 静夜思', '复习 · 登鹳雀楼', '错题回练 · 口算错题'];
    for (final (width, columns, scale) in [
      (320.0, 1, 1.0),
      (599.0, 1, 1.0),
      (600.0, 2, 1.0),
      (899.0, 2, 1.0),
      (900.0, 3, 1.0),
      (900.0, 3, 2.0),
    ]) {
      await pumpHome(width, scale);
      if (width == 320) await drainHiveWritesForTesting(tester);
      checkGrid(goals, width, columns);
      checkGrid(['继续上次口算', '继续上次应用题', readingTitle], width, columns);
      checkGrid(tasks, width, columns);
      expect(tester.takeException(), isNull);
    }

    await pumpHome(900, 1);
    container.read(draftState.notifier).state = [drafts.first];
    await tester.pumpAndSettle();
    checkGrid(['继续上次口算', readingTitle], 900, 3);

    container.read(readingState.notifier).state = null;
    await tester.pumpAndSettle();
    checkGrid(['继续上次口算'], 900, 3);
    expect(find.text(readingTitle), findsNothing);

    container.read(readingState.notifier).state = (book: book, page: 2);
    container.read(draftState.notifier).state = [];
    await tester.pumpAndSettle();
    checkGrid([readingTitle], 900, 3);
    expect(find.text('继续练习'), findsOneWidget);

    container.read(readingState.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('继续练习'), findsNothing);
    const goalNote = '今日练习清单提供额外复习建议，不影响打卡目标。';
    expect(
      tester.getTopLeft(find.byType(TodayPlanSection)).dy,
      closeTo(
        tester.getRect(find.text(goalNote)).bottom + SpacingTokens.lg,
        .01,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainHiveWritesForTesting(tester);
  });
}
