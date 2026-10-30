import 'package:poemath/data/models/textbook_course.dart';

enum TextbookExerciseResult {
  correct,
  incorrect,
  parentPending,
  parentCorrect,
  parentAgain,
}

class TextbookExerciseAnswer {
  const TextbookExerciseAnswer.choice(this.choiceIds)
      : questionType = TextbookExerciseQuestionType.choice,
        blankAnswers = const [],
        oralCompleted = false;
  const TextbookExerciseAnswer.fillBlank(this.blankAnswers)
      : questionType = TextbookExerciseQuestionType.fillBlank,
        choiceIds = const [],
        oralCompleted = false;
  const TextbookExerciseAnswer.oral({this.oralCompleted = true})
      : questionType = TextbookExerciseQuestionType.oral,
        choiceIds = const [],
        blankAnswers = const [];

  final TextbookExerciseQuestionType questionType;
  final List<String> choiceIds;
  final List<String> blankAnswers;
  final bool oralCompleted;

  Map<String, dynamic> toJson() => {
        'questionType': questionType.name,
        'choiceIds': choiceIds,
        'blankAnswers': blankAnswers,
        'oralCompleted': oralCompleted,
      };

  factory TextbookExerciseAnswer.fromJson(Map<String, dynamic> json) {
    final typeName = _string(json, 'questionType');
    final type = TextbookExerciseQuestionType.values
        .where((item) => item.name == typeName)
        .firstOrNull;
    if (type == null) throw const FormatException('习题作答题型损坏');
    final choiceIds = _strings(json, 'choiceIds');
    final blankAnswers = _strings(json, 'blankAnswers');
    final oralCompleted = json['oralCompleted'];
    if (oralCompleted is! bool) {
      throw const FormatException('习题作答完成状态损坏');
    }
    final answer = switch (type) {
      TextbookExerciseQuestionType.choice =>
        TextbookExerciseAnswer.choice(choiceIds),
      TextbookExerciseQuestionType.fillBlank =>
        TextbookExerciseAnswer.fillBlank(blankAnswers),
      TextbookExerciseQuestionType.oral =>
        TextbookExerciseAnswer.oral(oralCompleted: oralCompleted),
    };
    if (type != TextbookExerciseQuestionType.choice && choiceIds.isNotEmpty ||
        type != TextbookExerciseQuestionType.fillBlank &&
            blankAnswers.isNotEmpty ||
        type != TextbookExerciseQuestionType.oral && oralCompleted) {
      throw const FormatException('习题作答题型不匹配');
    }
    return answer;
  }
}

class TextbookExerciseEvaluation {
  const TextbookExerciseEvaluation(this.result, this.itemResults);
  final TextbookExerciseResult result;
  final List<bool> itemResults;
}

TextbookExerciseEvaluation evaluateTextbookExercise(
  TextbookCourseExercise exercise,
  TextbookExerciseAnswer answer,
) {
  if (answer.questionType != exercise.questionType) {
    throw const FormatException('习题作答题型已过期');
  }
  if (exercise.answerType != TextbookAnswerType.exact) {
    return const TextbookExerciseEvaluation(
      TextbookExerciseResult.parentPending,
      [],
    );
  }
  return switch (exercise.questionType) {
    TextbookExerciseQuestionType.choice => _evaluateChoice(exercise, answer),
    TextbookExerciseQuestionType.fillBlank =>
      _evaluateFillBlank(exercise, answer),
    TextbookExerciseQuestionType.oral => const TextbookExerciseEvaluation(
        TextbookExerciseResult.parentPending,
        [],
      ),
  };
}

TextbookExerciseEvaluation _evaluateChoice(
  TextbookCourseExercise exercise,
  TextbookExerciseAnswer answer,
) {
  final selected = answer.choiceIds.toSet();
  if (selected.length != answer.choiceIds.length ||
      selected.any(
        (id) => !exercise.choiceOptions.any((option) => option.id == id),
      )) {
    throw const FormatException('选择题作答选项无效');
  }
  final expected = exercise.correctChoiceIds.toSet();
  final itemResults = [
    for (final option in exercise.choiceOptions)
      selected.contains(option.id) == expected.contains(option.id),
  ];
  return TextbookExerciseEvaluation(
    selected.length == expected.length && selected.containsAll(expected)
        ? TextbookExerciseResult.correct
        : TextbookExerciseResult.incorrect,
    itemResults,
  );
}

TextbookExerciseEvaluation _evaluateFillBlank(
  TextbookCourseExercise exercise,
  TextbookExerciseAnswer answer,
) {
  if (answer.blankAnswers.length != exercise.fillBlanks.length) {
    throw const FormatException('填空题作答数量无效');
  }
  final itemResults = <bool>[];
  for (var index = 0; index < exercise.fillBlanks.length; index++) {
    final blank = exercise.fillBlanks[index];
    itemResults.add(
      blank.answers.map(_normalizeAnswer).contains(
            _normalizeAnswer(answer.blankAnswers[index]),
          ),
    );
  }
  return TextbookExerciseEvaluation(
    itemResults.every((value) => value)
        ? TextbookExerciseResult.correct
        : TextbookExerciseResult.incorrect,
    itemResults,
  );
}

String normalizeTextbookExerciseAnswer(String value) => _normalizeAnswer(value);

String _normalizeAnswer(String value) => value
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll('，', ',')
    .replaceAll('。', '.')
    .replaceAll('；', ';')
    .replaceAll('：', ':')
    .replaceAll('！', '!')
    .replaceAll('？', '?');

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('习题作答 $key 损坏');
  }
  return value;
}

List<String> _strings(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('习题作答 $key 损坏');
  }
  return List.unmodifiable(value.cast<String>());
}
