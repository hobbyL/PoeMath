// test/math_engine/grade_presets_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/validators/constraint_checker.dart';

void main() {
  group('GradePresets', () {
    test('12 个预设全部存在', () {
      expect(GradePresets.all.length, 12);
    });

    test('get 方法正确查找', () {
      final config = GradePresets.get(1, '上');
      expect(config.grade, 1);
      expect(config.semester, '上');
      expect(config.label, '一年级上');
    });

    test('get 方法 - 所有年级', () {
      for (var grade = 1; grade <= 6; grade++) {
        for (final sem in ['上', '下']) {
          final config = GradePresets.get(grade, sem);
          expect(config.grade, grade);
          expect(config.semester, sem);
        }
      }
    });

    test('一年级上 - 10以内，无进退位', () {
      final c = GradePresets.grade1a;
      expect(c.maxOperand, 10);
      expect(c.maxResult, 10);
      expect(c.allowCarry, isFalse);
      expect(c.allowBorrow, isFalse);
      expect(c.allowedOperators, {Operator.add, Operator.subtract});
    });

    test('一年级下 - 20以内，有进退位', () {
      final c = GradePresets.grade1b;
      expect(c.maxOperand, 20);
      expect(c.allowCarry, isTrue);
      expect(c.allowBorrow, isTrue);
    });

    test('二年级上 - 含乘法', () {
      final c = GradePresets.grade2a;
      expect(c.allowedOperators.contains(Operator.multiply), isTrue);
      expect(c.maxResult, 100);
    });

    test('二年级下 - 含除法和余数', () {
      final c = GradePresets.grade2b;
      expect(c.allowedOperators.contains(Operator.divide), isTrue);
      expect(c.allowRemainder, isTrue);
    });

    test('三年级下 - 含括号', () {
      final c = GradePresets.grade3b;
      expect(c.allowBrackets, isTrue);
      expect(c.maxOperands, 3);
    });

    test('四年级下 - 小数', () {
      final c = GradePresets.grade4b;
      expect(c.allowDecimal, isTrue);
      expect(c.maxDecimalPlaces, 2);
    });

    test('五年级下 - 分数', () {
      final c = GradePresets.grade5b;
      expect(c.allowFraction, isTrue);
      expect(c.maxDenominator, 12);
    });

    test('六年级下 - 负数', () {
      final c = GradePresets.grade6b;
      expect(c.allowNegative, isTrue);
      expect(c.minOperand, -100);
    });

    test('六年级上 - 乘除参数补齐（Bug B 修复）', () {
      final c = GradePresets.grade6a;
      expect(c.maxMultiplier, 99);
      expect(c.maxDividend, 999);
      expect(c.maxResult, 10000);
    });

    test('六年级下 - 乘除参数补齐（Bug B 修复）', () {
      final c = GradePresets.grade6b;
      expect(c.maxMultiplier, 99);
      expect(c.maxDividend, 9999);
      expect(c.maxResult, 10000);
    });

    test('5a/6a/6b allowedModes 含 chain（R8 模式白名单修复）', () {
      for (final c in [GradePresets.grade5a, GradePresets.grade6a, GradePresets.grade6b]) {
        expect(
          c.allowedModes.contains(ProblemMode.chain),
          isTrue,
          reason: '${c.label} 应允许 chain 模式',
        );
      }
    });

    test('每个预设的 maxResult 合理', () {
      for (final config in GradePresets.all) {
        expect(
          config.maxResult,
          greaterThan(0),
          reason: '${config.label} maxResult 应为正数',
        );
        expect(
          config.maxResult,
          greaterThanOrEqualTo(config.maxOperand),
          reason: '${config.label} maxResult 应 >= maxOperand',
        );
      }
    });
  });

  group('6a/6b 采样分布（AC2）', () {
    test('6a 3000 题乘除不退化且全部通过校验', () async {
      final config = GradePresets.grade6a;
      final multiplicandValues = <int>{};
      var mulTotal = 0;
      var divTotal = 0;
      var quotientOne = 0;
      for (var i = 0; i < 3000; i++) {
        final p = MathEngine.generate(
          grade: 6,
          semester: '上',
          random: Random(60000 + i),
        );
        expect(ConstraintChecker.check(p, config), isNull,
            reason: p.problemText,);
        if (p.operators.length == 1 && p.operators[0] == Operator.multiply) {
          // 排除百分数题（操作数含分数）
          if (p.operands.every((o) => o.isInteger)) {
            mulTotal++;
            multiplicandValues.add(p.operands[0].asInteger);
          }
        } else if (p.operators.length == 1 &&
            p.operators[0] == Operator.divide) {
          divTotal++;
          if (p.result.asInteger == 1) quotientOne++;
        }
      }
      expect(mulTotal, greaterThan(20), reason: '乘法题样本量过少');
      expect(multiplicandValues.length, greaterThanOrEqualTo(10),
          reason: '被乘数出现 $multiplicandValues，不足 10 个不同值',);
      expect(
        multiplicandValues.length == 1 && multiplicandValues.contains(10),
        isFalse,
        reason: '被乘数恒为 10（退化分布）',
      );
      if (divTotal > 20) {
        expect(quotientOne / divTotal, lessThan(0.10),
            reason: '商=1 占比 ${(quotientOne * 100 / divTotal).toStringAsFixed(1)}%',);
      }
    }, timeout: const Timeout(Duration(minutes: 3)),);

    test('6b 3000 题乘除不退化且全部通过校验', () async {
      final config = GradePresets.grade6b;
      final multiplicandValues = <int>{};
      var mulTotal = 0;
      var divTotal = 0;
      var quotientOne = 0;
      for (var i = 0; i < 3000; i++) {
        final p = MathEngine.generate(
          grade: 6,
          semester: '下',
          random: Random(66000 + i),
        );
        expect(ConstraintChecker.check(p, config), isNull,
            reason: p.problemText,);
        if (p.operators.length == 1 && p.operators[0] == Operator.multiply) {
          // 排除比例题（操作数含分数）
          if (p.operands.every((o) => o.isInteger)) {
            mulTotal++;
            multiplicandValues.add(p.operands[0].asInteger);
          }
        } else if (p.operators.length == 1 &&
            p.operators[0] == Operator.divide) {
          divTotal++;
          if (p.result.asInteger == 1) quotientOne++;
        }
      }
      expect(mulTotal, greaterThan(20), reason: '乘法题样本量过少');
      expect(multiplicandValues.length, greaterThanOrEqualTo(10),
          reason: '被乘数出现 $multiplicandValues，不足 10 个不同值',);
      expect(divTotal, greaterThan(20), reason: '除法题样本量过少');
      expect(quotientOne / divTotal, lessThan(0.10),
          reason: '商=1 占比 ${(quotientOne * 100 / divTotal).toStringAsFixed(1)}%',);
    }, timeout: const Timeout(Duration(minutes: 3)),);
  });
}
