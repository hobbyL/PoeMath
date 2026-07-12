// lib/math_engine/generators/mixed_operation_gen.dart
//
// 混合运算生成器（3-4 年级）。

import '../models/math_problem.dart';
import '../models/number_value.dart';
import 'base_generator.dart';

/// 混合运算生成器（两到三步运算）。
class MixedOperationGen extends BaseGenerator {
  MixedOperationGen(super.config, {super.random});

  @override
  MathProblem generate() {
    final stepCount = randomInt(2, config.maxOperands.clamp(2, 3));
    return stepCount == 2 ? _twoStep() : _threeStep();
  }

  MathProblem _twoStep() {
    // 生成 a ○ b ○ c 形式，确保中间结果和最终结果合理
    final ops = _pickOperators(2);
    final values = _generateValidOperands(ops);
    if (values == null) return _twoStep();

    final operands = values.map((v) => NumberValue.fromInt(v)).toList();
    final result = _evaluate(values, ops);

    if (result < 0 || result > config.maxResult) return _twoStep();

    final difficulty = scoreDifficulty(operands, ops);

    return MathProblem(
      operands: operands,
      operators: ops,
      result: NumberValue.fromInt(result),
      mode: ProblemMode.chain,
      grade: config.grade,
      difficulty: difficulty,
    );
  }

  MathProblem _threeStep() {
    final ops = _pickOperators(3);
    final values = _generateValidOperands(ops);
    if (values == null) return _threeStep();

    final operands = values.map((v) => NumberValue.fromInt(v)).toList();
    final result = _evaluate(values, ops);

    if (result < 0 || result > config.maxResult) return _threeStep();

    final difficulty = (scoreDifficulty(operands, ops) + 1).clamp(1, 5);

    final usesBrackets = config.allowBrackets && randomInt(0, 2) == 0;

    return MathProblem(
      operands: operands,
      operators: ops,
      result: NumberValue.fromInt(result),
      mode: usesBrackets ? ProblemMode.withBrackets : ProblemMode.chain,
      grade: config.grade,
      difficulty: difficulty,
      bracketRange: usesBrackets ? (0, 2) : null,
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

  /// 按数学运算顺序（先乘除后加减）计算结果。
  int _evaluate(List<int> values, List<Operator> ops) {
    // 复制列表以避免修改原始数据
    final vals = List<int>.from(values);
    final opList = List<Operator>.from(ops);

    // 先处理乘除
    var i = 0;
    while (i < opList.length) {
      if (opList[i] == Operator.multiply || opList[i] == Operator.divide) {
        if (opList[i] == Operator.multiply) {
          vals[i] = vals[i] * vals[i + 1];
        } else {
          if (vals[i + 1] == 0) return -1;
          vals[i] = vals[i] ~/ vals[i + 1];
        }
        vals.removeAt(i + 1);
        opList.removeAt(i);
      } else {
        i++;
      }
    }

    // 再处理加减
    var result = vals[0];
    for (i = 0; i < opList.length; i++) {
      if (opList[i] == Operator.add) {
        result += vals[i + 1];
      } else {
        result -= vals[i + 1];
      }
    }
    return result;
  }
}
