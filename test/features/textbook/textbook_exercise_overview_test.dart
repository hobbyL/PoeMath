import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
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
}
