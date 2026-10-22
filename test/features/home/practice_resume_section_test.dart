import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/home/practice_resume_section.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final (width, scale, horizontal) in [
    (599.0, 1.0, false),
    (600.0, 1.0, true),
    (900.0, 1.0, true),
    (600.0, 1.7, true),
  ]) {
    testWidgets('续练卡片按区域宽度 $width 排列（字号 $scale），剩一张铺满', (tester) async {
      final drafts = PracticeDraftRepository();
      await tester.runAsync(() async {
        for (final kind in PracticeDraftRepository.kinds) {
          await drafts.save(
            kind,
            {
              'sessionId': 'resume-$kind',
              'records': [<String, dynamic>{}],
              'problems': List.filled(10, <String, dynamic>{}),
            },
          );
        }
      });
      final wordDraft = drafts.get('word');
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.resolve(
              subject: AppSubject.poem,
              brightness: Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: const PracticeResumeSection(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mathCard = find.ancestor(
        of: find.text('继续上次口算'),
        matching: find.byType(ColoredCard),
      );
      final wordCard = find.ancestor(
        of: find.text('继续上次应用题'),
        matching: find.byType(ColoredCard),
      );
      final mathRect = tester.getRect(mathCard);
      final wordRect = tester.getRect(wordCard);
      if (horizontal) {
        expect(wordRect.top, mathRect.top);
        expect(wordRect.left, mathRect.right + SpacingTokens.sm);
        expect(wordRect.size, mathRect.size);
        expect(mathRect.width + wordRect.width + SpacingTokens.sm, width);
      } else {
        expect(wordRect.top, mathRect.bottom + SpacingTokens.sm);
        expect(mathRect.width, width);
        expect(wordRect.width, width);
      }
      for (final card in [mathCard, wordCard]) {
        final arrow = find.descendant(
          of: card,
          matching: find.byIcon(Icons.chevron_right),
        );
        final discard = find.descendant(
          of: card,
          matching: find.widgetWithText(TextButton, '放弃草稿'),
        );
        expect(tester.getTopLeft(discard).dy, tester.getBottomLeft(arrow).dy);
        expect(
          tester.getRect(card).contains(tester.getBottomRight(discard)),
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: mathCard,
          matching: find.widgetWithText(TextButton, '放弃草稿'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '放弃草稿'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('继续上次口算'), findsNothing);
      expect(drafts.get('math'), isNull);
      expect(drafts.get('word'), wordDraft);
      expect(tester.getSize(wordCard).width, width);
      if (scale == 1) {
        expect(
          tester.getSize(wordCard).height,
          wordRect.height,
          reason: '横排不应额外撑高正常字号的卡片',
        );
      }
      expect(tester.takeException(), isNull);
      await drainHiveWritesForTesting(tester);
    });
  }

  for (final kind in PracticeDraftRepository.kinds) {
    for (final (width, scale) in [(400.0, 1.0), (320.0, 1.7)]) {
      testWidgets('$kind 续练卡片保持紧凑高度、箭头下放弃操作独立点击（字号 $scale）', (tester) async {
        final drafts = PracticeDraftRepository();
        await tester.runAsync(
          () => drafts.save(
            kind,
            {
              'sessionId': 'resume-$kind',
              'records': [<String, dynamic>{}],
              'problems': List.filled(10, <String, dynamic>{}),
            },
          ),
        );
        final original = drafts.get(kind);
        var resumed = 0;
        final route = kind == 'math'
            ? AppRoutes.mathPractice
            : AppRoutes.wordProblemPractice;
        final title = kind == 'math' ? '继续上次口算' : '继续上次应用题';
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      const PracticeResumeSection(),
                      AppTile(
                        key: const ValueKey('baseline'),
                        icon: Icons.play_circle_outline,
                        iconColor: Theme.of(context).colorScheme.secondary,
                        title: title,
                        subtitle: '已答 1 / 10 题',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GoRoute(
              path: route,
              builder: (_, state) {
                resumed++;
                return Scaffold(
                  body: Text('恢复：${state.uri.queryParameters['resume']}'),
                );
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.resolve(
                subject: kind == 'math' ? AppSubject.math : AppSubject.poem,
                brightness: Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final resumeTitle = find.descendant(
          of: find.byType(PracticeResumeSection),
          matching: find.text(title),
        );
        final card = find.ancestor(
          of: resumeTitle,
          matching: find.byType(ColoredCard),
        );
        final arrow = find.descendant(
          of: card,
          matching: find.byIcon(Icons.chevron_right),
        );
        final discard = find.widgetWithText(TextButton, '放弃草稿');
        final cardRect = tester.getRect(card);
        final arrowRect = tester.getRect(arrow);
        final discardRect = tester.getRect(discard);
        expect(arrowRect.left, greaterThan(cardRect.center.dx));
        expect(arrowRect.top, closeTo(tester.getTopLeft(resumeTitle).dy, 1));
        expect(discardRect.top, closeTo(arrowRect.bottom, 1));
        expect(discardRect.center.dx, greaterThan(cardRect.center.dx));
        expect(cardRect.contains(discardRect.topLeft), isTrue);
        expect(cardRect.contains(discardRect.bottomRight), isTrue);
        if (scale == 1) {
          expect(
            cardRect.height,
            tester.getSize(find.byKey(const ValueKey('baseline'))).height,
            reason: '新增放弃操作不能撑高正常字号的续练卡片',
          );
        }
        expect(tester.takeException(), isNull);

        await tester.tap(arrow);
        await tester.pumpAndSettle();
        expect(find.text('恢复：1'), findsOneWidget);
        expect(resumed, 1);
        router.pop();
        await tester.pumpAndSettle();

        await tester.tap(resumeTitle);
        await tester.pumpAndSettle();
        expect(find.text('恢复：1'), findsOneWidget);
        expect(resumed, 2);
        router.pop();
        await tester.pumpAndSettle();

        await tester.tap(discard);
        await tester.pumpAndSettle();
        expect(find.text('放弃未完成的题组？'), findsOneWidget);
        expect(resumed, 2);
        await tester.tap(find.text('保留草稿'));
        await tester.pumpAndSettle();
        expect(drafts.get(kind), original);

        await tester.tap(discard);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(FilledButton, '放弃草稿'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(drafts.get(kind), isNull);
        expect(resumeTitle, findsNothing);
        expect(resumed, 2);
        expect(tester.takeException(), isNull);
        await drainHiveWritesForTesting(tester);
      });
    }
  }
}
