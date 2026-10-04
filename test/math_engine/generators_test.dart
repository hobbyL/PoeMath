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
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/number_value.dart';

int _gcd(int a, int b) {
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a;
}

// ============ 测试专用独立参考求值辅助（与生产实现分开编写） ============

/// 按先乘除（从左到右）、后加减（从左到右）折叠，返回 null 表示除零。
int? _foldIntByPriority(List<int> vals, List<Operator> ops) {
  final v = List<int>.from(vals);
  final o = List<Operator>.from(ops);
  var i = 0;
  while (i < o.length) {
    if (o[i] == Operator.multiply || o[i] == Operator.divide) {
      if (o[i] == Operator.divide && v[i + 1] == 0) return null;
      v[i] = _applyInt(v[i], v[i + 1], o[i]);
      v.removeAt(i + 1);
      o.removeAt(i);
    } else {
      i++;
    }
  }
  var result = v[0];
  for (var k = 0; k < o.length; k++) {
    result = _applyInt(result, v[k + 1], o[k]);
  }
  return result;
}

/// 整数折叠单步（除法调用方保证整除）。
int _applyInt(int a, int b, Operator op) => switch (op) {
      Operator.add => a + b,
      Operator.subtract => a - b,
      Operator.multiply => a * b,
      Operator.divide => a ~/ b,
    };

/// 对整数序列按优先级折叠并断言每步除法整除。
void _checkIntSteps(List<int> vals, List<Operator> ops, String label) {
  final v = List<int>.from(vals);
  final o = List<Operator>.from(ops);
  var i = 0;
  while (i < o.length) {
    if (o[i] == Operator.multiply || o[i] == Operator.divide) {
      if (o[i] == Operator.divide) {
        expect(v[i] % v[i + 1], 0,
            reason: '$label $v 除法步骤 ${v[i]} ÷ ${v[i + 1]} 不整除',);
      }
      v[i] = _applyInt(v[i], v[i + 1], o[i]);
      v.removeAt(i + 1);
      o.removeAt(i);
    } else {
      i++;
    }
  }
}

