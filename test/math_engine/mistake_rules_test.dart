// test/math_engine/mistake_rules_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/diagnostics/mistake_rule.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';

void main() {
  group('CarryOmissionRule', () {
    final rule = CarryOmissionRule();

    MathProblem addProblem(int a, int b) => MathProblem(
          operands: [NumberValue.fromInt(a), NumberValue.fromInt(b)],
          operators: [Operator.add],
          result: NumberValue.fromInt(a + b),
          mode: ProblemMode.findResult,
          grade: 1,
        );

    test('正确答案不匹配', () {
      final p = addProblem(18, 25);
      expect(rule.matches(p, NumberValue.fromInt(43)), isFalse);
    });

    test('差 10 匹配（进位遗漏）', () {
      final p = addProblem(18, 25);
      // 正确 43，如果学生写 33（差 10）
      expect(rule.matches(p, NumberValue.fromInt(33)), isTrue);
    });

    test('差 20 匹配', () {
      final p = addProblem(28, 35);
      // 正确 63，学生写 43（差 20）
      expect(rule.matches(p, NumberValue.fromInt(43)), isTrue);
    });

    test('差 100 匹配', () {
      final p = addProblem(55, 55);
      // 正确 110，学生写 10（差 100）
      expect(rule.matches(p, NumberValue.fromInt(10)), isTrue);
    });

    test('减法不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(25), NumberValue.fromInt(10)],
        operators: [Operator.subtract],
        result: NumberValue.fromInt(15),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(rule.matches(p, NumberValue.fromInt(5)), isFalse);
    });

    test('差 7 不匹配（非 10 的倍数）', () {
      final p = addProblem(18, 25);
      expect(rule.matches(p, NumberValue.fromInt(36)), isFalse);
    });

    test('describe 返回进位提示', () {
      final p = addProblem(18, 25);
      final diag = rule.describe(p);
      expect(diag.category, 'carry_omission');
      expect(diag.message, contains('进'));
    });
  });

  group('BorrowOmissionRule', () {
    final rule = BorrowOmissionRule();

    MathProblem subProblem(int a, int b) => MathProblem(
          operands: [NumberValue.fromInt(a), NumberValue.fromInt(b)],
          operators: [Operator.subtract],
          result: NumberValue.fromInt(a - b),
          mode: ProblemMode.findResult,
          grade: 1,
        );

    test('差 10 匹配（退位遗漏）', () {
      final p = subProblem(42, 18);
      // 正确 24，学生写 34（多 10）
      expect(rule.matches(p, NumberValue.fromInt(34)), isTrue);
    });

    test('差 20 匹配', () {
      final p = subProblem(52, 18);
      // 正确 34，学生写 54（多 20）
      expect(rule.matches(p, NumberValue.fromInt(54)), isTrue);
    });

    test('正确答案不匹配', () {
      final p = subProblem(42, 18);
      expect(rule.matches(p, NumberValue.fromInt(24)), isFalse);
    });

    test('加法不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(18), NumberValue.fromInt(25)],
        operators: [Operator.add],
        result: NumberValue.fromInt(43),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(rule.matches(p, NumberValue.fromInt(53)), isFalse);
    });

    test('差 5 不匹配（非 10 的倍数）', () {
      final p = subProblem(42, 18);
      expect(rule.matches(p, NumberValue.fromInt(29)), isFalse);
    });

    test('describe 返回退位提示', () {
      final p = subProblem(42, 18);
      final diag = rule.describe(p);
      expect(diag.category, 'borrow_omission');
      expect(diag.message, contains('借'));
    });
  });

  group('MultiplicationTableRule', () {
    final rule = MultiplicationTableRule();

    MathProblem mulProblem(int a, int b) => MathProblem(
          operands: [NumberValue.fromInt(a), NumberValue.fromInt(b)],
          operators: [Operator.multiply],
          result: NumberValue.fromInt(a * b),
          mode: ProblemMode.findResult,
          grade: 2,
        );

    test('口诀范围内错误匹配', () {
      final p = mulProblem(7, 8);
      expect(rule.matches(p, NumberValue.fromInt(54)), isTrue); // 应 56
    });

    test('正确答案不匹配', () {
      final p = mulProblem(7, 8);
      expect(rule.matches(p, NumberValue.fromInt(56)), isFalse);
    });

    test('超出口诀范围不匹配', () {
      final p = mulProblem(12, 5);
      expect(rule.matches(p, NumberValue.fromInt(55)), isFalse);
    });

    test('非乘法不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(7), NumberValue.fromInt(8)],
        operators: [Operator.add],
        result: NumberValue.fromInt(15),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      expect(rule.matches(p, NumberValue.fromInt(16)), isFalse);
    });

    test('describe 包含口诀', () {
      final p = mulProblem(7, 8);
      final diag = rule.describe(p);
      expect(diag.category, 'multiplication_table');
      expect(diag.message, contains('56'));
    });

    test('describe 使用小×大格式', () {
      final p = mulProblem(9, 3);
      final diag = rule.describe(p);
      expect(diag.message, contains('3'));
      expect(diag.message, contains('9'));
    });
  });

  group('OperationOrderRule', () {
    final rule = OperationOrderRule();

    test('先加后乘错误匹配', () {
      // 2 + 3 × 4 = 14（正确），学生从左到右算 = 20
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(2),
          NumberValue.fromInt(3),
          NumberValue.fromInt(4),
        ],
        operators: [Operator.add, Operator.multiply],
        result: NumberValue.fromInt(14),
        mode: ProblemMode.chain,
        grade: 3,
      );
      expect(rule.matches(p, NumberValue.fromInt(20)), isTrue);
    });

    test('正确答案不匹配', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(2),
          NumberValue.fromInt(3),
          NumberValue.fromInt(4),
        ],
        operators: [Operator.add, Operator.multiply],
        result: NumberValue.fromInt(14),
        mode: ProblemMode.chain,
        grade: 3,
      );
      expect(rule.matches(p, NumberValue.fromInt(14)), isFalse);
    });

    test('纯加法不匹配', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(2),
          NumberValue.fromInt(3),
          NumberValue.fromInt(4),
        ],
        operators: [Operator.add, Operator.add],
        result: NumberValue.fromInt(9),
        mode: ProblemMode.chain,
        grade: 3,
      );
      expect(rule.matches(p, NumberValue.fromInt(10)), isFalse);
    });

    test('单步运算不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(rule.matches(p, NumberValue.fromInt(7)), isFalse);
    });

    test('describe 返回运算顺序提示', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(2),
          NumberValue.fromInt(3),
          NumberValue.fromInt(4),
        ],
        operators: [Operator.add, Operator.multiply],
        result: NumberValue.fromInt(14),
        mode: ProblemMode.chain,
        grade: 3,
      );
      final diag = rule.describe(p);
      expect(diag.category, 'operation_order');
      expect(diag.message, contains('乘除'));
    });
  });

  group('RemainderMistakeRule', () {
    final rule = RemainderMistakeRule();

    test('余数模式错误匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 2,
      );
      expect(rule.matches(p, NumberValue.fromInt(4)), isTrue);
    });

    test('正确答案不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 2,
      );
      expect(rule.matches(p, NumberValue.fromInt(3)), isFalse);
    });

    test('非余数模式不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(10), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(2),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      expect(rule.matches(p, NumberValue.fromInt(3)), isFalse);
    });

    test('describe 包含除数', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 2,
      );
      final diag = rule.describe(p);
      expect(diag.message, contains('5'));
    });

    test('describe 提示余数必须小于除数', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 2,
      );
      final diag = rule.describe(p);
      expect(diag.message, contains('小'));
    });
  });

  group('DecimalAlignmentRule', () {
    final rule = DecimalAlignmentRule();

    test('10 倍关系匹配', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromDouble(3.5),
          NumberValue.fromDouble(2.1),
        ],
        operators: [Operator.add],
        result: NumberValue.fromDouble(5.6),
        mode: ProblemMode.findResult,
        grade: 4,
        resultForm: ResultForm.decimal,
      );
      // 学生写 56（正确答案的 10 倍）
      expect(rule.matches(p, NumberValue.fromDouble(56)), isTrue);
    });

    test('0.1 倍关系匹配', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromDouble(5.0),
          NumberValue.fromDouble(2.0),
        ],
        operators: [Operator.add],
        result: NumberValue.fromDouble(7.0),
        mode: ProblemMode.findResult,
        grade: 4,
        resultForm: ResultForm.decimal,
      );
      // 学生写 70（正确答案的 10 倍）
      expect(rule.matches(p, NumberValue.fromDouble(70)), isTrue);
    });

    test('正确答案不匹配', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromDouble(3.5),
          NumberValue.fromDouble(2.1),
        ],
        operators: [Operator.add],
        result: NumberValue.fromDouble(5.6),
        mode: ProblemMode.findResult,
        grade: 4,
        resultForm: ResultForm.decimal,
      );
      expect(rule.matches(p, NumberValue.fromDouble(5.6)), isFalse);
    });

    test('非小数模式不匹配', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      expect(rule.matches(p, NumberValue.fromInt(80)), isFalse);
    });

    test('describe 返回对齐提示', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromDouble(3.5),
          NumberValue.fromDouble(2.1),
        ],
        operators: [Operator.add],
        result: NumberValue.fromDouble(5.6),
        mode: ProblemMode.findResult,
        grade: 4,
        resultForm: ResultForm.decimal,
      );
      final diag = rule.describe(p);
      expect(diag.category, 'decimal_alignment');
      expect(diag.message, contains('小数点'));
    });
  });

  group('MistakeDiagnoser', () {
    test('匹配首个适用规则', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(18), NumberValue.fromInt(25)],
        operators: [Operator.add],
        result: NumberValue.fromInt(43),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final diag = MistakeDiagnoser.diagnose(p, NumberValue.fromInt(33));
      expect(diag, isNotNull);
      expect(diag!.category, 'carry_omission');
    });

    test('无规则匹配返回 null', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final diag = MistakeDiagnoser.diagnose(p, NumberValue.fromInt(7));
      expect(diag, isNull);
    });
  });
}
