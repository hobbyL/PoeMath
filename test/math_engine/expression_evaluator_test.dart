// test/math_engine/expression_evaluator_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

NumberValue _i(int v) => NumberValue.fromInt(v);
NumberValue _f(int n, int d) => NumberValue.fromFraction(n, d);

void main() {
  group('ExpressionEvaluator.evaluate', () {
    test('单步加法', () {
      final r = ExpressionEvaluator.evaluate([_i(3), _i(5)], [Operator.add]);
      expect(r, isNotNull);
      expect(r!.asInteger, 8);
    });

    test('单步减法为负数', () {
      final r = ExpressionEvaluator.evaluate([_i(3), _i(5)], [Operator.subtract]);
      expect(r!.asInteger, -2);
    });

    test('单步乘法', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(6), _i(7)],
        [Operator.multiply],
      );
      expect(r!.asInteger, 42);
    });

    test('单步除法', () {
      final r = ExpressionEvaluator.evaluate([_i(42), _i(7)], [Operator.divide]);
      expect(r!.asInteger, 6);
    });

    test('除数为零返回 null（不触发 assert）', () {
      final r = ExpressionEvaluator.evaluate([_i(5), _i(0)], [Operator.divide]);
      expect(r, isNull);
    });

    test('同级加减从左到右：10 - 4 + 3 = 9', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(10), _i(4), _i(3)],
        [Operator.subtract, Operator.add],
      );
      expect(r!.asInteger, 9);
    });

    test('同级乘除从左到右：8 ÷ 4 × 2 = 4', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(8), _i(4), _i(2)],
        [Operator.divide, Operator.multiply],
      );
      expect(r!.asInteger, 4);
    });

    test('先乘除后加减：2 + 3 × 4 = 14', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(2), _i(3), _i(4)],
        [Operator.add, Operator.multiply],
      );
      expect(r!.asInteger, 14);
    });

    test('先乘除后加减：20 - 3 × 4 = 8', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(20), _i(3), _i(4)],
        [Operator.subtract, Operator.multiply],
      );
      expect(r!.asInteger, 8);
    });

    test('四步混合：36 ÷ 4 + 5 × 2 = 19', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(36), _i(4), _i(5), _i(2)],
        [Operator.divide, Operator.add, Operator.multiply],
      );
      expect(r!.asInteger, 19);
    });

    test('三步 chain 全整数除法：100 ÷ 5 ÷ 4 = 5', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(100), _i(5), _i(4)],
        [Operator.divide, Operator.divide],
      );
      expect(r!.asInteger, 5);
    });

    test('括号 (3 + 5) × 2 = 16', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(3), _i(5), _i(2)],
        [Operator.add, Operator.multiply],
        bracketRange: (0, 2),
      );
      expect(r!.asInteger, 16);
    });

    test('括号语义 Bug A 实例：(71 + 10) × 7 × 4 = 2268', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(71), _i(10), _i(7), _i(4)],
        [Operator.add, Operator.multiply, Operator.multiply],
        bracketRange: (0, 2),
      );
      expect(r!.asInteger, 2268);
    });

    test('无括号同题求值 351（对照）', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(71), _i(10), _i(7), _i(4)],
        [Operator.add, Operator.multiply, Operator.multiply],
      );
      expect(r!.asInteger, 351);
    });

    test('括号在中间位置：6 ÷ (2 - 3) = -6', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(6), _i(2), _i(3)],
        [Operator.divide, Operator.subtract],
        bracketRange: (1, 3),
      );
      expect(r!.asInteger, -6);
    });

    test('括号在末尾位置：8 - (3 + 2) = 3', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(8), _i(3), _i(2)],
        [Operator.subtract, Operator.add],
        bracketRange: (1, 3),
      );
      expect(r!.asInteger, 3);
    });

    test('括号值作除数为零返回 null：8 ÷ (3 - 3) + 2', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(8), _i(3), _i(3), _i(2)],
        [Operator.divide, Operator.subtract, Operator.add],
        bracketRange: (1, 3),
      );
      expect(r, isNull);
    });

    test('括号内多操作数折叠：(2 + 3 + 4) × 2 = 18', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(2), _i(3), _i(4), _i(2)],
        [Operator.add, Operator.add, Operator.multiply],
        bracketRange: (0, 3),
      );
      expect(r!.asInteger, 18);
    });

    test('括号内混合优先级：(71 + 10 × 2) = 91（非从左到右的 162）', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(71), _i(10), _i(2)],
        [Operator.add, Operator.multiply],
        bracketRange: (0, 3),
      );
      expect(r!.asInteger, 91);
    });

    test('括号内先除后减：(100 - 20 ÷ 4) × 2 = 190', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(100), _i(20), _i(4), _i(2)],
        [Operator.subtract, Operator.divide, Operator.multiply],
        bracketRange: (0, 3),
      );
      expect(r!.asInteger, 190);
    });

    test('分数操作数精确求值：1/2 + 1/3 = 5/6', () {
      final r = ExpressionEvaluator.evaluate(
        [_f(1, 2), _f(1, 3)],
        [Operator.add],
      );
      expect(r, equals(const Fraction(5, 6)));
    });

    test('分数除法：3/2 ÷ 1/4 = 6', () {
      final r = ExpressionEvaluator.evaluate(
        [_f(3, 2), _f(1, 4)],
        [Operator.divide],
      );
      expect(r!.asInteger, 6);
    });

    test('非整数中间结果保留精确分数：(70 ÷ 14) ÷ 2 = 5/2', () {
      final r = ExpressionEvaluator.evaluate(
        [_i(70), _i(14), _i(2)],
        [Operator.divide, Operator.divide],
        bracketRange: (0, 2),
      );
      expect(r, isNotNull);
      expect(r!.isInteger, isFalse);
      expect(r, equals(const Fraction(5, 2)));
    });

    test('分数与整数混合：(1/2 + 1/2) × 3 = 3', () {
      final r = ExpressionEvaluator.evaluate(
        [_f(1, 2), _f(1, 2), _i(3)],
        [Operator.add, Operator.multiply],
        bracketRange: (0, 2),
      );
      expect(r!.asInteger, 3);
    });

    test('操作数与运算符数量不匹配返回 null', () {
      expect(
        ExpressionEvaluator.evaluate([_i(1), _i(2), _i(3)], [Operator.add]),
        isNull,
      );
      expect(
        ExpressionEvaluator.evaluate([], []),
        isNull,
      );
    });

    test('非法括号范围返回 null', () {
      expect(
        ExpressionEvaluator.evaluate(
          [_i(1), _i(2)],
          [Operator.add],
          bracketRange: (0, 5),
        ),
        isNull,
      );
      expect(
        ExpressionEvaluator.evaluate(
          [_i(1), _i(2)],
          [Operator.add],
          bracketRange: (-1, 1),
        ),
        isNull,
      );
    });
  });

  group('ExpressionEvaluator.evaluateWithSteps', () {
    test('括号题步骤序列（design 示例）', () {
      final trace = ExpressionEvaluator.evaluateWithSteps(
        [_i(71), _i(10), _i(7), _i(4)],
        [Operator.add, Operator.multiply, Operator.multiply],
        bracketRange: (0, 2),
      )!;
      expect(trace.steps.length, 3);
      expect(trace.steps[0].expression, '(71 + 10)');
      expect(trace.steps[0].value.asInteger, 81);
      expect(trace.steps[1].expression, '81 × 7');
      expect(trace.steps[1].value.asInteger, 567);
      expect(trace.steps[2].expression, '567 × 4');
      expect(trace.steps[2].value.asInteger, 2268);
      expect(trace.value.asInteger, 2268);
      expect(trace.steps.last.value, equals(trace.value));
    });

    test('chain 步骤序列：先乘除后加减', () {
      final trace = ExpressionEvaluator.evaluateWithSteps(
        [_i(2), _i(3), _i(4)],
        [Operator.add, Operator.multiply],
      )!;
      expect(trace.steps.length, 2);
      expect(trace.steps[0].expression, '3 × 4');
      expect(trace.steps[0].value.asInteger, 12);
      expect(trace.steps[1].expression, '2 + 12');
      expect(trace.steps[1].value.asInteger, 14);
    });

    test('chain 同级从左到右步骤序列', () {
      final trace = ExpressionEvaluator.evaluateWithSteps(
        [_i(3), _i(5), _i(2)],
        [Operator.add, Operator.subtract],
      )!;
      expect(trace.steps.length, 2);
      expect(trace.steps[0].expression, '3 + 5');
      expect(trace.steps[1].expression, '8 - 2');
      expect(trace.steps.last.value.asInteger, 6);
    });

    test('除零轨迹返回 null', () {
      final trace = ExpressionEvaluator.evaluateWithSteps(
        [_i(5), _i(0)],
        [Operator.divide],
      );
      expect(trace, isNull);
    });

    test('分数中间值以假分数形态呈现', () {
      final trace = ExpressionEvaluator.evaluateWithSteps(
        [_i(70), _i(14), _i(2)],
        [Operator.divide, Operator.divide],
        bracketRange: (0, 2),
      )!;
      expect(trace.steps.last.value, equals(const Fraction(5, 2)));
      // 步骤表达式引用上一步精确值，最终值保持假分数
      expect(trace.steps[1].expression, '5 ÷ 2');
      expect(trace.value.toImproperString(), '5/2');
    });
  });
}
