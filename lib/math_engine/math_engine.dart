// lib/math_engine/math_engine.dart
//
// 口算引擎统一入口。
// 无 Flutter 依赖，纯 Dart 实现。

import 'dart:math';

import 'models/answer_judgement.dart';
import 'models/difficulty_level.dart';
import 'models/grade_config.dart';
import 'models/math_problem.dart';
import 'models/math_skill.dart';
import 'models/vertical_attempt.dart';
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
import 'presets/difficulty_adjuster.dart';
import 'validators/constraint_checker.dart';

/// 口算引擎：生成 → 判定 → 诊断 → 解释。
class MathEngine {
  const MathEngine._();

  /// UI 与生成器共享年级、难度对应的模式白名单。
  static Set<ProblemMode> supportedModes({
    required int grade,
    required String semester,
    DifficultyLevel? difficulty,
  }) {
    final base = GradePresets.get(grade, semester);
    return Set.unmodifiable(
      difficulty == null
          ? base.allowedModes
          : DifficultyAdjuster.adjust(base, difficulty).allowedModes,
    );
  }

  /// 生成一道题目。
  ///
  /// [grade] 年级（1-6），[semester] 学期（'上' 或 '下'）。
  /// [mode] 可选的题目模式，默认随机。
  /// [difficulty] 可选的难度级别，默认使用年级原始配置。
  /// [random] 可选的随机数生成器（用于测试）。
  static MathProblem generate({
    required int grade,
    required String semester,
    ProblemMode? mode,
    DifficultyLevel? difficulty,
    Random? random,
    String? skillId,
    bool verticalProcessOnly = false,
  }) {
    if (verticalProcessOnly && mode != ProblemMode.vertical) {
      throw ArgumentError('逐列过程练习必须使用竖式模式');
    }
    var config = GradePresets.get(grade, semester);
    if (difficulty != null) {
      config = DifficultyAdjuster.adjust(config, difficulty);
    }
    if (mode != null && !config.allowedModes.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', '该学期不支持此练习模式');
    }
    final rng = random ?? Random();
    final requestedSkill = MathSkill.fromId(skillId);
    if (skillId != null && requestedSkill == null) {
      throw ArgumentError.value(skillId, 'skillId', '未知知识点');
    }
    final generators = _buildGenerators(config, random: rng)
        .where(
          (g) =>
              requestedSkill == null ||
              _generatorSkills(g).contains(requestedSkill),
        )
        .toList();
    if (generators.isEmpty) throw ArgumentError('当前册次不支持此知识点');

    // 约束检查，不通过则重新生成（最多 100 次）
    for (var i = 0;
        i < (requestedSkill == null && !verticalProcessOnly ? 100 : 1000);
        i++) {
      final generator = generators[rng.nextInt(generators.length)];
      final problem = generator.generate();

      // 若指定了模式，强制转换
      final converted = _applyMode(problem, mode, config, generator);
      if (converted == null) continue; // 模式不兼容，重试
      // 综合属于普通方案；竖式只能由用户明确选择后进入。
      if (mode == null && converted.mode == ProblemMode.vertical) continue;
      if (verticalProcessOnly && !VerticalAttempt.supportsProcess(converted)) {
        continue;
      }
      final skill = _classifySkill(generator, converted);
      if (requestedSkill != null && skill != requestedSkill) continue;

      final violation = ConstraintChecker.check(converted, config);
      if (violation == null) {
        return converted.withContext(skillId: skill.id, semester: semester);
      }
    }

    if (requestedSkill != null || verticalProcessOnly) {
      throw StateError('无法生成满足当前册次、模式和知识点的专项题，请调整选择');
    }

    // 兜底也必须兑现请求模式，并通过与常规生成相同的约束。
    final fallback = AdditionSubtractionGen(config, random: rng);
    for (var i = 0; i < 100; i++) {
      final seed = mode == ProblemMode.chain || mode == ProblemMode.withBrackets
          ? MathProblem(
              operands: List.generate(3, (_) => NumberValue.fromInt(1)),
              operators: const [Operator.add, Operator.add],
              result: NumberValue.fromInt(3),
              mode: mode!,
              grade: grade,
              bracketRange: mode == ProblemMode.withBrackets ? (0, 2) : null,
            )
          : fallback.generate();
      final converted = _applyMode(seed, mode, config, fallback);
      if (converted != null &&
          (mode != null || converted.mode != ProblemMode.vertical) &&
          ConstraintChecker.check(converted, config) == null) {
        return converted.withContext(
          skillId: _classifySkill(fallback, converted).id,
          semester: semester,
        );
      }
    }
    throw StateError('无法生成满足所选模式和学期约束的题目');
  }

