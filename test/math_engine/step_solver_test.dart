// test/math_engine/step_solver_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';
import 'package:poemath/math_engine/step_solver/step_solver.dart';

void main() {
  group('StepSolver', () {
    test('加法无进位', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(23), NumberValue.fromInt(14)],
        operators: [Operator.add],
        result: NumberValue.fromInt(37),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
      expect(steps.last.description, contains('37'));
    });

    test('加法有进位', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(18), NumberValue.fromInt(25)],
        operators: [Operator.add],
        result: NumberValue.fromInt(43),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final steps = StepSolver.solve(p);
      expect(steps.length, greaterThanOrEqualTo(2));
      // 应有进位提示
      final hasCarry = steps.any((s) => s.description.contains('进'));
      expect(hasCarry, isTrue);
    });

    test('减法无退位', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(47), NumberValue.fromInt(23)],
        operators: [Operator.subtract],
        result: NumberValue.fromInt(24),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
      expect(steps.last.description, contains('24'));
    });

    test('减法有退位', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(42), NumberValue.fromInt(18)],
        operators: [Operator.subtract],
        result: NumberValue.fromInt(24),
        mode: ProblemMode.findResult,
        grade: 1,
      );
      final steps = StepSolver.solve(p);
      final hasBorrow = steps.any((s) => s.description.contains('借'));
      expect(hasBorrow, isTrue);
    });

    test('乘法', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(6), NumberValue.fromInt(7)],
        operators: [Operator.multiply],
        result: NumberValue.fromInt(42),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
      expect(steps.first.resultHint, '42');
    });

    test('除法', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(42), NumberValue.fromInt(7)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(6),
        mode: ProblemMode.findResult,
        grade: 2,
      );
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
    });

    test('除法有余数', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(17), NumberValue.fromInt(5)],
        operators: [Operator.divide],
        result: NumberValue.fromInt(3),
        mode: ProblemMode.findResult,
        grade: 2,
        resultForm: ResultForm.withRemainder,
        remainder: 2,
      );
      final steps = StepSolver.solve(p);
      expect(steps.length, greaterThanOrEqualTo(2));
      // 应有验算步骤
      final hasVerify = steps.any((s) => s.description.contains('验算'));
      expect(hasVerify, isTrue);
    });

    test('多步运算', () {
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
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
      // 应有先乘除后加减提示
      final hasOrder = steps.any((s) => s.description.contains('乘除'));
      expect(hasOrder, isTrue);
    });

    test('括号运算', () {
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
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
      final hasBracket = steps.any((s) => s.description.contains('括号'));
      expect(hasBracket, isTrue);
    });

    test('括号题完整步骤（AC8：括号内算式 → 括号外逐步 → 最终）', () {
      // (71 + 10) × 7 × 4 = 2268
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
      final steps = StepSolver.solve(p);
      // ① 先算括号提示
      expect(steps.first.description, '先算括号里的');
      // ② 括号内算式与结果
      expect(steps[1].description, contains('(71 + 10)'));
      expect(steps[1].description, contains('81'));
      // ③ 括号外逐步计算
      expect(steps[2].description, '81 × 7 = 567');
      expect(steps[3].description, '567 × 4 = 2268');
      // ④ 最终结果引用 problemText 与 answerText
      expect(steps.last.expression, p.problemText);
      expect(steps.last.resultHint, p.answerText);
      expect(steps.last.resultHint, '2268');
    });

    test('chain 题逐步折叠', () {
      // 2 + 3 × 4 = 14
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
      final steps = StepSolver.solve(p);
      final hasOrder = steps.any((s) => s.description.contains('乘除'));
      expect(hasOrder, isTrue);
      final calcSteps = steps.where((s) => s.description.contains('=')).toList();
      expect(calcSteps.any((s) => s.description.contains('3 × 4 = 12')), isTrue);
      expect(calcSteps.any((s) => s.description.contains('2 + 12 = 14')), isTrue);
      expect(steps.last.resultHint, '14');
    });

    test('chain 同级从左到右逐步', () {
      // 10 - 4 + 3 = 9
      final p = MathProblem(
        operands: [
          NumberValue.fromInt(10),
          NumberValue.fromInt(4),
          NumberValue.fromInt(3),
        ],
        operators: [Operator.subtract, Operator.add],
        result: NumberValue.fromInt(9),
        mode: ProblemMode.chain,
        grade: 3,
      );
      final steps = StepSolver.solve(p);
      expect(
        steps.any((s) => s.description.contains('10 - 4 = 6')),
        isTrue,
      );
      expect(
        steps.any((s) => s.description.contains('6 + 3 = 9')),
        isTrue,
      );
    });

    test('多步分数题无精度丢失（Fraction 精确中间值）', () {
      // 1/2 + 1/3 + 1/6 = 1
      final p = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 2),
          NumberValue.fromFraction(1, 3),
          NumberValue.fromFraction(1, 6),
        ],
        operators: [Operator.add, Operator.add],
        result: NumberValue.fromFraction(1, 1),
        mode: ProblemMode.chain,
        grade: 5,
      );
      final steps = StepSolver.solve(p);
      final joined = steps.map((s) => '${s.description}|${s.resultHint}').join(' ; ');
      // 中间值 5/6 不应显示为截断小数（如 0.83）
      expect(joined.contains('5/6'), isTrue);
      expect(joined.contains('0.83'), isFalse);
      expect(steps.last.resultHint, '1');
    });

    test('大数加法跳过逐位分解', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(500), NumberValue.fromInt(300)],
        operators: [Operator.add],
        result: NumberValue.fromInt(800),
        mode: ProblemMode.findResult,
        grade: 3,
      );
      final steps = StepSolver.solve(p);
      expect(steps, isNotEmpty);
      // 大数直接给出结果
      expect(steps.last.description, contains('800'));
    });
  });
}
