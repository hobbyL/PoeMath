// test/math_engine/math_problem_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';

void main() {
  group('MathProblem', () {
    test('加法题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(p.problemText, '3 + 5 = ?');
      expect(p.answerText, '8');
    });

    test('减法题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(10), NumberValue.fromInt(3)],
        operators: [Operator.subtract],
        result: NumberValue.fromInt(7),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(p.problemText, '10 - 3 = ?');
      expect(p.answerText, '7');
    });

    test('乘法题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(6), NumberValue.fromInt(7)],
        operators: [Operator.multiply],
        result: NumberValue.fromInt(42),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      expect(p.problemText, '6 × 7 = ?');
      expect(p.answerText, '42');
    });

    test('除法题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(42), NumberValue.fromInt(7)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(6),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      expect(p.problemText, '42 ÷ 7 = ?');
      expect(p.answerText, '6');
    });

    test('findMissing 题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findMissing,
        grade: 1,
        missingIndex: 0,
      );
      expect(p.problemText, '? + 5 = 3');
    });

    test('compare 题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.compare,
        grade: 2,
        compareRelation: CompareRelation.greaterThan,
        compareTarget: NumberValue.fromInt(7),
      );
      expect(p.problemText, '3 + 5 ○ 7');
      expect(p.answerText, '>');
    });

    test('余数题目文本', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 2,
      );
      expect(p.answerText, '3…2');
    });

    test('分数答案文本', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 3),
          NumberValue.fromFraction(1, 6),
        ],
        operators: [Operator.add],
        result: NumberValue.fromFraction(1, 2),
        mode: ProblemMode.findResult,
        grade: 5,
        resultForm: ResultForm.fraction,
      );
      expect(p.answerText, '1/2');
    });

    test('chain 题目文本', () {
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
      expect(p.problemText, '3 + 5 - 2 = ?');
    });

    test('withBrackets 题目文本', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(3),
          NumberValue.fromInt(5),
          NumberValue.fromInt(2),
        ],
        operators: [Operator.add, Operator.multiply],
        result: NumberValue.fromInt(16),
        mode: ProblemMode.withBrackets,
        grade: 3,
        bracketRange: (0, 2),
      );
      expect(p.problemText, '(3 + 5) × 2 = ?');
    });

    test('toString 返回 problemText', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(1), NumberValue.fromInt(2)],
        operators: [Operator.add],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(p.toString(), p.problemText);
    });
  });

  group('Operator', () {
    test('symbol', () {
      expect(Operator.add.symbol, '+');
      expect(Operator.subtract.symbol, '-');
      expect(Operator.multiply.symbol, '×');
      expect(Operator.divide.symbol, '÷');
    });

    test('toString', () {
      expect(Operator.add.toString(), '+');
    });
  });

  group('CompareRelation', () {
    test('symbol', () {
      expect(CompareRelation.greaterThan.symbol, '>');
      expect(CompareRelation.lessThan.symbol, '<');
      expect(CompareRelation.equal.symbol, '=');
    });
  });
}