  /// 将题目转换为指定模式。返回 null 表示不兼容需重试。
  static MathProblem? _applyMode(
    MathProblem problem,
    ProblemMode? mode,
    GradeConfig config,
    BaseGenerator generator,
  ) {
    if (mode == null) return problem;

    // 已经是目标模式
    if (problem.mode == mode) return problem;

    // 专题题面和未知数是所学内容的一部分，不能转成普通求值后继续贴专题标签。
    if (problem.displayText != null || generator is SimpleEquationGen) {
      return null;
    }

    switch (mode) {
      case ProblemMode.compare:
        if (!config.allowedModes.contains(ProblemMode.compare)) return null;
        // 余数题答案为「商…余」混合格式，比较/挖空模式无法表达，
        // 不兼容返回 null 重试（与 vertical 仅支持 findResult 的先例同构）。
        if (problem.resultForm == ResultForm.withRemainder) return null;
        return generator.toCompare(problem);
      case ProblemMode.vertical:
        if (!config.allowedModes.contains(ProblemMode.vertical)) return null;
        // 竖式只支持 findResult 模式的加减乘法
        if (problem.mode != ProblemMode.findResult) return null;
        final converted = generator.toVertical(problem);
        return converted.mode == mode ? converted : null;
      case ProblemMode.findMissing:
        if (!config.allowedModes.contains(ProblemMode.findMissing)) return null;
        // 同 compare：余数题转 findMissing 后答案变成「缺失项…余数」
        // 混合格式（如 38…2），孩子无法作答。
        if (problem.resultForm == ResultForm.withRemainder) return null;
        return generator.toFindMissing(problem);
      case ProblemMode.findResult:
        final value = problem.expressionResult ?? problem.result;
        return MathProblem(
          operands: problem.operands,
          operators: problem.operators,
          result: value,
          mode: mode,
          grade: problem.grade,
          difficulty: problem.difficulty,
          resultForm: problem.resultForm == ResultForm.withRemainder
              ? ResultForm.withRemainder
              : MathProblem.formFor(value),
          remainder: problem.remainder,
          bracketRange: problem.bracketRange,
        );
      case ProblemMode.chain:
      case ProblemMode.withBrackets:
        return null;
    }
  }

  /// 批量生成题目。
  static List<MathProblem> generateBatch({
    required int grade,
    required String semester,
    int count = 10,
    ProblemMode? mode,
    DifficultyLevel? difficulty,
    Random? random,
    String? skillId,
    bool verticalProcessOnly = false,
  }) {
    return List.generate(
      count,
      (_) => generate(
        grade: grade,
        semester: semester,
        mode: mode,
        difficulty: difficulty,
        random: random,
        skillId: skillId,
        verticalProcessOnly: verticalProcessOnly,
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
                parseAnswer(userAnswer.split('…').first) ??
                    NumberValue.fromInt(-1),
              ),
        correctSteps: steps,
      );
    }

    final userValue = parseAnswer(userAnswer);
    final isCorrect = userValue != null && userValue == problem.result;

