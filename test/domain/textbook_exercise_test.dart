import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_exercise_progress.dart';
import 'package:poemath/domain/textbook_exercise.dart';

import '../helpers/textbook_course_fixture.dart';

TextbookCourseExercise exerciseWith(Map<String, dynamic> fields) {
  final raw = courseFixture();
  final exercise = (raw['lessons'] as List).single['exercises'] as List;
  (exercise.single as Map<String, dynamic>).addAll(fields);
  return TextbookCoursePack.fromJson(raw).lessons.single.exercises.single;
}

void main() {
  test('单选和多选按选项集合自动核对，并返回逐项结果', () {
    final exercise = exerciseWith({
      'questionType': 'choice',
      'choiceMode': 'multiple',
      'choiceOptions': [
        {'id': 'A', 'text': '星'},
        {'id': 'B', 'text': '月'},
        {'id': 'C', 'text': '云'},
      ],
      'correctChoiceIds': ['A', 'C'],
      'answerType': 'exact',
      'answers': ['星、云'],
      'answerOrigin': 'textbook',
      'answerSources': [courseFixtureSource(3)],
    });
    final correct = evaluateTextbookExercise(
      exercise,
      const TextbookExerciseAnswer.choice(['C', 'A']),
    );
    expect(correct.result, TextbookExerciseResult.correct);
    expect(correct.itemResults, [true, true, true]);

    final incorrect = evaluateTextbookExercise(
      exercise,
      const TextbookExerciseAnswer.choice(['A']),
    );
    expect(incorrect.result, TextbookExerciseResult.incorrect);
    expect(incorrect.itemResults, [true, true, false]);
  });

  test('多空答案逐空核对并统一空格和中文标点', () {
    final exercise = exerciseWith({
      'questionType': 'fillBlank',
      'fillBlanks': [
        {
          'id': 'one',
          'answers': ['星光'],
        },
        {
          'id': 'two',
          'answers': ['月，亮', '月,亮'],
        },
      ],
      'answerType': 'exact',
      'answers': ['星光、月亮'],
      'answerOrigin': 'textbook',
      'answerSources': [courseFixtureSource(3)],
    });
    final result = evaluateTextbookExercise(
      exercise,
      const TextbookExerciseAnswer.fillBlank([' 星光 ', '月，亮']),
    );
    expect(result.result, TextbookExerciseResult.correct);
    expect(result.itemResults, [true, true]);
  });

  test('口答和参考答案只记录待家长核对，答案可 JSON 往返', () {
    final exercise = exerciseWith({
      'answerType': 'reference',
      'answers': ['可以自由表达'],
      'answerOrigin': 'reviewerReference',
    });
    final answer = const TextbookExerciseAnswer.oral();
    expect(
      evaluateTextbookExercise(exercise, answer).result,
      TextbookExerciseResult.parentPending,
    );
    expect(
      TextbookExerciseAnswer.fromJson(answer.toJson()).oralCompleted,
      isTrue,
    );
    expect(
      () => TextbookExerciseAnswer.fromJson({
        ...answer.toJson(),
        'questionType': 'unknown',
      }),
      throwsFormatException,
    );
  });

  test('习题进度保存最近作答和统计并可往返', () {
    final answer = const TextbookExerciseAnswer.fillBlank(['星光']);
    final progress = TextbookExerciseProgress(
      profileId: 'child',
      bookId: 'book',
      editionId: 'edition',
      revision: 2,
      records: {
        TextbookExerciseProgress.targetKey('lesson', 'exercise'):
            TextbookExerciseRecord(
          fingerprint: 'fingerprint',
          attempts: 1,
          automaticCorrect: 1,
          lastAnswer: answer,
          lastResult: TextbookExerciseResult.correct,
          lastItemResults: const [true],
          lastDay: '2026-10-29',
        ),
      },
      operations: const ['op-1'],
    );
    final decoded = TextbookExerciseProgress.fromJson(
      jsonDecode(jsonEncode(progress.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.toJson(), progress.toJson());
  });
}
