// lib/math_engine/presets/grade_presets.dart
//
// 1-6 年级 12 学期出题预设（人教版对齐）。

import '../models/grade_config.dart';
import '../models/math_problem.dart';

/// 年级预设配置表。
class GradePresets {
  const GradePresets._();

  static const _basicModes = {ProblemMode.findResult, ProblemMode.findMissing};
  static const _extendedModes = {
    ProblemMode.findResult,
    ProblemMode.findMissing,
    ProblemMode.compare,
    ProblemMode.vertical,
  };
  static const _fullModes = {
    ProblemMode.findResult,
    ProblemMode.findMissing,
    ProblemMode.compare,
    ProblemMode.vertical,
    ProblemMode.chain,
  };

  /// 一年级上：10 以内加减法，无进退位。
  static const grade1a = GradeConfig(
    grade: 1,
    semester: '上',
    label: '一年级上',
    allowedOperators: {Operator.add, Operator.subtract},
    allowedModes: _basicModes,
    minOperand: 0,
    maxOperand: 10,
    maxResult: 10,
    allowCarry: false,
    allowBorrow: false,
  );

  /// 一年级下：20 以内加减法，可进退位。
  static const grade1b = GradeConfig(
    grade: 1,
    semester: '下',
    label: '一年级下',
    allowedOperators: {Operator.add, Operator.subtract},
    allowedModes: _basicModes,
    minOperand: 0,
    maxOperand: 20,
    maxResult: 20,
    allowCarry: true,
    allowBorrow: true,
  );

  /// 二年级上：100 以内加减法、乘法口诀（1-9 × 1-9）。
  static const grade2a = GradeConfig(
    grade: 2,
    semester: '上',
    label: '二年级上',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
    },
    allowedModes: _extendedModes,
    minOperand: 0,
    maxOperand: 100,
    maxResult: 100,
    allowCarry: true,
    allowBorrow: true,
    maxMultiplier: 9,
  );

  /// 二年级下：万以内加减、表内除法、有余数除法。
  static const grade2b = GradeConfig(
    grade: 2,
    semester: '下',
    label: '二年级下',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: _extendedModes,
    minOperand: 0,
    maxOperand: 10000,
    maxResult: 10000,
    allowCarry: true,
    allowBorrow: true,
    allowRemainder: true,
    maxMultiplier: 9,
    maxDividend: 81,
  );

  /// 三年级上：多位数乘一位数、万以内加减。
  static const grade3a = GradeConfig(
    grade: 3,
    semester: '上',
    label: '三年级上',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: _fullModes,
    minOperand: 0,
    maxOperand: 10000,
    maxResult: 10000,
    allowCarry: true,
    allowBorrow: true,
    maxOperands: 2,
    maxMultiplier: 999,
    maxDividend: 999,
  );

  /// 三年级下：两位数乘两位数、三步混合运算。
  static const grade3b = GradeConfig(
    grade: 3,
    semester: '下',
    label: '三年级下',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: {..._fullModes, ProblemMode.withBrackets},
    minOperand: 0,
    maxOperand: 10000,
    maxResult: 100000,
    allowCarry: true,
    allowBorrow: true,
    allowBrackets: true,
    maxOperands: 3,
    maxMultiplier: 99,
    maxDividend: 9999,
  );

  /// 四年级上：大数运算、三步混合运算、运算律。
  static const grade4a = GradeConfig(
    grade: 4,
    semester: '上',
    label: '四年级上',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: {..._fullModes, ProblemMode.withBrackets},
    minOperand: 0,
    maxOperand: 1000000,
    maxResult: 1000000,
    allowCarry: true,
    allowBorrow: true,
    allowBrackets: true,
    maxOperands: 3,
    maxMultiplier: 999,
    maxDividend: 99999,
  );

  /// 四年级下：小数加减法。
  static const grade4b = GradeConfig(
    grade: 4,
    semester: '下',
    label: '四年级下',
    allowedOperators: {Operator.add, Operator.subtract},
    allowedModes: _extendedModes,
    minOperand: 0,
    maxOperand: 1000,
    maxResult: 1000,
    allowCarry: true,
    allowBorrow: true,
    allowDecimal: true,
    maxDecimalPlaces: 2,
  );

  /// 五年级上：小数乘除法。
  static const grade5a = GradeConfig(
    grade: 5,
    semester: '上',
    label: '五年级上',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: _extendedModes,
    minOperand: 0,
    maxOperand: 1000,
    maxResult: 100000,
    allowCarry: true,
    allowBorrow: true,
    allowDecimal: true,
    maxDecimalPlaces: 3,
    maxMultiplier: 100,
    maxDividend: 10000,
  );

  /// 五年级下：分数加减法。
  static const grade5b = GradeConfig(
    grade: 5,
    semester: '下',
    label: '五年级下',
    allowedOperators: {Operator.add, Operator.subtract},
    allowedModes: _basicModes,
    minOperand: 0,
    maxOperand: 100,
    maxResult: 100,
    allowCarry: true,
    allowBorrow: true,
    allowFraction: true,
    maxDenominator: 12,
  );

  /// 六年级上：分数乘除法、百分数。
  static const grade6a = GradeConfig(
    grade: 6,
    semester: '上',
    label: '六年级上',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: _extendedModes,
    minOperand: 0,
    maxOperand: 100,
    maxResult: 1000,
    allowCarry: true,
    allowBorrow: true,
    allowFraction: true,
    maxDenominator: 20,
    allowDecimal: true,
    maxDecimalPlaces: 2,
  );

  /// 六年级下：比例、正负数。
  static const grade6b = GradeConfig(
    grade: 6,
    semester: '下',
    label: '六年级下',
    allowedOperators: {
      Operator.add,
      Operator.subtract,
      Operator.multiply,
      Operator.divide,
    },
    allowedModes: _extendedModes,
    minOperand: -100,
    maxOperand: 100,
    maxResult: 1000,
    allowCarry: true,
    allowBorrow: true,
    allowNegative: true,
    allowFraction: true,
    maxDenominator: 20,
    allowDecimal: true,
    maxDecimalPlaces: 2,
  );

  /// 所有 12 学期预设（有序列表）。
  static const List<GradeConfig> all = [
    grade1a, grade1b,
    grade2a, grade2b,
    grade3a, grade3b,
    grade4a, grade4b,
    grade5a, grade5b,
    grade6a, grade6b,
  ];

  /// 按年级和学期查找配置。
  static GradeConfig get(int grade, String semester) {
    return all.firstWhere(
      (c) => c.grade == grade && c.semester == semester,
    );
  }
}
