// lib/math_engine/generators/mixed_operation_gen.dart
//
// 混合运算生成器：自动模式沿用年级预设；自选次数支持各年级已允许的运算。
//
// 核心不变量：「题面显示语义 = 判分答案」。
// withBrackets 题的 result 必须等于按显示语义（先算括号，括号内与
// 括号外均先乘除后加减、同级从左到右）的精确求值结果；整数题的中间
// 与最终结果必须为整数。自动模式可降级为 chain；显式次数和括号请求
// 必须严格兑现，无法生成时有界失败（不递归重试）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import '../validators/expression_evaluator.dart';
import '../validators/constraint_checker.dart';
import 'base_generator.dart';

/// 混合运算生成器（两到三步运算）。
class MixedOperationGen extends BaseGenerator {
  MixedOperationGen(
    super.config, {
    super.random,
    this.operationCount,
    this.requestedMode,
  });

  final int? operationCount;
  final ProblemMode? requestedMode;

  /// 生成尝试上限（防御未来预设改动导致死循环）。
  static const _maxAttempts = 200;

  @override
  MathProblem generate() {
    if (operationCount != null) return _exactSteps(operationCount!);
    final stepCount = randomInt(2, config.maxOperands.clamp(2, 3));
    return stepCount == 2 ? _twoStep() : _threeStep();
  }

  MathProblem _exactSteps(int count) {
    if (count < 2 || count > 3) {
      throw ArgumentError.value(count, 'operationCount', '组合题须为 2 或 3 次');
    }
    final brackets =
        requestedMode == ProblemMode.withBrackets ||
        (requestedMode != ProblemMode.chain &&
            config.allowBrackets &&
            config.allowedModes.contains(ProblemMode.withBrackets) &&
            randomInt(0, 2) == 0);
    if (brackets && !config.allowBrackets) {
      throw ArgumentError('当前范围未开放括号');
    }
    // 先固定形态，再挑数值；不能因某种形态较难生成而静默移除它。
    final bracketLength = brackets ? randomInt(2, count) : 0;
    final bracketStart = brackets ? randomInt(0, count + 1 - bracketLength) : 0;
    final bracketRange = brackets
        ? (bracketStart, bracketStart + bracketLength)
        : null;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final operators = _pickOperators(count);
      final max = config.maxOperand.clamp(1, 100);
      final min = config.minOperand.clamp(1, max);
      final values = List.generate(count + 1, (_) => randomInt(min, max));
      for (var i = 0; i < count; i++) {
        if (operators[i] == Operator.multiply) {
          final factorMax = config.maxMultiplier.clamp(min, max).clamp(min, 9);
          values[i] = randomInt(min, factorMax);
          values[i + 1] = randomInt(min, factorMax);
        } else if (operators[i] == Operator.divide) {
          final dividendMax = config.maxDividend.clamp(min, max);
          final divisor = randomInt(min.clamp(2, 9), dividendMax.clamp(2, 9));
          final quotientMax = (dividendMax ~/ divisor).clamp(1, 9);
          values[i] = divisor * randomInt(1, quotientMax);
          values[i + 1] = divisor;
        }
      }
      final candidate = _checkedExact(values, operators, bracketRange);
      if (candidate != null) return candidate;
    }