/// Fraction 版优先级折叠（供独立参考求值器使用）。
int? _foldByPriority(
  List<Fraction> vals,
  List<Operator> ops,
  Fraction? Function(Fraction, Fraction, Operator) apply,
) {
  final v = List<Fraction>.from(vals);
  final o = List<Operator>.from(ops);
  var i = 0;
  while (i < o.length) {
    if (o[i] == Operator.multiply || o[i] == Operator.divide) {
      final r = apply(v[i], v[i + 1], o[i]);
      if (r == null) return null;
      v[i] = r;
      v.removeAt(i + 1);
      o.removeAt(i);
    } else {
      i++;
    }
  }
  var acc = v[0];
  for (var k = 0; k < o.length; k++) {
    final r = apply(acc, v[k + 1], o[k]);
    if (r == null) return null;
    acc = r;
  }
  return acc.isInteger ? acc.asInteger : null;
}

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

    test('500 seed 显示语义求值 == result（独立参考求值器互证）', () {
      // 独立编写的参考实现：先括号内从左到右、括号外先乘除后加减，
      // 与生产 ExpressionEvaluator 分开编写，互相验证。
      int? refEvaluate(MathProblem p) {
        final br = p.bracketRange;
        final vals = p.operands.map((o) => o.asFraction).toList();
        final ops = p.operators.toList();
        Fraction? apply(Fraction a, Fraction b, Operator op) => switch (op) {
              Operator.add => a + b,
              Operator.subtract => a - b,
              Operator.multiply => a * b,
              Operator.divide =>
                b.numerator == 0 ? null : Fraction(a.numerator * b.denominator,
                    a.denominator * b.numerator,),
            };
        if (br != null) {
          var inner = vals[br.$1];
          for (var k = br.$1; k < br.$2 - 1; k++) {
            final r = apply(inner, vals[k + 1], ops[k]);
            if (r == null) return null;
            inner = r;
          }
          final folded = [
            ...vals.sublist(0, br.$1),
            inner,
            ...vals.sublist(br.$2),
          ];
          final restOps = [
            ...ops.sublist(0, br.$1),
            ...ops.sublist(br.$2 - 1),
          ];
          return _foldByPriority(folded, restOps, apply);
        }
        return _foldByPriority(vals, ops, apply);
      }
      var bracketCount = 0;
      for (var seed = 0; seed < 500; seed++) {
        final g = MixedOperationGen(GradePresets.grade3b, random: Random(seed));
        final p = g.generate();
        if (p.mode == ProblemMode.withBrackets) bracketCount++;
        final expected = refEvaluate(p);
        expect(expected, isNotNull, reason: 'seed=$seed ${p.problemText}');
        expect(
          expected,
          p.result.asInteger,
          reason: 'seed=$seed ${p.problemText} 显示语义=$expected '
              '引擎判分=${p.answerText}',
        );
      }
      // 3b 允许括号，500 seed 中应出现过带括号题（降级后仍应保留相当占比）
      expect(bracketCount, greaterThan(50));
    });

    test('withBrackets 题逐步除法全整除', () {
      for (var seed = 0; seed < 300; seed++) {
        final g = MixedOperationGen(GradePresets.grade3b, random: Random(seed));
        final p = g.generate();
        if (p.mode != ProblemMode.withBrackets) continue;
        final br = p.bracketRange!;
        final vals = p.operands.map((o) => o.asInteger).toList();
        final ops = p.operators;
        // 括号内逐步
        var inner = vals[br.$1];
        for (var k = br.$1; k < br.$2 - 1; k++) {
          if (ops[k] == Operator.divide) {
            expect(inner % vals[k + 1], 0,
                reason: 'seed=$seed 括号内 $inner ÷ ${vals[k + 1]} 不整除',);
          }
          inner = _applyInt(inner, vals[k + 1], ops[k]);
        }
        // 括号外：先乘除后加减逐步
        final folded = <int>[inner, ...vals.sublist(br.$2)];
        final restOps = [...ops.sublist(0, br.$1), ...ops.sublist(br.$2 - 1)];
        _checkIntSteps(folded, restOps, 'seed=$seed 括号外');
      }
    });

    test('4a 也满足显示语义一致（Bug A 高发学期）', () {
      for (var seed = 0; seed < 200; seed++) {
        final g = MixedOperationGen(GradePresets.grade4a, random: Random(seed));
        final p = g.generate();
        if (p.mode != ProblemMode.withBrackets) continue;
        // 直接用显示语义人工复算
        final br = p.bracketRange!;
        final vals = p.operands.map((o) => o.asInteger).toList();
        final ops = p.operators;
        var inner = vals[br.$1];
        for (var k = br.$1; k < br.$2 - 1; k++) {
          inner = _applyInt(inner, vals[k + 1], ops[k]);
        }
        final folded = <int>[inner, ...vals.sublist(br.$2)];
        final restOps = [...ops.sublist(0, br.$1), ...ops.sublist(br.$2 - 1)];
        final expected = _foldIntByPriority(folded, restOps);
        expect(expected, p.result.asInteger,
            reason: 'seed=$seed ${p.problemText}',);
      }
    });

    test('非法括号组合确定性降级为 chain', () {
      // 3b 采样中所有 withBrackets 题必须满足括号语义整数性；
      // 一旦括号语义出现非整数/超范围，该题必然以 chain 形态产出。
      for (var seed = 0; seed < 500; seed++) {
        final g = MixedOperationGen(GradePresets.grade3b, random: Random(seed));
        final p = g.generate();
        if (p.mode != ProblemMode.withBrackets) continue;
        // 括号语义合法性的必要条件：折叠全程整数且结果在范围内
        final br = p.bracketRange!;
        final vals = p.operands.map((o) => o.asInteger).toList();
        final ops = p.operators;
        var inner = vals[br.$1];
        var allInt = true;
        for (var k = br.$1; k < br.$2 - 1; k++) {
          if (ops[k] == Operator.divide && inner % vals[k + 1] != 0) {
            allInt = false;
            break;
          }
          inner = _applyInt(inner, vals[k + 1], ops[k]);
        }
        expect(allInt, isTrue, reason: 'seed=$seed ${p.problemText}');
        expect(p.result.asInteger, inInclusiveRange(0, GradePresets.grade3b.maxResult));
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

    test('题面操作数为分数形态（R5/AC5，不再显示小数）', () {
      for (var i = 0; i < 40; i++) {
        final p = gen.generate();
        expect(p.problemText, contains('/'));
        expect(p.problemText.contains(RegExp(r'\d\.\d')), isFalse,
            reason: '题面混入小数形态: ${p.problemText}',);
        expect(p.problemText.endsWith('= ?'), isTrue);
      }
    });

    test('题面与 answerText 判分一致', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        final j = MathEngine.judge(p, p.answerText);
        expect(j.isCorrect, isTrue,
            reason: '${p.problemText} ans=${p.answerText}',);
      }
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

    test('题面为百分数形态（R3/AC3）', () {
      for (var i = 0; i < 30; i++) {
        final p = gen.generate();
        expect(p.problemText, contains('%'));
        expect(
          p.problemText,
          matches(RegExp(r'^\d+ × \d+% = \?$')),
          reason: '形态不符: ${p.problemText}',
        );
      }
    });

    test('answerText 为整数且判分正确', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        expect(p.answerText, matches(RegExp(r'^\d+$')));
        final j = MathEngine.judge(p, p.answerText);
        expect(j.isCorrect, isTrue, reason: p.problemText);
        // 错误答案给出诊断
        final wrong = MathEngine.judge(p, (p.result.asInteger + 1).toString());
        expect(wrong.isCorrect, isFalse);
      }
    });

    test('内部结构数学正确：base × percent/100 = result', () {
      for (var i = 0; i < 30; i++) {
        final p = gen.generate();
        final base = p.operands[0].asInteger;
        final ratio = p.operands[1].asFraction;
        expect(Fraction(base) * ratio, equals(p.result.asFraction));
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

    test('题面为比例形态且 a:b 最简（R4/AC4）', () {
      for (var i = 0; i < 30; i++) {
        final p = gen.generate();
        expect(p.problemText, contains(' : '));
        final match =
            RegExp(r'^(\d+) : (\d+) = (\d+) : \?$').firstMatch(p.problemText);
        expect(match, isNotNull, reason: '形态不符: ${p.problemText}');
        final a = int.parse(match!.group(1)!);
        final b = int.parse(match.group(2)!);
        final c = int.parse(match.group(3)!);
        expect(_gcd(a, b), 1, reason: 'a:b 未约最简: ${p.problemText}');
        // 比例语义：a : b = c : d → d = b × c / a
        expect(b * c % a, 0);
        expect(b * c ~/ a, p.result.asInteger,
            reason: '${p.problemText} 答案应为 ${b * c ~/ a}',);
      }
    });

    test('判分正确', () {
      for (var i = 0; i < 20; i++) {
        final p = gen.generate();
        final j = MathEngine.judge(p, p.answerText);
        expect(j.isCorrect, isTrue, reason: p.problemText);
        final wrong =
            MathEngine.judge(p, (p.result.asInteger + 1).toString());
        expect(wrong.isCorrect, isFalse);
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
