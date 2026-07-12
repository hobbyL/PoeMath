// test/math_engine/constraint_checker_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/validators/constraint_checker.dart';

void main() {
  group('ConstraintChecker', () {
    test('合规题目通过', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(ConstraintChecker.check(p, GradePresets.grade1a), isNull);
    });

    test('结果超范围被拦截', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(8), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(13),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade1a);
      expect(violation, isNotNull);
      expect(violation, contains('超出范围'));
    });

    test('负数结果在不允许时被拦截', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.subtract],
        result: NumberValue.fromInt(-2),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade1a);
      expect(violation, isNotNull);
      expect(violation, contains('负'));
    });

    test('负数结果在允许时通过', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.subtract],
        result: NumberValue.fromInt(-2),
        mode: ProblemMode.findResult,
        grade: 6,
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade6b);
      expect(violation, isNull);
    });

    test('余数 ≥ 除数被拦截', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(3)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(4),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 5, // 5 >= 3
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade2b);
      expect(violation, isNotNull);
      expect(violation, contains('余数'));
    });

    test('操作数超范围被拦截', () {
      // 构造一个操作数超范围但结果在范围内的场景
      final pOver = MathProblem(
        operands: [NumberValue.fromInt(15), NumberValue.fromInt(3)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8), // 故意让结果在范围内
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final violation = ConstraintChecker.check(pOver, GradePresets.grade1a);
      expect(violation, isNotNull);
    });
  });

  group('DifficultyScorer', () {
    test('简单加法 - 难度 1-2', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final score = DifficultyScorer.score(p);
      expect(score, inInclusiveRange(1, 2));
    });

    test('乘法比加法难', () {
      final pAdd = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final pMul = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.multiply],
        result: NumberValue.fromInt(15),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      expect(
        DifficultyScorer.score(pMul),
        greaterThanOrEqualTo(DifficultyScorer.score(pAdd)),
      );
    });

    test('多步比单步难', () {
      final pSingle = MathProblem(
        operands: [NumberValue.fromInt(10), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(15),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final pMulti = MathProblem(
        operands: [
          NumberValue.fromInt(10),
          NumberValue.fromInt(5),
          NumberValue.fromInt(3),
        ],
        operators: [Operator.add, Operator.subtract],
        result: NumberValue.fromInt(12),
        mode: ProblemMode.chain,
        grade: 3,
      );
      expect(
        DifficultyScorer.score(pMulti),
        greaterThan(DifficultyScorer.score(pSingle)),
      );
    });

    test('难度范围 1-5', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(9999),
          NumberValue.fromInt(9999),
          NumberValue.fromInt(9999),
        ],
        operators: [Operator.multiply, Operator.multiply],
        result: NumberValue.fromInt(0),
        mode: ProblemMode.withBrackets,
        grade: 4,
        resultForm: ResultForm.fraction,
        bracketRange: (0, 2),
      );
      final score = DifficultyScorer.score(p);
      expect(score, inInclusiveRange(1, 5));
    });

    test('findMissing 增加难度', () {
      final pNormal = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final pMissing = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findMissing,
        grade: 1,
        missingIndex: 0,
      );
      expect(
        DifficultyScorer.score(pMissing),
        greaterThanOrEqualTo(DifficultyScorer.score(pNormal)),
      );
    });
  });
}
