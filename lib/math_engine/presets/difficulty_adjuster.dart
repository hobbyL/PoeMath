// lib/math_engine/presets/difficulty_adjuster.dart
//
// 难度调整器：在不跨越年级边界的前提下，缩放 GradeConfig 参数。

import '../models/difficulty_level.dart';
import '../models/grade_config.dart';
import '../models/math_problem.dart';

/// 根据难度级别调整 [GradeConfig]，产出约束更松或更紧的配置。
///
/// 关键约束：所有数值上限 ≤ 原始 config，确保不跨越年级边界。
class DifficultyAdjuster {
  const DifficultyAdjuster._();

  /// 返回按 [level] 调整后的 [GradeConfig]。
  static GradeConfig adjust(GradeConfig base, DifficultyLevel level) {
    return switch (level) {
      DifficultyLevel.easy => _easy(base),
      DifficultyLevel.medium => base,
      DifficultyLevel.hard => _hard(base),
    };
  }

  /// 简单：缩小数值范围，禁止进退位，仅求结果模式。
  static GradeConfig _easy(GradeConfig base) {
    // 操作数和结果范围缩减到约 50%，但最小为 5
    final maxOp = (base.maxOperand * 0.5).ceil().clamp(5, base.maxOperand);
    final maxRes = (base.maxResult * 0.5).ceil().clamp(5, base.maxResult);

    // 乘除数范围也缩减
    final maxMul = (base.maxMultiplier * 0.5).ceil().clamp(2, base.maxMultiplier);
    final maxDiv = (base.maxDividend * 0.5).ceil().clamp(9, base.maxDividend);

    // 只保留基础模式
    final modes = <ProblemMode>{ProblemMode.findResult};

    // 运算符只保留加减（低年级），若年级 ≥ 3 则保留乘除
    Set<Operator> ops;
    if (base.grade <= 2) {
      ops = base.allowedOperators
          .intersection({Operator.add, Operator.subtract});
      if (ops.isEmpty) ops = {Operator.add};
    } else {
      ops = base.allowedOperators;
    }

    return GradeConfig(
      grade: base.grade,
      semester: base.semester,
      label: base.label,
      allowedOperators: ops,
      allowedModes: modes,
      minOperand: base.minOperand,
      maxOperand: maxOp,
      maxResult: maxRes,
      allowCarry: false,
      allowBorrow: false,
      allowRemainder: false,
      allowBrackets: false,
      maxOperands: 2,
      allowDecimal: base.allowDecimal,
      maxDecimalPlaces: base.allowDecimal ? 1 : 0,
      allowFraction: base.allowFraction,
      maxDenominator: base.allowFraction
          ? (base.maxDenominator * 0.5).ceil().clamp(2, base.maxDenominator)
          : 1,
      allowNegative: false,
      maxMultiplier: maxMul,
      maxDividend: maxDiv,
    );
  }

  /// 困难：保持年级数值范围，增加模式和复杂度。
  static GradeConfig _hard(GradeConfig base) {
    // 开放所有该年级支持的模式
    final modes = Set<ProblemMode>.from(base.allowedModes);
    if (base.grade >= 2) {
      modes.addAll({ProblemMode.findMissing, ProblemMode.compare});
    }

    // 高年级允许多一步运算
    final maxOps = base.grade >= 3
        ? (base.maxOperands + 1).clamp(2, 4)
        : base.maxOperands;

    return GradeConfig(
      grade: base.grade,
      semester: base.semester,
      label: base.label,
      allowedOperators: base.allowedOperators,
      allowedModes: modes,
      minOperand: base.minOperand,
      maxOperand: base.maxOperand,
      maxResult: base.maxResult,
      allowCarry: true,
      allowBorrow: true,
      allowRemainder: base.allowRemainder,
      allowBrackets: base.allowBrackets || base.grade >= 3,
      maxOperands: maxOps,
      allowDecimal: base.allowDecimal,
      maxDecimalPlaces: base.maxDecimalPlaces,
      allowFraction: base.allowFraction,
      maxDenominator: base.maxDenominator,
      allowNegative: base.allowNegative,
      maxMultiplier: base.maxMultiplier,
      maxDividend: base.maxDividend,
    );
  }
}
