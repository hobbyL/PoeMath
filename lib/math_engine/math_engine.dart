// lib/math_engine/math_engine.dart
//
// 口算引擎统一入口。
// 无 Flutter 依赖，纯 Dart 实现。

import 'dart:math';

import 'models/answer_judgement.dart';
import 'models/grade_config.dart';
import 'models/math_problem.dart';
import 'models/number_value.dart';
import 'generators/base_generator.dart';
import 'generators/addition_subtraction_gen.dart';
import 'generators/multiplication_table_gen.dart';
import 'generators/remainder_division_gen.dart';
import 'generators/multi_digit_mul_div_gen.dart';
import 'generators/mixed_operation_gen.dart';
import 'generators/law_of_operation_gen.dart';
import 'generators/decimal_gen.dart';
import 'generators/fraction_gen.dart';
import 'generators/percentage_gen.dart';
import 'generators/simple_equation_gen.dart';
import 'generators/ratio_proportion_gen.dart';
import 'generators/negative_number_gen.dart';
import 'diagnostics/mistake_rule.dart';
import 'step_solver/step_solver.dart';
import 'presets/grade_presets.dart';
import 'validators/constraint_checker.dart';

/// 口算引擎：生成 → 判定 → 诊断 → 解释。
class MathEngine {
  const MathEngine._();

  /// 生成一道题目。
  ///
  /// [grade] 年级（1-6），[semester] 学期（'上' 或 '下'）。
  /// [mode] 可选的题目模式，默认随机。
  /// [random] 可选的随机数生成器（用于测试）。
  static MathProblem generate({
    required int grade,
    required String semester,
    ProblemMode? mode,
    Random? random,
  }) {
    final config = GradePresets.get(grade, semester);
    final generator = _selectGenerator(config, random: random);

    // 约束检查，不通过则重新生成（最多 100 次）
    for (var i = 0; i < 100; i++) {
      final problem = generator.generate();
      final violation = ConstraintChecker.check(problem, config);
      if (violation == null) return problem;
    }

    // 兜底：返回最后一次生成的题目
    return generator.generate();
  }

  /// 批量生成题目。
  static List<MathProblem> generateBatch({
    required int grade,
    required String semester,
    int count = 10,
    ProblemMode? mode,
    Random? random,
  }) {
    return List.generate(
      count,
      (_) => generate(
        grade: grade,
        semester: semester,
        mode: mode,
        random: random,
      ),
    );
  }

  /// 判定用户答案。
  static AnswerJudgement judge(MathProblem problem, String userAnswer) {
    final steps = StepSolver.solve(problem);

    // 解析用户答案
    if (problem.mode == ProblemMode.compare) {
      final isCorrect = userAnswer.trim() == problem.answerText;
      return AnswerJudgement(
        isCorrect: isCorrect,
        diagnosis: isCorrect
            ? null
            : const MistakeDiagnosis(
                category: 'compare_error',
                template: '比较大小时要先算出左边的值，再和右边比较。',
              ),
        correctSteps: steps,
      );
    }

    if (problem.resultForm == ResultForm.withRemainder) {
      // 解析 "3…2" 格式
      final isCorrect = userAnswer.trim() == problem.answerText;
      return AnswerJudgement(
        isCorrect: isCorrect,
        diagnosis: isCorrect
            ? null
            : MistakeDiagnoser.diagnose(
                problem,
                _parseAnswer(userAnswer),
              ),
        correctSteps: steps,
      );
    }

    final userValue = _parseAnswer(userAnswer);
    final isCorrect = _isAnswerCorrect(problem, userValue);

    return AnswerJudgement(
      isCorrect: isCorrect,
      diagnosis: isCorrect
          ? null
          : MistakeDiagnoser.diagnose(problem, userValue),
      correctSteps: steps,
    );
  }

  /// 生成分步解答。
  static List<SolutionStep> explain(MathProblem problem) {
    return StepSolver.solve(problem);
  }

  // ============ 内部方法 ============

  static BaseGenerator _selectGenerator(
    GradeConfig config, {
    Random? random,
  }) {
    final generators = _buildGenerators(config, random: random);
    if (generators.isEmpty) {
      // 回退到加减法
      return AdditionSubtractionGen(config, random: random);
    }
    final r = random ?? Random();
    return generators[r.nextInt(generators.length)];
  }

  static List<BaseGenerator> _buildGenerators(
    GradeConfig config, {
    Random? random,
  }) {
    final generators = <BaseGenerator>[];

    // 加减法（所有年级都有）
    if (config.allowedOperators.contains(Operator.add) ||
        config.allowedOperators.contains(Operator.subtract)) {
      generators.add(AdditionSubtractionGen(config, random: random));
    }

    // 乘法口诀（2年级）
    if (config.grade == 2 &&
        config.allowedOperators.contains(Operator.multiply)) {
      generators.add(MultiplicationTableGen(config, random: random));
    }

    // 有余数除法（2年级下）
    if (config.grade == 2 &&
        config.semester == '下' &&
        config.allowRemainder) {
      generators.add(RemainderDivisionGen(config, random: random));
    }

    // 多位数乘除法（3年级及以上）
    if (config.grade >= 3 &&
        (config.allowedOperators.contains(Operator.multiply) ||
            config.allowedOperators.contains(Operator.divide))) {
      generators.add(MultiDigitMulDivGen(config, random: random));
    }

    // 混合运算（3年级及以上，允许乘除法时即可生成两步混合）
    if (config.grade >= 3 &&
        config.allowedOperators.length >= 3) {
      generators.add(MixedOperationGen(config, random: random));
    }

    // 运算律（4年级）
    if (config.grade == 4 && config.semester == '上') {
      generators.add(LawOfOperationGen(config, random: random));
    }

    // 小数（4-5年级）
    if (config.allowDecimal) {
      generators.add(DecimalGen(config, random: random));
    }

    // 分数（5-6年级）
    if (config.allowFraction) {
      generators.add(FractionGen(config, random: random));
    }

    // 百分数（6年级上）
    if (config.grade == 6 && config.semester == '上') {
      generators.add(PercentageGen(config, random: random));
    }

    // 简易方程（5-6年级）
    if (config.grade >= 5) {
      generators.add(SimpleEquationGen(config, random: random));
    }

    // 比例（6年级下）
    if (config.grade == 6 && config.semester == '下') {
      generators.add(RatioProportionGen(config, random: random));
    }

    // 正负数（6年级下）
    if (config.allowNegative) {
      generators.add(NegativeNumberGen(config, random: random));
    }

    return generators;
  }

  static NumberValue _parseAnswer(String answer) {
    final trimmed = answer.trim();

    // 分数格式 "a/b"
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length == 2) {
        final n = int.tryParse(parts[0].trim());
        final d = int.tryParse(parts[1].trim());
        if (n != null && d != null && d != 0) {
          return NumberValue.fromFraction(n, d);
        }
      }
    }

    // 小数或整数
    final value = double.tryParse(trimmed);
    if (value != null) {
      if (value == value.roundToDouble()) {
        return NumberValue.fromInt(value.round());
      }
      return NumberValue.fromDouble(value);
    }

    return NumberValue.fromInt(0);
  }

  static bool _isAnswerCorrect(MathProblem problem, NumberValue userValue) {
    if (problem.resultForm == ResultForm.fraction) {
      return userValue.asFraction == problem.result.asFraction;
    }
    // 允许小数误差
    final diff = (userValue.asDouble - problem.result.asDouble).abs();
    return diff < 0.001;
  }
}
