import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/domain/textbook_exercise.dart';
import 'package:poemath/features/textbook/exercise/exercise_providers.dart';
import 'package:poemath/features/textbook/exercise/textbook_exercise_overview.dart';

import '../../helpers/textbook_course_fixture.dart';

TextbookCourseLesson lessonWithExercises() {
  final raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
  final exercises = lesson['exercises'] as List;
  final original = exercises.single as Map<String, dynamic>;
  exercises
    ..clear()
    ..addAll(<Map<String, dynamic>>[
      {
        ...original,
        'id': 'choice-1',
        'questionType': 'choice',
        'choiceMode': 'single',
        'choiceOptions': [
          {'id': 'A', 'text': '星'},
          {'id': 'B', 'text': '月'},
        ],
        'correctChoiceIds': ['A'],
        'answerType': 'exact',
        'answers': ['星'],
        'answerOrigin': 'textbook',
        'answerSources': [courseFixtureSource(3)],
      },
      {
        ...original,
        'id': 'multi-1',
        'questionType': 'choice',
        'choiceMode': 'multiple',
        'choiceOptions': [
          {'id': 'A', 'text': '星'},
          {'id': 'B', 'text': '月'},
        ],
        'correctChoiceIds': ['A', 'B'],
        'answerType': 'parentCheck',
        'answers': <String>[],
        'answerOrigin': 'none',
        'answerSources': <Map<String, dynamic>>[],
      },
      {
        ...original,
        'id': 'fill-1',
        'questionType': 'fillBlank',
        'fillBlanks': <Map<String, dynamic>>[
          {
            'id': 'one',
            'answers': ['星'],
          },
          {
            'id': 'two',
            'answers': ['月'],
          },
        ],
        'answerType': 'exact',
        'answers': ['星、月'],
        'answerOrigin': 'textbook',
        'answerSources': [courseFixtureSource(3)],
      },
    ]);
  return TextbookCoursePack.fromJson(raw).lessons.single;
}

Future<TextbookCourseLesson> pumpOralExercise(
  WidgetTester tester, {
  required bool parentPending,
  double textScale = 1,
}) async {
  final lesson =
      TextbookCoursePack.fromJson(courseFixtureWithReviewedExercise())
          .lessons
          .single;
  final exercise = lesson.exercises.single;
  final bookId = courseFixtureBook().pdfSha256;
  final progress = TextbookExerciseProgress(
    profileId: 'default',
    bookId: bookId,
    editionId: 'edition',
    records: {
      if (parentPending)
        TextbookExerciseProgress.targetKey(lesson.id, exercise.id):
            TextbookExerciseRecord(
          fingerprint: exercise.contentDigest,
          attempts: 1,
          lastResult: TextbookExerciseResult.parentPending,
        ),
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        textbookExerciseProgressProvider(bookId).overrideWith(
          (_) async => progress,
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: ColoredCard(
                color: Theme.of(context).colorScheme.primary,
                child: TextbookExerciseOverview(
                  bookId: bookId,
                  lesson: lesson,
                  exercises: lesson.exercises,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lesson;
}

void main() {
  testWidgets('按结构化题型渲染单选、多选和多空控件', (tester) async {
    final lesson = lessonWithExercises();
    final bookId = courseFixtureBook().pdfSha256;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookExerciseProgressProvider(bookId).overrideWith(
            (_) async => const TextbookExerciseProgress(
              profileId: 'default',
              bookId: 'book',
              editionId: 'edition',
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TextbookExerciseOverview(
                bookId: bookId,
                lesson: lesson,
                exercises: lesson.exercises,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('选择题'), findsNWidgets(2));
    expect(find.text('填空题'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    for (final textScale in [1.0, 2.0]) {
      for (final parentPending in [false, true]) {
        testWidgets(
          '口答标题同行靠右显示操作：宽$width、字号$textScale、待核对$parentPending',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final lesson = await pumpOralExercise(
              tester,
              parentPending: parentPending,
              textScale: textScale,
            );

            final complete = find.widgetWithText(FilledButton, '我已完成');
            final parent = find.widgetWithText(OutlinedButton, '家长核对');
            expect(complete, findsOneWidget);
            expect(parent, parentPending ? findsOneWidget : findsNothing);

            final titleRect = tester.getRect(find.text('口答题'));
            final completeRect = tester.getRect(complete);
            final contentRect =
                tester.getRect(find.byType(TextbookExerciseOverview));
            final actions = [
              completeRect,
              if (parentPending) tester.getRect(parent),
            ];
            expect(
              titleRect.right + SpacingTokens.sm,
              lessThanOrEqualTo(completeRect.left),
            );
            for (final rect in actions) {
              expect(rect.center.dy, closeTo(titleRect.center.dy, 0.01));
              expect(
                rect.width,
                greaterThanOrEqualTo(SpacingTokens.minTapTarget),
              );
              expect(
                rect.height,
                greaterThanOrEqualTo(SpacingTokens.minTapTarget),
              );
            }
            if (parentPending) {
              expect(
                completeRect.right + SpacingTokens.xs,
                lessThanOrEqualTo(actions.last.left),
              );
            }
            expect(actions.last.right, closeTo(contentRect.right, 0.01));
            expect(
              tester.getRect(find.text(lesson.exercises.single.prompt)).top,
              greaterThanOrEqualTo(actions.first.bottom + SpacingTokens.sm),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('标题右侧的家长核对按钮仍能打开核对弹窗', (tester) async {
    await pumpOralExercise(tester, parentPending: true);
    await tester.tap(find.widgetWithText(OutlinedButton, '家长核对'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('还要练习'), findsOneWidget);
    expect(find.text('确认完成'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