    // 小数值结构作为有界兜底；同样核验中间值、括号和次数。
    // 不允许把三步降为两步，或把带括号降为无括号。
    for (final operator in config.allowedOperators) {
      for (
        var value = config.minOperand.clamp(1, 9);
        value <= config.maxOperand.clamp(1, 9);
        value++
      ) {
        final values = List<int>.filled(count + 1, value);
        if (operator == Operator.subtract) values[0] = count * value;
        final candidate = _checkedExact(
          values,
          List<Operator>.filled(count, operator),
          bracketRange,
        );
        if (candidate != null) return candidate;
      }
    }
    throw StateError('无法生成满足所选次数和数值范围的组合题');
  }

  MathProblem? _checkedExact(
    List<int> values,
    List<Operator> operators,
    (int, int)? bracketRange,
  ) {
    final operands = values.map(NumberValue.fromInt).toList();
    final trace = ExpressionEvaluator.evaluateWithSteps(
      operands,
      operators,
      bracketRange: bracketRange,
    );
    if (ConstraintChecker.checkIntegerSteps(trace, config) != null) return null;
    final problem = MathProblem(
      operands: operands,
      operators: operators,
      result: NumberValue.fromInt(trace!.value.asInteger),
      mode: bracketRange == null ? ProblemMode.chain : ProblemMode.withBrackets,
      grade: config.grade,
      difficulty: scoreDifficulty(operands, operators),
      bracketRange: bracketRange,
    );
    if (ConstraintChecker.check(problem, config) != null) return null;
    if (requestedMode == null) {
      final mode = randomInt(0, 4);
      if (mode == 0 && config.allowedModes.contains(ProblemMode.findMissing)) {
        return toFindMissing(problem);
      }
      if (mode == 1 && config.allowedModes.contains(ProblemMode.compare)) {
        return toCompare(problem);
      }
    }
    return problem;
  }

  MathProblem _twoStep() {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final ops = _pickOperators(2);
      final values = _generateValidOperands(ops);
      if (values == null) continue;

      final operands = values.map((v) => NumberValue.fromInt(v)).toList();
      final result = ExpressionEvaluator.evaluate(operands, ops);
      // 整数题：求值必须可用且结果为整数
      if (result == null || !result.isInteger) continue;
      final resultInt = result.asInteger;
      if (resultInt < 0 || resultInt > config.maxResult) continue;

      return MathProblem(
        operands: operands,
        operators: ops,
        result: NumberValue.fromInt(resultInt),
        mode: ProblemMode.chain,
        grade: config.grade,
        difficulty: scoreDifficulty(operands, ops),
      );
    }
    return _fallbackProblem();
  }

  MathProblem _threeStep() {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final ops = _pickOperators(3);
      final values = _generateValidOperands(ops);
      if (values == null) continue;

      final operands = values.map((v) => NumberValue.fromInt(v)).toList();

      // 无括号（chain）语义下的精确结果
      final plainResult = ExpressionEvaluator.evaluate(operands, ops);
      if (plainResult == null || !plainResult.isInteger) continue;
      final plainInt = plainResult.asInteger;
      if (plainInt < 0 || plainInt > config.maxResult) continue;

      var mode = ProblemMode.chain;
      (int, int)? bracketRange;
      var resultValue = plainInt;

      // 括号路径：按显示语义精确求值；非法组合确定性降级为 chain
      if (config.allowBrackets && randomInt(0, 2) == 0) {
        final trace = ExpressionEvaluator.evaluateWithSteps(
          operands,
          ops,
          bracketRange: (0, 2),
        );
        final bracketInt = _validBracketResult(trace);
        if (bracketInt != null) {
          mode = ProblemMode.withBrackets;
          bracketRange = (0, 2);
          resultValue = bracketInt;
        }
      }

      final difficulty = (scoreDifficulty(operands, ops) + 1).clamp(1, 5);

      return MathProblem(
        operands: operands,
        operators: ops,
        result: NumberValue.fromInt(resultValue),
        mode: mode,
        grade: config.grade,
        difficulty: difficulty,
        bracketRange: bracketRange,
      );
    }
    return _fallbackProblem();
  }

  /// 括号语义结果合法性：可用、中间值全整数、最终整数、非负、不超上限。
  /// 不合法返回 null（调用方降级为 chain，用无括号结果）。
  int? _validBracketResult(EvaluationTrace? trace) {
    if (trace == null) return null;
    // 整数题要求括号内与括号外的中间值全部为整数
    if (!trace.steps.every((s) => s.value.isInteger)) return null;
    final value = trace.value;
    if (!value.isInteger) return null;
    final valueInt = value.asInteger;
    if (valueInt < 0 || valueInt > config.maxResult) return null;
    return valueInt;
  }

  /// 保底题：小操作数加法 chain（必过约束校验）。
  MathProblem _fallbackProblem() {
    final a = randomInt(1, 9);
    final b = randomInt(1, 9);
    final c = randomInt(1, 9);
    final operands = [a, b, c].map((v) => NumberValue.fromInt(v)).toList();
    return MathProblem(
      operands: operands,
      operators: [Operator.add, Operator.add],
      result: NumberValue.fromInt(a + b + c),
      mode: ProblemMode.chain,
      grade: config.grade,
      difficulty: 2,
    );
  }

  List<Operator> _pickOperators(int count) {
    final available = config.allowedOperators.toList();
    return List.generate(count, (_) => randomChoice(available));
  }

  List<int>? _generateValidOperands(List<Operator> ops) {
    final count = ops.length + 1;
    final values = <int>[];

    for (var i = 0; i < count; i++) {
      if (i == 0) {
        values.add(randomInt(1, 100.clamp(1, config.maxOperand)));
      } else {
        final op = ops[i - 1];
        final prev = values.last;
        switch (op) {
          case Operator.add:
            values.add(randomInt(1, 100.clamp(1, config.maxOperand)));
          case Operator.subtract:
            values.add(randomInt(1, prev.clamp(1, 100)));
          case Operator.multiply:
            values.add(randomInt(2, 9));
          case Operator.divide:
            // 找 prev 的因数
            final factors = _findFactors(prev).where((f) => f > 1).toList();
            if (factors.isEmpty) return null;
            values.add(randomChoice(factors));
        }
      }
    }
    return values;
  }

  List<int> _findFactors(int n) {
    if (n <= 0) return [1];
    final factors = <int>[];
    for (var i = 1; i * i <= n; i++) {
      if (n % i == 0) {
        factors.add(i);
        if (i != n ~/ i) factors.add(n ~/ i);
      }
    }
    factors.sort();
    return factors;
  }
}
