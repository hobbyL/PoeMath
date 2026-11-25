import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/english_home_section.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/home/home_section.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/english_fixture.dart';
import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('英语首页分组沿用统一纸面和箭头且入口有效：$subject $brightness', (tester) async {
        final book = englishBook(), course = englishCourse();
        final lesson = course.lessons.single;
        final progress = EnglishProgress(
          profileId: 'default',
          bookId: book.pdfSha256,
          editionId: book.learningEditionId,
          lastLessonId: lesson.id,
          reviews: {
            '${lesson.id}/${lesson.targets.first.id}/meaning':
                EnglishReviewRecord(
                  fingerprint: lesson.targets.first.fingerprint,
                  nextDay: '2020-01-01',
                ),
          },
        );
        await tester.runAsync(() async {
          await HiveBoxes.settings.put(
            EnglishProgressRepository.keyFor(
              'default',
              book.pdfSha256,
              book.learningEditionId,
            ),
            jsonEncode(progress.toJson()),
          );
          final drafts = PracticeDraftRepository();
          for (final kind in ['englishPractice', 'englishSpeaking']) {
            final scope = '${book.pdfSha256}/${lesson.id}';
            drafts.claim(kind, scope: scope);
            await drafts.save(kind, {
              'sessionId': 'draft-$kind',
              'lessonId': lesson.id,
              'practiceKind': 'meaning',
              'due': false,
              'retry': false,
            }, scope: scope);
          }
        });
        final theme = AppTheme.resolve(
          subject: subject,
          brightness: brightness,
        );
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => AppScaffold(
                body: ListView(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  children: [
                    HomeEntryGroup(
                      children: [
                        AppTile(
                          flat: theme.appearance.ink,
                          title: '首页参照入口',
                          subtitle: '与首页卡片保持一致',
                          icon: Icons.school_outlined,
                          iconColor: theme.colorScheme.primary,
                          onTap: () {},
                        ),
                      ],
                    ),
                    const EnglishHomeSection(),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.englishLesson,
              builder: (_, _) => const AppScaffold(body: Text('课时已打开')),
            ),
          ],
        );
        addTearDown(router.dispose);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Future<void> mount(Size size) async {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                staticDayKeyOverride(),
                textbookListProvider.overrideWith((ref) => [book]),
                englishCourseProvider(book.pdfSha256)
                    .overrideWith((ref) async => course),
              ],
              child: MaterialApp.router(
                routerConfig: router,
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        for (final size in [const Size(320, 700), const Size(740, 320)]) {
          await mount(size);
          final group = find.descendant(
            of: find.byType(EnglishHomeSection),
            matching: find.byType(HomeEntryGroup),
          );
          final cards = find.descendant(
            of: group,
            matching: find.byType(ColoredCard),
          );
          expect(cards, findsNWidgets(theme.appearance.ink ? 1 : 4));
          final reference = find.widgetWithText(AppTile, '首页参照入口');
          final referenceArrow = find.descendant(
            of: reference,
            matching: find.byIcon(Icons.chevron_right),
          );
          final inset =
              tester.getRect(reference).right -
              tester.getRect(referenceArrow).right;
          for (final title in ['继续练习', '继续跟读', '继续学习', '到期复习 · 1 项']) {
            final tile = find.widgetWithText(AppTile, title);
            final arrow = find.descendant(
              of: tile,
              matching: find.byIcon(Icons.chevron_right),
            );
            expect(
              tester.getRect(tile).right - tester.getRect(arrow).right,
              closeTo(inset, .01),
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text('继续学习'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('继续学习'));
        await tester.pumpAndSettle();
        expect(find.text('课时已打开'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/english/book/${book.pdfSha256}/lesson/${lesson.id}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
