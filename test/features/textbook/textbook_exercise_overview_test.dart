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
  Map<String, dynamic>? raw,
}) async {
  final lesson = TextbookCoursePack.fromJson(
    raw ?? courseFixtureWithReviewedExercise(),
  ).lessons.single;
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
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
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
  return lesson;
}

double baselineFor(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final distance = box.getDryBaseline(
    box.constraints,
    TextBaseline.alphabetic,
  );
  expect(distance, isNotNull);
  return tester.getRect(finder).top + distance!;
}

void main() {
  testWidgets('每道习题使用独立卡片并渲染结构化答题控件', (tester) async {
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
    expect(find.byType(ColoredCard), findsNWidgets(lesson.exercises.length));
    final cardRects = <Rect>[];
    for (final exercise in lesson.exercises) {
      final card = find.byKey(
        ValueKey('textbook-exercise-${lesson.id}-${exercise.id}'),
      );
      expect(
        find.ancestor(of: card, matching: find.byType(ColoredCard)),
        findsNothing,
      );
      cardRects.add(tester.getRect(card));
    }
    for (var index = 1; index < cardRects.length; index++) {
      expect(
        cardRects[index].top - cardRects[index - 1].bottom,
        closeTo(SpacingTokens.md, 0.01),
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0]) {
    for (final textScale in [1.0, 2.0]) {
      for (final parentPending in [false, true]) {
        testWidgets(
          '题目替代题型标题且操作靠右：宽$width、字号$textScale、待核对$parentPending',
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

            final complete = find.widgetWithText(TextButton, '完成');
            final parent = find.widgetWithText(TextButton, '核对');
            expect(complete, findsOneWidget);
            expect(parent, parentPending ? findsOneWidget : findsNothing);
            expect(find.text('口答题'), findsNothing);
            final title = find.text('请说出测试句中的天体');
            expect(title, findsOneWidget);
            expect(find.text(lesson.exercises.single.prompt), findsNothing);

            final titleRect = tester.getRect(title);
            final completeRect = tester.getRect(complete);
            final cardRect = tester.getRect(
              find.byKey(
                ValueKey(
                  'textbook-exercise-${lesson.id}-${lesson.exercises.single.id}',
                ),
              ),
            );
            final actions = [
              completeRect,
              if (parentPending) tester.getRect(parent),
            ];
            expect(
              titleRect.right + SpacingTokens.sm,
              lessThanOrEqualTo(completeRect.left),
            );
            for (final action in [complete, if (parentPending) parent]) {
              final rect = tester.getRect(action);
              expect(
                baselineFor(tester, action),
                closeTo(baselineFor(tester, title), 0.01),
              );
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
            expect(
              actions.last.right,
              closeTo(cardRect.right - SpacingTokens.md, 0.01),
            );
            final headerTop = [titleRect, ...actions]
                .map((rect) => rect.top)
                .reduce((first, next) => first < next ? first : next);
            expect(
              headerTop - cardRect.top,
              closeTo(SpacingTokens.xs, 0.01),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('标题右侧的核对按钮仍能打开家长核对弹窗', (tester) async {
    await pumpOralExercise(tester, parentPending: true);
    await tester.tap(find.widgetWithText(TextButton, '核对'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('还要练习'), findsOneWidget);
    expect(find.text('确认完成'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通多行题将首行放到标题，后续题干独立保留', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final raw = courseFixture();
    final exercise =
        ((raw['lessons'] as List).single['exercises'] as List).single as Map;
    exercise['prompt'] = '分角色朗读课文。\n请按顺序讲述星月的故事。';
    await pumpOralExercise(
      tester,
      parentPending: true,
      textScale: 2,
      raw: raw,
    );

    final heading = find.text('分角色朗读课文');
    final complete = find.widgetWithText(TextButton, '完成');
    final body = find.text('请按顺序讲述星月的故事。');
    expect(heading, findsOneWidget);
    expect(body, findsOneWidget);
    expect(find.text('口答题'), findsNothing);
    expect(
      tester.getRect(heading).height,
      greaterThan(tester.getRect(complete).height),
    );
    expect(
      baselineFor(tester, heading),
      closeTo(baselineFor(tester, complete), 0.01),
    );
    expect(
      tester.getRect(body).top,
      greaterThanOrEqualTo(tester.getRect(heading).bottom + SpacingTokens.sm),
    );
    expect(tester.takeException(), isNull);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('排版题标题不重复，词组和加点保留（字号$textScale）', (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final raw = courseFixture();
      final exercise =
          ((raw['lessons'] as List).single['exercises'] as List).single as Map;
      exercise['prompt'] = '读一读，注意加点的词。\n𠀀月明亮\t看星星\n春风\t山河\n我发现这些加点的词是表示动作的。';
      exercise['promptLayout'] = [
        [
          {'text': '读一读，注意加点的词。', 'emphasis': <int>[]},
        ],
        [
          {
            'text': '𠀀月明亮',
            'emphasis': [0],
          },
          {
            'text': '看星星',
            'emphasis': [0],
          },
        ],
        [
          {'text': '春风', 'emphasis': <int>[]},
          {'text': '山河', 'emphasis': <int>[]},
        ],
        [
          {'text': '我发现这些加点的词是表示动作的。', 'emphasis': <int>[]},
        ],
      ];
      await pumpOralExercise(
        tester,
        parentPending: true,
        textScale: textScale,
        raw: raw,
      );

      final heading = find.text('读一读，注意加点的词');
      expect(heading, findsOneWidget);
      expect(find.text('口答题'), findsNothing);
      expect(find.text('春风'), findsOneWidget);
      expect(find.text('山河'), findsOneWidget);
      expect(find.text('𠀀'), findsOneWidget);
      expect(find.text('看'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsNWidgets(2));
      expect(find.textContaining('我发现这些加点的词是表示动作的。'), findsNothing);
      expect(
        tester.getRect(find.text('春风')).top,
        greaterThan(tester.getRect(heading).bottom),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('没有独占题首行的词组排版也完整保留且不重复', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final raw = courseFixture();
    final exercise =
        ((raw['lessons'] as List).single['exercises'] as List).single as Map;
    exercise['prompt'] = '星光\t月光\n春风\t山河';
    exercise['promptLayout'] = [
      [
        {'text': '星光', 'emphasis': <int>[]},
        {'text': '月光', 'emphasis': <int>[]},
      ],
      [
        {'text': '春风', 'emphasis': <int>[]},
        {'text': '山河', 'emphasis': <int>[]},
      ],
    ];
    await pumpOralExercise(
      tester,
      parentPending: true,
      textScale: 2,
      raw: raw,
    );
    for (final word in ['星光', '月光', '春风', '山河']) {
      expect(find.text(word), findsOneWidget);
    }
    expect(find.text('口答题'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('题首本身有加点时保留完整排版和Unicode文字', (tester) async {
    final raw = courseFixture();
    final exercise =
        ((raw['lessons'] as List).single['exercises'] as List).single as Map;
    exercise['prompt'] = '𠀀月\n春风\t山河';
    exercise['promptLayout'] = [
      [
        {
          'text': '𠀀月',
          'emphasis': [0],
        },
      ],
      [
        {'text': '春风', 'emphasis': <int>[]},
        {'text': '山河', 'emphasis': <int>[]},
      ],
    ];
    await pumpOralExercise(tester, parentPending: true, raw: raw);
    expect(find.text('𠀀'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(find.text('春风'), findsOneWidget);
    expect(find.text('山河'), findsOneWidget);
    expect(find.text('口答题'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
