// lib/math_engine/models/grade_config.dart
//
// 年级出题配置：每个年级/学期的数值范围、允许运算和题型约束。

import 'math_problem.dart';

/// 年级出题配置。
class GradeConfig {
  /// 年级（1-6）。
  final int grade;

  /// 学期（'上' 或 '下'）。
  final String semester;

  /// 配置标签（如 '一年级上'）。
  final String label;

  /// 允许的运算符。
  final Set<Operator> allowedOperators;

  /// 允许的题目模式。
  final Set<ProblemMode> allowedModes;

  /// 操作数最小值。
  final int minOperand;

  /// 操作数最大值。
  final int maxOperand;

  /// 结果最大值。
  final int maxResult;

  /// 是否允许进位。
  final bool allowCarry;

  /// 是否允许退位。
  final bool allowBorrow;

  /// 是否允许余数。
  final bool allowRemainder;

  /// 是否允许括号。
  final bool allowBrackets;

  /// 最大操作数个数（连续运算时用）。
  final int maxOperands;

  /// 是否允许小数。
  final bool allowDecimal;

  /// 小数最大位数。
  final int maxDecimalPlaces;

  /// 是否允许分数。
  final bool allowFraction;

  /// 分数分母最大值。
  final int maxDenominator;

  /// 是否允许负数结果。
  final bool allowNegative;

  /// 乘法最大因数。
  final int maxMultiplier;

  /// 除法最大被除数。
  final int maxDividend;

  const GradeConfig({
    required this.grade,
    required this.semester,
    required this.label,
    required this.allowedOperators,
    required this.allowedModes,
    this.minOperand = 0,
    required this.maxOperand,
    required this.maxResult,
    this.allowCarry = false,
    this.allowBorrow = false,
    this.allowRemainder = false,
    this.allowBrackets = false,
    this.maxOperands = 2,
    this.allowDecimal = false,
    this.maxDecimalPlaces = 0,
    this.allowFraction = false,
    this.maxDenominator = 1,
    this.allowNegative = false,
    this.maxMultiplier = 9,
    this.maxDividend = 81,
  });
}
