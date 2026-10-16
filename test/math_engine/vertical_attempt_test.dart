import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

MathProblem _problem(int a, int b, Operator op) => MathProblem(
      operands: [NumberValue.fromInt(a), NumberValue.fromInt(b)],
      operators: [op],
      result: NumberValue.fromInt(op == Operator.add ? a + b : a - b),
      mode: ProblemMode.vertical,
      grade: 2,
      difficulty: 2,
    );

void main() {
  test('过程专项生成始终是可逐列练习的两位数，知识点不混题', () {
    for (final skill in [
      MathSkill.additionCarry,
      MathSkill.subtractionBorrow,
    ]) {
      for (var seed = 0; seed < 40; seed++) {
        final problem = MathEngine.generate(
            grade: 2,
            semester: '上',
            difficulty: DifficultyLevel.medium,
            mode: ProblemMode.vertical,
            skillId: skill.id,
            verticalProcessOnly: true,
            random: Random(seed),);
        expect(VerticalAttempt.supports(problem), isTrue);
        expect(problem.skillId, skill.id);
      }
    }
    expect(
        () => MathEngine.generate(
            grade: 2, semester: '上', verticalProcessOnly: true,),
        throwsArgumentError,);
  });
  for (final (a, b, op, ones, tens, hundreds, regroup) in [
    (38, 45, Operator.add, '3', '8', '', '1'),
    (52, 38, Operator.subtract, '4', '1', '', '1'),
    (23, 14, Operator.add, '7', '3', '', '0'),
    (86, 24, Operator.subtract, '2', '6', '', '0'),
    (95, 27, Operator.add, '2', '2', '1', '1'),
    (10, 90, Operator.add, '0', '0', '1', '0'),
    (20, 19, Operator.subtract, '1', '0', '', '1'),
  ]) {
    test('$a ${op.symbol} $b 逐列和进退位同时判定', () {
      final problem = _problem(a, b, op);
      final attempt = VerticalAttempt(
          ones: ones, tens: tens, hundreds: hundreds, regroup: regroup,);
      expect(VerticalAttempt.supports(problem), isTrue);
      expect(attempt.judge(problem).isCorrect, isTrue);
      expect(
          attempt
              .withField('regroup', regroup == '1' ? '0' : '1')
              .judge(problem)
              .isCorrect,
          isFalse,);
      expect(
          attempt
              .withField('ones', (int.parse(ones) + 1).toString())
              .judge(problem)
              .isCorrect,
          isFalse,);
      expect(attempt.withField('regroup', '').complete(problem), isFalse);
      expect(
          VerticalAttempt.fromJson(jsonDecode(jsonEncode(attempt.toJson()))
                  as Map<String, dynamic>,)
              .toJson(),
          attempt.toJson(),);
    });
  }
  test('结果正确而未填过程不能通过，百位不能靠前导零替代', () {
    final problem = _problem(38, 45, Operator.add);
    expect(const VerticalAttempt(ones: '3', tens: '8').judge(problem).isCorrect,
        isFalse,);
    expect(
        const VerticalAttempt(ones: '2', tens: '2', hundreds: '0', regroup: '1')
            .judge(_problem(95, 27, Operator.add))
            .isCorrect,
        isFalse,);
    expect(VerticalAttempt.supports(_problem(8, 5, Operator.add)), isFalse);
    expect(
        VerticalAttempt.supports(_problem(38, 45, Operator.multiply)), isFalse,);
  });
}
