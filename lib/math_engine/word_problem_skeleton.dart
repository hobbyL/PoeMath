// lib/math_engine/word_problem_skeleton.dart
//
// 知识点定向的整数结构骨架生成（应用题专用）。
// 核心不变量：算法定结构与答案，LLM 只套情境文本——
// 所有操作数与答案均为非负整数，且等于 ExpressionEvaluator 精确求值结果。
//
// 纯 Dart，无 Flutter 依赖。

import 'dart:math';

import 'generators/addition_subtraction_gen.dart';
import 'generators/base_generator.dart';
import 'generators/mixed_operation_gen.dart';
import 'generators/multiplication_table_gen.dart';
import 'generators/multi_digit_mul_div_gen.dart';
import 'models/grade_config.dart';
import 'models/difficulty_level.dart';
import 'models/math_problem.dart';
import 'models/number_value.dart';
import 'models/problem_skeleton.dart';
import 'presets/grade_presets.dart';
import 'presets/difficulty_adjuster.dart';
import 'validators/constraint_checker.dart';
import 'validators/expression_evaluator.dart';

/// 常用单位池（同题同质，算法侧随机指定，LLM 只能沿用）。
const List<String> kWordProblemUnitPool = [
  '个',
  '支',
  '颗',
  '本',
  '张',
  '元',
  '米',
  '千克',
  '朵',
  '瓶',
];

/// 应用题知识点骨架生成器。
///
/// 复用现有各学期生成器与 GradeConfig 预设，只做「知识点定向」：
/// - addition / subtraction → AdditionSubtractionGen，锁定单一运算符
/// - multiplication / division →
///   2 年级走 MultiplicationTableGen，3 年级及以上走 MultiDigitMulDivGen，
///   按运算过滤
/// - mixed → 锁两步 chain（无括号）；二年级仅困难档开放
class WordProblemSkeletonGenerator {
  const WordProblemSkeletonGenerator._();

  /// 生成 [count] 个整数结构骨架。
  ///
  /// [topic] 白名单外的知识点抛 [ArgumentError]；[count] 必须 ≥ 1。
  static List<ProblemSkeleton> generate({
    required int grade,
    required String semester,
    required String topic,
    required int count,
    DifficultyLevel difficulty = DifficultyLevel.medium,
    Random? random,
  }) {
    final parsedTopic = WordProblemTopic.tryParse(topic);
    if (parsedTopic == null) {
      throw ArgumentError('未知知识点: $topic');
    }
    if (count < 1) {
      throw ArgumentError('生成数量必须 ≥ 1');
    }
    final config =
        configuration(grade: grade, semester: semester, difficulty: difficulty);
    final r = random ?? Random();

    return List.generate(
      count,
      (_) {
        if (!isTopicAvailable(config, parsedTopic, difficulty: difficulty)) {
          throw ArgumentError('该学期不学习此知识点');
        }
        var best = _generateOne(config, parsedTopic, r);
        if (difficulty == DifficultyLevel.hard) {
          for (var i = 1; i < 8; i++) {
            final candidate = _generateOne(config, parsedTopic, r);
            if (_selectionScore(candidate, grade) >
                _selectionScore(best, grade)) {
              best = candidate;
            }
          }
        }
        return best;
      },
    );
  }

  /// 判定某学期配置下指定知识点是否可生成（镜像 [generate] 各分支的学期守卫）。
  ///
  /// 规则与下方各 `_generate*` 的 [ArgumentError] 守卫严格一致：
  /// - 加/减/乘/除：对应运算符在 `config.allowedOperators` 中
  /// - 混合运算：三年级起，或二年级困难档，且学期允许乘除
  ///
  /// UI 据此隐藏当前学期不学的知识点，避免用户选中后生成才报错。
  static bool isTopicAvailable(
    GradeConfig config,
    WordProblemTopic topic, {
    DifficultyLevel difficulty = DifficultyLevel.medium,
  }) {
    switch (topic) {
      case WordProblemTopic.addition:
        return config.allowedOperators.contains(Operator.add);
      case WordProblemTopic.subtraction:
        return config.allowedOperators.contains(Operator.subtract);
      case WordProblemTopic.multiplication:
        return config.allowedOperators.contains(Operator.multiply);
      case WordProblemTopic.division:
        return config.allowedOperators.contains(Operator.divide);
      case WordProblemTopic.mixed:
        return (config.grade >= 3 ||
                config.grade == 2 && difficulty == DifficultyLevel.hard) &&
            config.allowedOperators.length >= 3;
    }
  }

