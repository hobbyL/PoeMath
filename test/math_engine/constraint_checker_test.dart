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

  group('ConstraintChecker 校验 6（模式白名单）', () {
    test('越权模式被拒绝并返回中文原因', () {
      // 一年级上不允许 chain 模式
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(3),
          NumberValue.fromInt(5),
          NumberValue.fromInt(2),
        ],
        operators: [Operator.add, Operator.subtract],
        result: NumberValue.fromInt(6),
        mode: ProblemMode.chain,
        grade: 1,
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade1a);
      expect(violation, isNotNull);
      expect(violation, contains('题目模式未被允许'));
      expect(violation, contains('chain'));
    });

    test('白名单内模式通过', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(3),
          NumberValue.fromInt(5),
          NumberValue.fromInt(2),
        ],
        operators: [Operator.add, Operator.subtract],
        result: NumberValue.fromInt(6),
        mode: ProblemMode.chain,
        grade: 3,
      );
      expect(ConstraintChecker.check(p, GradePresets.grade3a), isNull);
    });

    test('5a/6a/6b 允许 chain（修复后不再越权）', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(3),
          NumberValue.fromInt(5),
          NumberValue.fromInt(2),
        ],
        operators: [Operator.add, Operator.subtract],
        result: NumberValue.fromInt(6),
        mode: ProblemMode.chain,
        grade: 5,
      );
      expect(ConstraintChecker.check(p, GradePresets.grade5a), isNull);
      expect(ConstraintChecker.check(p, GradePresets.grade6a), isNull);
      expect(ConstraintChecker.check(p, GradePresets.grade6b), isNull);
    });
  });

  group('ConstraintChecker 校验 7（括号一致性）', () {
    test('括号题答案与显示语义不一致被拒绝', () {
      // (71 + 10) × 7 × 4 数学正确 2268，构造错误 result 351（Bug A 实例）
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(71),
          NumberValue.fromInt(10),
          NumberValue.fromInt(7),
          NumberValue.fromInt(4),
        ],
        operators: [
          Operator.add,
          Operator.multiply,
          Operator.multiply,
        ],
        result: NumberValue.fromInt(351),
        mode: ProblemMode.withBrackets,
        grade: 3,
        bracketRange: (0, 2),
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade3b);
      expect(violation, isNotNull);
      expect(violation, contains('括号题答案与显示语义不一致'));
    });

    test('括号语义正确的题通过', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(71),
          NumberValue.fromInt(10),
          NumberValue.fromInt(7),
          NumberValue.fromInt(4),
        ],
        operators: [
          Operator.add,
          Operator.multiply,
          Operator.multiply,
        ],
        result: NumberValue.fromInt(2268),
        mode: ProblemMode.withBrackets,
        grade: 3,
        bracketRange: (0, 2),
      );
      expect(ConstraintChecker.check(p, GradePresets.grade3b), isNull);
    });

    test('整数操作数括号题求值非整数被拒绝', () {
      // (70 ÷ 14) ÷ 2 = 5/2 非整数
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(70),
          NumberValue.fromInt(14),
          NumberValue.fromInt(2),
        ],
        operators: [Operator.divide, Operator.divide],
        result: NumberValue.fromFraction(5, 2),
        mode: ProblemMode.withBrackets,
        grade: 3,
        bracketRange: (0, 2),
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade3b);
      expect(violation, contains('括号题答案与显示语义不一致'));
    });

    test('括号题除零被拒绝', () {
      // 8 ÷ (3 - 3) + 2 无法求值
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(8),
          NumberValue.fromInt(3),
          NumberValue.fromInt(3),
          NumberValue.fromInt(2),
        ],
        operators: [
          Operator.divide,
          Operator.subtract,
          Operator.add,
        ],
        result: NumberValue.fromInt(2),
        mode: ProblemMode.withBrackets,
        grade: 3,
        bracketRange: (1, 3),
      );
      final violation = ConstraintChecker.check(p, GradePresets.grade3b);
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
