// lib/math_engine/generators/base_generator.dart
//
// 题目生成器基类。

import 'dart:math';

import '../models/grade_config.dart';
import '../models/math_problem.dart';
import '../models/number_value.dart';

/// 题目生成器基类。所有年级的具体生成器继承此类。
abstract class BaseGenerator {
  final GradeConfig config;
  final Random _random;

  BaseGenerator(this.config, {Random? random})
      : _random = random ?? Random();

  /// 生成一道题目。子类必须实现。
  MathProblem generate();

  /// 生成一道指定模式的题目。
  MathProblem generateWithMode(ProblemMode mode) => generate();

  // ============ 工具方法 ============

  /// 在 [min, max] 范围内生成随机整数。
  int randomInt(int min, int max) {
    if (min >= max) return min;
    return min + _random.nextInt(max - min + 1);
  }

  /// 在 [min, max] 范围内生成随机小数（指定小数位数）。
  double randomDecimal(double min, double max, int decimalPlaces) {
    final factor = pow(10, decimalPlaces).toInt();
    final minInt = (min * factor).ceil();
    final maxInt = (max * factor).floor();
    if (minInt >= maxInt) return min;
    final value = minInt + _random.nextInt(maxInt - minInt + 1);
    return value / factor;
  }

  /// 从列表中随机选择一个元素。
  T randomChoice<T>(List<T> items) {
    return items[_random.nextInt(items.length)];
  }

  /// 从 Set 中随机选择一个元素。
  T randomChoiceFromSet<T>(Set<T> items) {
    return randomChoice(items.toList());
  }

  /// 生成 findMissing 模式题目。
  ///
  /// 注意：不透传 [MathProblem.displayText]（已知取舍）——模式转换后
  /// 题面形态已变（如出现 ? 占位），覆盖文本不再匹配，按通用形态渲染，
  /// 数学语义仍与内部结构一致。
  MathProblem toFindMissing(MathProblem problem) {
    if (problem.operands.length < 2) return problem;
    final missingIndex = _random.nextInt(problem.operands.length);
    final missingValue = problem.operands[missingIndex];
    return MathProblem(
      operands: problem.operands,
      operators: problem.operators,
      result: missingValue,
      mode: ProblemMode.findMissing,
      grade: problem.grade,
      difficulty: problem.difficulty,
      resultForm: problem.resultForm,
      missingIndex: missingIndex,
      expressionResult: problem.result, // 保留原始计算结果用于显示
    );
  }

  /// 生成 compare 模式题目。
  ///
  /// 比较基准取表达式值：findMissing 源题的 [MathProblem.result] 是缺失项
  /// 答案（x）而非表达式值，必须用 [MathProblem.expressionResult]；
  /// findResult 源题无 expressionResult，result 即表达式值。
  ///
  /// 非整数基准（分数/小数）只取非负 offset，避免五年级分数题产出
  /// 「5/6 ○ 负数」这类超纲负数比较；整数基准保持 [-3, 3] 全范围
  /// （六下负数比较是已学考点）。
  ///
  /// 目标值用 [NumberValue] 分数精确加法构造（5/6 + 3 = 23/6），
  /// 杜绝 asInteger 截断（5/6 截断为 0 会产出 5/6 = 0 的错题）。
  ///
  /// 注意：不透传 [MathProblem.displayText]（取舍同 toFindMissing），
  /// 转换后按通用形态渲染（如 80 × 0.3 ○ 24），数学仍正确。
  MathProblem toCompare(MathProblem problem) {
    final base = problem.expressionResult ?? problem.result;

    final isWhole = base.isInteger;
    final offset = isWhole ? randomInt(-3, 3) : randomInt(0, 3);

    // 精确构造：offset=0 时 target 即 base（任意 resultForm 精确相等）；
    // 否则用分数加法（如 5/6 + 3 = 23/6）。
    final target = offset == 0
        ? base
        : base + NumberValue.fromInt(offset);

    final CompareRelation relation = offset > 0
        ? CompareRelation.lessThan
        : offset < 0
            ? CompareRelation.greaterThan
            : CompareRelation.equal;

    return MathProblem(
      operands: problem.operands,
      operators: problem.operators,
      // compare 模式下 result 语义 = 左边表达式的值（约束检查 #2 与
      // StepSolver 均按此求解），findMissing 源题转换后必须换基准。
      result: base,
      mode: ProblemMode.compare,
      grade: problem.grade,
      difficulty: problem.difficulty,
      resultForm: problem.resultForm,
      compareRelation: relation,
      compareTarget: target,
    );
  }

  /// 生成竖式计算模式题目（仅适用于两操作数的加减乘法）。
  ///
  /// 注意：不透传 [MathProblem.displayText]（取舍同 toFindMissing）。
  MathProblem toVertical(MathProblem problem) {
    if (problem.operands.length != 2) return problem;
    final op = problem.operators.first;
    // 竖式只支持加减乘
    if (op == Operator.divide) return problem;
    // 负数操作数不适合竖式（"- -20" 视觉混乱），回退横式
    if (problem.operands.any((o) => o.isNegative)) return problem;
    return MathProblem(
      operands: problem.operands,
      operators: problem.operators,
      result: problem.result,
      mode: ProblemMode.vertical,
      grade: problem.grade,
      difficulty: problem.difficulty,
      resultForm: problem.resultForm,
    );
  }

  /// 评估难度分。
  int scoreDifficulty(List<NumberValue> operands, List<Operator> operators) {
    var score = 1;
    for (final op in operands) {
      final digits = op.asInteger.abs().toString().length;
      if (digits >= 4) {
        score += 2;
      } else if (digits >= 2) {
        score++;
      }
    }
    if (operators.contains(Operator.multiply) ||
        operators.contains(Operator.divide)) {
      score++;
    }
    if (operators.length > 1) score++;
    return score.clamp(1, 5);
  }
}
