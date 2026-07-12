// test/math_engine/grade_presets_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';

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
}
