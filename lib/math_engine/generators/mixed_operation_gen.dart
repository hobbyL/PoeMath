// lib/math_engine/generators/mixed_operation_gen.dart
//
// 混合运算生成器（3-4 年级）。
//
// 核心不变量：「题面显示语义 = 判分答案」。
// withBrackets 题的 result 必须等于按显示语义（先算括号，括号内与
// 括号外均先乘除后加减、同级从左到右）的精确求值结果；整数题的中间
// 与最终结果必须为整数，否则确定性降级为 chain 形态产出（不递归重试）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import '../validators/expression_evaluator.dart';
import 'base_generator.dart';

/// 混合运算生成器（两到三步运算）。
class MixedOperationGen extends BaseGenerator {
  MixedOperationGen(super.config, {super.random});

  /// 生成尝试上限（防御未来预设改动导致死循环）。
  static const _maxAttempts = 200;

  @override
  MathProblem generate() {
    final stepCount = randomInt(2, config.maxOperands.clamp(2, 3));
    return stepCount == 2 ? _twoStep() : _threeStep();
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