  /// 返回「年级+学期」下可生成的知识点（保持 [WordProblemTopic.values] 顺序）。
  ///
  /// 加法/减法在全部 12 个学期预设中恒存在，返回列表不会为空。
  static List<WordProblemTopic> availableTopics({
    required int grade,
    required String semester,
    DifficultyLevel difficulty = DifficultyLevel.medium,
  }) {
    final config = GradePresets.get(grade, semester);
    return WordProblemTopic.values
        .where(
          (topic) => isTopicAvailable(config, topic, difficulty: difficulty),
        )
        .toList();
  }

  /// 应用题保留所选知识点；简单档缩小数值，不隐藏乘除知识点。
  /// 两步题的 chain 只用于本地数量计划，不改变口算的模式白名单。
  static GradeConfig configuration({
    required int grade,
    required String semester,
    DifficultyLevel difficulty = DifficultyLevel.medium,
  }) {
    final base = GradePresets.get(grade, semester);
    final adjusted = difficulty == DifficultyLevel.easy
        ? DifficultyAdjuster.adjust(base, difficulty)
        : base;
    return adjusted.withAllowed(
      operators: base.allowedOperators,
      modes: {...adjusted.allowedModes, ProblemMode.chain},
    );
  }

  static int _selectionScore(ProblemSkeleton skeleton, int grade) =>
      DifficultyScorer.selectionScore(
        MathProblem(
          operands: skeleton.operands.map(NumberValue.fromInt).toList(),
          operators: skeleton.operators,
          result: NumberValue.fromInt(skeleton.answer),
          mode: ProblemMode.findResult,
          grade: grade,
        ),
      );

  static ProblemSkeleton _generateOne(
    GradeConfig config,
    WordProblemTopic topic,
    Random random,
  ) {
    // 单位池随机（骨架内单位同质：每题独立随机一次）。
    final unitHint = kWordProblemUnitPool[random.nextInt(
      kWordProblemUnitPool.length,
    )];

    MathProblem problem;
    switch (topic) {
      case WordProblemTopic.addition:
        problem = _generateLockedAddSub(config, Operator.add, random);
      case WordProblemTopic.subtraction:
        problem = _generateLockedAddSub(config, Operator.subtract, random);
      case WordProblemTopic.multiplication:
        problem = _generateMulDiv(config, Operator.multiply, random);
      case WordProblemTopic.division:
        problem = _generateMulDiv(config, Operator.divide, random);
      case WordProblemTopic.mixed:
        problem = _generateMixedChain(config, random);
    }

    return _toSkeleton(problem, unitHint);
  }

  /// 加减法锁定单一运算符：反复生成直到产出目标运算符的 findResult 题。
  ///
  /// AdditionSubtractionGen 会在 findMissing/compare/vertical 间随机转换，
  /// 且运算符从 allowedOperators 随机选择——此处按运算符与模式过滤重试。
  static MathProblem _generateLockedAddSub(
    GradeConfig config,
    Operator target,
    Random random,
  ) {
    if (!config.allowedOperators.contains(target)) {
      throw ArgumentError('该学期不学习此知识点: ${target.symbol}');
    }
    final generator = AdditionSubtractionGen(config, random: random);
    for (var attempt = 0; attempt < 200; attempt++) {
      final problem = generator.generate();
      if (problem.mode != ProblemMode.findResult) continue;
      if (problem.operators.length != 1) continue;
      if (problem.operators.first != target) continue;
      final violation = ConstraintChecker.check(problem, config);
      if (violation != null) continue;
      if (!_isNonNegativeIntegerProblem(problem)) continue;
      return problem;
    }
    throw StateError('无法生成目标运算符的加减法骨架');
  }

