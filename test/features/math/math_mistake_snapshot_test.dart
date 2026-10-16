import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/features/math/math_mistake_snapshot.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

MathMistake _mistake() => MathMistake(
      id: 'one',
      profileId: 'default',
      problemText: '38 + 45 = ?',
      correctAnswer: '83',
      userAnswer: '83',
      problemType: 'vertical',
      grade: 2,
      errorType: VerticalAttempt.errorCategory,
    );

void main() {
  test('快照读取保留原题与真实错误过程，结果相同仍然判错', () {
    final problem = MathProblem(
      operands: [NumberValue.fromInt(38), NumberValue.fromInt(45)],
      operators: const [Operator.add],
      result: NumberValue.fromInt(83),
      mode: ProblemMode.vertical,
      grade: 2,
      semester: '上',
      skillId: 'addition_carry',
    );
    const attempt = VerticalAttempt(ones: '3', tens: '8', regroup: '0');
    final mistake = _mistake()
      ..problemJson = jsonEncode(problem.toJson())
      ..attemptJson = jsonEncode(attempt.toJson());
    expect(mistake.originalProblem!.toJson(), problem.toJson());
    expect(mistake.originalAttempt!.toJson(), attempt.toJson());
    expect(mistake.originalAttempt!.answer(mistake.originalProblem!), '83');
    expect(mistake.originalAttempt!.judge(mistake.originalProblem!).isCorrect,
        isFalse,);
  });

  test('缺少快照的旧错题不伪造过程', () {
    final mistake = _mistake();
    expect(mistake.originalProblem, isNull);
    expect(mistake.originalAttempt, isNull);
  });

  test('损坏题目和过程快照返回不可用，不伪造可判分题目', () {
    final mistake = _mistake()
      ..problemJson = '[]'
      ..attemptJson = '{"v":2}';
    expect(mistake.originalProblem, isNull);
    expect(mistake.originalAttempt, isNull);
  });
}
