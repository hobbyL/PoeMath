// test/math_engine/generators_test.dart
//
// 12 个生成器的单元测试。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/generators/addition_subtraction_gen.dart';
import 'package:poemath/math_engine/generators/multiplication_table_gen.dart';
import 'package:poemath/math_engine/generators/remainder_division_gen.dart';
import 'package:poemath/math_engine/generators/multi_digit_mul_div_gen.dart';
import 'package:poemath/math_engine/generators/mixed_operation_gen.dart';
import 'package:poemath/math_engine/generators/law_of_operation_gen.dart';
import 'package:poemath/math_engine/generators/decimal_gen.dart';
import 'package:poemath/math_engine/generators/fraction_gen.dart';
import 'package:poemath/math_engine/generators/percentage_gen.dart';
import 'package:poemath/math_engine/generators/simple_equation_gen.dart';
import 'package:poemath/math_engine/generators/ratio_proportion_gen.dart';
import 'package:poemath/math_engine/generators/negative_number_gen.dart';

void main() {
  group('AdditionSubtractionGen', () {
    final gen1a = AdditionSubtractionGen(GradePresets.grade1a, random: Random(1));
    final gen1b = AdditionSubtractionGen(GradePresets.grade1b, random: Random(2));

    test('生成 20 道题，全部有效', () {
      for (var i = 0; i < 20; i++) {
        final p = gen1a.generate();
        expect(p.operands.length, 2);
        expect(p.operators.length, 1);
        expect(p.grade, 1);
      }
    });

    test('1 年级上 结果 ≤ 10', () {
      for (var i = 0; i < 20; i++) {
        final p = gen1a.generate();
        expect(p.result.asInteger, lessThanOrEqualTo(10));
        expect(p.result.asInteger, greaterThanOrEqualTo(0));
      }
    });

    test('1 年级上 无进位加法', () {
      final gen = AdditionSubtractionGen(GradePresets.grade1a, random: Random(10));
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        if (p.operators[0] == Operator.add) {
          final a = p.operands[0].asInteger;
          final b = p.operands[1].asInteger;
          // 个位不进位
          expect((a % 10) + (b % 10), lessThan(10));
        }
      }
    });

    test('1 年级下 允许进位', () {
      var hasCarry = false;
      for (var i = 0; i < 50; i++) {
        final p = gen1b.generate();
        if (p.operators[0] == Operator.add) {
          final a = p.operands[0].asInteger;
          final b = p.operands[1].asInteger;
          if ((a % 10) + (b % 10) >= 10) hasCarry = true;
        }
      }
      // 50 次中应该至少出现一次进位
      expect(hasCarry, isTrue);
    });

    test('运算符只有加或减', () {
      for (var i = 0; i < 20; i++) {
        final p = gen1a.generate();
        expect(
          p.operators[0],
          isIn([Operator.add, Operator.subtract]),
        );
      }
    });

    test('减法结果非负', () {
      for (var i = 0; i < 20; i++) {
        final p = gen1a.generate();
        expect(p.result.asInteger, greaterThanOrEqualTo(0));
      }
    });
  });

  group('MultiplicationTableGen', () {
    final gen = MultiplicationTableGen(GradePresets.grade2a, random: Random(3));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.operands.length, 2);
        expect(p.grade, 2);
      }
    });

    test('乘法口诀范围 1-9', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        if (p.operators[0] == Operator.multiply) {
          expect(p.operands[0].asInteger, inInclusiveRange(1, 9));
          expect(p.operands[1].asInteger, inInclusiveRange(1, 9));
        }
      }
    });

    test('乘法结果正确', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        if (p.operators[0] == Operator.multiply &&
            p.mode == ProblemMode.findResult) {
          final a = p.operands[0].asInteger;
          final b = p.operands[1].asInteger;
          expect(p.result.asInteger, a * b);
        }
      }
    });

    test('除法结果整除', () {
      final divGen = MultiplicationTableGen(GradePresets.grade2b, random: Random(4));
      for (var i = 0; i < 30; i++) {
        final p = divGen.generate();
        if (p.operators[0] == Operator.divide) {
          final a = p.operands[0].asInteger;
          final b = p.operands[1].asInteger;
          expect(a % b, 0, reason: '$a ÷ $b 应整除');
        }
      }
    });
  });

  group('RemainderDivisionGen', () {
    final gen = RemainderDivisionGen(GradePresets.grade2b, random: Random(5));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.resultForm, ResultForm.withRemainder);
        expect(p.remainder, isNotNull);
      }
    });

    test('余数 < 除数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        final divisor = p.operands[1].asInteger;
        expect(p.remainder!, lessThan(divisor));
        expect(p.remainder!, greaterThan(0));
      }
    });

    test('验算：除数×商+余数=被除数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        final dividend = p.operands[0].asInteger;
        final divisor = p.operands[1].asInteger;
        final quotient = p.result.asInteger;
        expect(
          divisor * quotient + p.remainder!,
          dividend,
          reason: '$divisor × $quotient + ${p.remainder} 应 = $dividend',
        );
      }
    });

    test('除数范围 2-9', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.operands[1].asInteger, inInclusiveRange(2, 9));
      }
    });
  });

  group('MultiDigitMulDivGen', () {
    final gen3a = MultiDigitMulDivGen(GradePresets.grade3a, random: Random(6));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen3a.generate();
        expect(p.operands.length, 2);
        expect(p.grade, 3);
      }
    });

    test('3 年级上 多位数×一位数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen3a.generate();
        if (p.operators[0] == Operator.multiply) {
          final a = p.operands[0].asInteger;
          final b = p.operands[1].asInteger;
          expect(a, greaterThanOrEqualTo(10));
          expect(b, inInclusiveRange(2, 9));
        }
      }
    });

    test('结果不超范围', () {
      for (var i = 0; i < 20; i++) {
        final p = gen3a.generate();
        expect(
          p.result.asInteger,
          lessThanOrEqualTo(GradePresets.grade3a.maxResult),
        );
      }
    });

    test('除法整除', () {
      for (var i = 0; i < 20; i++) {
        final p = gen3a.generate();
        if (p.operators[0] == Operator.divide) {
          final a = p.operands[0].asInteger;
          final b = p.operands[1].asInteger;
          expect(a % b, 0);
        }
      }
    });
  });

  group('MixedOperationGen', () {
    final gen = MixedOperationGen(GradePresets.grade3b, random: Random(7));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.operands.length, greaterThanOrEqualTo(2));
        expect(p.operators.length, greaterThanOrEqualTo(2));
      }
    });

    test('结果非负', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.result.asInteger, greaterThanOrEqualTo(0));
      }
    });

    test('操作数个数 = 运算符个数 + 1', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.operands.length, p.operators.length + 1);
      }
    });
  });

  group('LawOfOperationGen', () {
    final gen = LawOfOperationGen(GradePresets.grade4a, random: Random(8));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.operands.length, greaterThanOrEqualTo(2));
        expect(p.grade, 4);
      }
    });

    test('结果不超范围', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(
          p.result.asInteger.abs(),
          lessThanOrEqualTo(GradePresets.grade4a.maxResult),
        );
      }
    });
  });

  group('DecimalGen', () {
    final gen = DecimalGen(GradePresets.grade4b, random: Random(9));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.resultForm, ResultForm.decimal);
      }
    });

    test('结果为小数格式', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.resultForm, ResultForm.decimal);
      }
    });

    test('五年级 含乘除', () {
      final gen5 = DecimalGen(GradePresets.grade5a, random: Random(10));
      var hasMulDiv = false;
      for (var i = 0; i < 30; i++) {
        final p = gen5.generate();
        if (p.operators[0] == Operator.multiply ||
            p.operators[0] == Operator.divide) {
          hasMulDiv = true;
        }
      }
      expect(hasMulDiv, isTrue);
    });
  });

  group('FractionGen', () {
    final gen = FractionGen(GradePresets.grade5b, random: Random(11));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.resultForm, ResultForm.fraction);
      }
    });

    test('分母在范围内', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        for (final op in p.operands) {
          final den = op.asFraction.denominator;
          expect(den, greaterThanOrEqualTo(1));
        }
      }
    });

    test('六年级含乘除', () {
      final gen6 = FractionGen(GradePresets.grade6a, random: Random(12));
      var hasMulDiv = false;
      for (var i = 0; i < 30; i++) {
        final p = gen6.generate();
        if (p.operators[0] == Operator.multiply ||
            p.operators[0] == Operator.divide) {
          hasMulDiv = true;
        }
      }
      expect(hasMulDiv, isTrue);
    });
  });

  group('PercentageGen', () {
    final gen = PercentageGen(GradePresets.grade6a, random: Random(13));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.grade, 6);
      }
    });

    test('结果为整数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.result.isInteger, isTrue);
      }
    });
  });

  group('SimpleEquationGen', () {
    final gen = SimpleEquationGen(GradePresets.grade5b, random: Random(14));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.mode, ProblemMode.findMissing);
        expect(p.missingIndex, isNotNull);
      }
    });

    test('缺失索引有效', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.missingIndex, inInclusiveRange(0, 1));
      }
    });

    test('答案为缺失的操作数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        final answer = p.result;
        final missing = p.operands[p.missingIndex!];
        expect(answer.asInteger, missing.asInteger);
      }
    });
  });

  group('RatioProportionGen', () {
    final gen = RatioProportionGen(GradePresets.grade6b, random: Random(15));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.grade, 6);
        expect(p.result.isInteger, isTrue);
      }
    });

    test('结果为正整数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.result.asInteger, greaterThan(0));
      }
    });
  });

  group('NegativeNumberGen', () {
    final gen = NegativeNumberGen(GradePresets.grade6b, random: Random(16));

    test('生成 20 道题', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.grade, 6);
      }
    });

    test('至少一个负数操作数', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        final hasNeg = p.operands.any((op) => op.isNegative);
        expect(hasNeg, isTrue);
      }
    });

    test('结果在合理范围', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.result.asInteger.abs(), lessThanOrEqualTo(100));
      }
    });

    test('只有加减运算', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(
          p.operators[0],
          isIn([Operator.add, Operator.subtract]),
        );
      }
    });
  });
}