  /// 乘除法：2 年级走乘法口诀表，3 年级及以上走多位数乘除生成器，
  /// 均按目标运算符过滤。
  static MathProblem _generateMulDiv(
    GradeConfig config,
    Operator target,
    Random random,
  ) {
    if (!config.allowedOperators.contains(target)) {
      throw ArgumentError('该学期不学习此知识点: ${target.symbol}');
    }
    final BaseGenerator generator;
    if (config.grade == 2) {
      generator = MultiplicationTableGen(config, random: random);
    } else {
      generator = MultiDigitMulDivGen(config, random: random);
    }
    for (var attempt = 0; attempt < 200; attempt++) {
      final problem = generator.generate();
      if (problem.mode != ProblemMode.findResult) continue;
      if (problem.operators.length != 1) continue;
      if (problem.operators.first != target) continue;
      if (target == Operator.multiply &&
          problem.operands
              .any((value) => value.asInteger > config.maxMultiplier)) {
        continue;
      }
      if (target == Operator.divide &&
          problem.operands.first.asInteger > config.maxDividend) {
        continue;
      }
      final violation = ConstraintChecker.check(problem, config);
      if (violation != null) continue;
      if (!_isNonNegativeIntegerProblem(problem)) continue;
      return problem;
    }
    throw StateError('无法生成目标运算符的乘除法骨架');
  }

  /// 混合运算锁定 chain 形态（无括号，一期取舍：bracketRange 不入库，
  /// 带括号题情境表述有歧义风险）。
  static MathProblem _generateMixedChain(GradeConfig config, Random random) {
    if (config.grade < 2 || config.allowedOperators.length < 3) {
      throw ArgumentError('该学期不学习混合运算');
    }
    final generator = MixedOperationGen(config, random: random);
    for (var attempt = 0; attempt < 200; attempt++) {
      final problem = generator.generate();
      if (problem.mode != ProblemMode.chain) continue;
      if (problem.bracketRange != null) continue;
      if (problem.operators.length != 2 ||
          ![Operator.add, Operator.subtract]
              .contains(problem.operators.first)) {
        continue;
      }
      final violation = ConstraintChecker.check(problem, config);
      if (violation != null) continue;
      if (!_isNonNegativeIntegerProblem(problem)) continue;
      if (config.grade == 2) {
        final b = problem.operands[1].asInteger;
        final c = problem.operands[2].asInteger;
        if (problem.operators.last == Operator.multiply && (b > 9 || c > 9)) {
          continue;
        }
        if (problem.operators.last == Operator.divide &&
            (b > 81 || c > 9 || b ~/ c > 9)) {
          continue;
        }
        final trace = ExpressionEvaluator.evaluateWithSteps(
          problem.operands,
          problem.operators,
        );
        if (trace == null ||
            trace.steps.any(
              (s) =>
                  !s.value.isInteger ||
                  s.value.numerator < 0 ||
                  s.value.asDouble > config.maxResult,
            )) {
          continue;
        }
      }
      return problem;
    }
    throw StateError('无法生成 chain 形态的混合运算骨架');
  }

  /// 整数不变量：全部操作数与结果均为非负整数。
  static bool _isNonNegativeIntegerProblem(MathProblem problem) {
    if (!problem.operands.every((o) => o.isInteger && !o.isNegative)) {
      return false;
    }
    if (!problem.result.isInteger || problem.result.isNegative) return false;
    return true;
  }

  /// MathProblem → ProblemSkeleton（复算校验 + 组装）。
  static ProblemSkeleton _toSkeleton(
    MathProblem problem,
    String unitHint,
  ) {
    final operands = problem.operands.map((o) => o.asInteger).toList();
    final answer = problem.result.asInteger;

    // 生成器不变量兜底复算：本地求值必须等于既定答案（防管线 bug）。
    final evaluated = ExpressionEvaluator.evaluate(
      problem.operands,
      problem.operators,
    );
    if (evaluated == null || !evaluated.isInteger) {
      throw StateError('骨架求值失败: ${problem.problemText}');
    }
    if (evaluated.asInteger != answer) {
      throw StateError('骨架求值与答案不一致: ${problem.problemText}');
    }

    return ProblemSkeleton(
      operands: operands,
      operators: problem.operators,
      answer: answer,
      unitHint: unitHint,
      difficulty: problem.difficulty,
    );
  }
}