    return AnswerJudgement(
      isCorrect: isCorrect,
      diagnosis: isCorrect || userValue == null
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

  static Set<MathSkill> _generatorSkills(BaseGenerator generator) =>
      switch (generator) {
        AdditionSubtractionGen() => {
            MathSkill.addition,
            MathSkill.additionCarry,
            MathSkill.subtraction,
            MathSkill.subtractionBorrow,
            MathSkill.operationOrder,
          },
        MultiplicationTableGen() => {MathSkill.multiplicationTable},
        RemainderDivisionGen() => {MathSkill.remainderDivision},
        MultiDigitMulDivGen() => {MathSkill.multiplication, MathSkill.division},
        MixedOperationGen() => {MathSkill.operationOrder},
        LawOfOperationGen() => {MathSkill.operationLaw},
        DecimalGen() => {MathSkill.decimal},
        FractionGen() => {MathSkill.fraction},
        PercentageGen() => {MathSkill.percentage},
        SimpleEquationGen() => {MathSkill.equation},
        RatioProportionGen() => {MathSkill.ratio},
        NegativeNumberGen() => {MathSkill.negative},
        _ => throw StateError('生成器缺少知识点映射'),
      };

  static MathSkill _classifySkill(BaseGenerator generator, MathProblem p) {
    if (generator is AdditionSubtractionGen) {
      if (p.operators.length > 1) return MathSkill.operationOrder;
      final regrouping = MathSkill.hasRegrouping(p);
      return p.operators.single == Operator.add
          ? (regrouping ? MathSkill.additionCarry : MathSkill.addition)
          : (regrouping ? MathSkill.subtractionBorrow : MathSkill.subtraction);
    }
    if (generator is MultiDigitMulDivGen) {
      return p.operators.single == Operator.multiply
          ? MathSkill.multiplication
          : MathSkill.division;
    }
    return _generatorSkills(generator).single;
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
    if (config.grade == 2 && config.semester == '下' && config.allowRemainder) {
      generators.add(RemainderDivisionGen(config, random: random));
    }

    // 多位数乘除法（3年级及以上）
    if (config.grade >= 3 &&
        (config.allowedOperators.contains(Operator.multiply) ||
            config.allowedOperators.contains(Operator.divide))) {
      generators.add(MultiDigitMulDivGen(config, random: random));
    }

    // 混合运算（3年级及以上，允许乘除法时即可生成两步混合）
    if (config.grade >= 3 && config.allowedOperators.length >= 3) {
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

  /// 无效输入返回 null；数字按文本精确解析，不将错误输入或舍入误差视为零。
  static NumberValue? parseAnswer(String answer) {
    final trimmed = answer.trim();
    if (trimmed.isEmpty || trimmed.length > 64) return null;

    // 带分数格式 "a b/c"（如 '1 1/2'，支持负数 '-1 1/2'）
    final spaced = trimmed.split(RegExp(r'\s+'));
    if (spaced.length == 2 && spaced[1].contains('/')) {
      final whole = _parseInteger(spaced[0]);
      final fracParts = spaced[1].split('/');
      if (whole != null && fracParts.length == 2) {
        final n = _parseInteger(fracParts[0]);
        final d = _parseInteger(fracParts[1]);
        if (n != null && d != null && d > BigInt.zero && n >= BigInt.zero) {
          final numerator = whole.abs() * d + n;
          return _boundedFraction(
            spaced[0].startsWith('-') ? -numerator : numerator,
            d,
          );
        }
      }
    }

    // 分数格式 "a/b"
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length == 2) {
        final n = _parseInteger(parts[0].trim());
        final d = _parseInteger(parts[1].trim());
        if (n != null && d != null && d != BigInt.zero) {
          return _boundedFraction(n, d);
        }
      }
    }

    final integer = _parseInteger(trimmed);
    if (integer != null) return _boundedFraction(integer, BigInt.one);
    if (!RegExp(r'^[+-]?(?:\d{1,8}\.\d{0,8}|\.\d{1,8})$').hasMatch(trimmed)) {
      return null;
    }
    final parts = trimmed.replaceFirst(RegExp(r'^[+-]'), '').split('.');
    final denominator = BigInt.from(10).pow(parts[1].length);
    final numerator =
        BigInt.tryParse('${parts[0].isEmpty ? '0' : parts[0]}${parts[1]}');
    if (numerator == null) return null;
    return _boundedFraction(
      trimmed.startsWith('-') ? -numerator : numerator,
      denominator,
    );
  }

  static BigInt? _parseInteger(String text) =>
      RegExp(r'^[+-]?\d+$').hasMatch(text) ? BigInt.tryParse(text) : null;

  static NumberValue? _boundedFraction(BigInt numerator, BigInt denominator) {
    final gcd = numerator.gcd(denominator);
    numerator ~/= gcd;
    denominator ~/= gcd;
    // 保证原生与 Web 的整数表示均精确，避免带分数乘积和 abs 回绕。
    final max = BigInt.from(9007199254740991);
    if (numerator.abs() > max || denominator.abs() > max) return null;
    return NumberValue.fromFraction(numerator.toInt(), denominator.toInt());
  }

  /// 用于只有答案快照的历史错题，保持与正式练习的数值判分一致。
  static bool answersEquivalent(String actual, String expected) {
    final a = actual.trim().replaceAll('−', '-');
    final b = expected.trim().replaceAll('−', '-');
    if (const ['<', '=', '>'].contains(b) || b.contains('…')) return a == b;
    final value = parseAnswer(a);
    final correct = parseAnswer(b);
    return value != null && correct != null && value == correct;
  }
}
