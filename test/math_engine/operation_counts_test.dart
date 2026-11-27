import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/generators/mixed_operation_gen.dart';
import 'package:poemath/math_engine/presets/difficulty_adjuster.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

// 递归下降参考求值，与生产的逐步折叠实现独立。生成题值均在精确整数范围内。
double _reference(MathProblem p) {
  final tokens = <Object>[];
  for (var i = 0; i < p.operands.length; i++) {
    if (i > 0) tokens.add(p.operators[i - 1]);
    if (i == p.bracketRange?.$1) tokens.add('(');
    tokens.add(p.operands[i].asDouble);
    if (i + 1 == p.bracketRange?.$2) tokens.add(')');
  }
  var index = 0;
  late double Function() expression;
  double atom() {
    final token = tokens[index++];
    if (token == '(') {
      final value = expression();
      expect(tokens[index++], ')');
      return value;
    }
    return token as double;
  }

  double product() {
    var value = atom();
    while (index < tokens.length &&
        (tokens[index] == Operator.multiply ||
            tokens[index] == Operator.divide)) {
      final op = tokens[index++];
      final right = atom();
      value = op == Operator.multiply ? value * right : value / right;
    }
    return value;
  }

  expression = () {
    var value = product();
    while (index < tokens.length &&
        (tokens[index] == Operator.add || tokens[index] == Operator.subtract)) {
      final op = tokens[index++];
      final right = product();
      value = op == Operator.add ? value + right : value - right;
    }
    return value;
  };
  final result = expression();
  expect(index, tokens.length);
  return result;
}

void _verify(MathProblem p, GradeConfig config) {
  expect(ConstraintChecker.check(p, config), isNull, reason: p.problemText);
  expect(MathEngine.judge(p, p.answerText).isCorrect, isTrue);
  if (p.resultForm != ResultForm.withRemainder) {
    expect(
      _reference(p),
      closeTo((p.expressionResult ?? p.result).asDouble, 1e-9),
    );
  }
  if (p.operators.length == 1) return;
  final trace = ExpressionEvaluator.evaluateWithSteps(
    p.operands,
    p.operators,
    bracketRange: p.bracketRange,
  )!;
  expect(trace.steps, hasLength(p.operators.length));
  expect(ConstraintChecker.checkIntegerSteps(trace, config), isNull);
  for (final step in trace.steps) {
    expect(step.value.isInteger, isTrue);
    expect(step.value.asInteger.abs(), lessThanOrEqualTo(config.maxResult));
    if (!config.allowNegative) {
      expect(step.value.asInteger, greaterThanOrEqualTo(0));
    }
  }
  final explained = MathEngine.explain(p);
  expect(explained.last.resultHint, p.answerText);
  for (final step in trace.steps) {
    expect(
      explained.map((s) => s.expression),
      contains('${step.expression} = ${step.value.asInteger}'),
    );
  }
}

void main() {
  test('次数冻结、规范化与严格校验', () {
    final source = [3, 1];
    final counts = OperationCounts(source);
    source.clear();
    expect(counts.values, [1, 3]);
    expect(counts.encode(), '1,3');
    expect(OperationCounts.decode(counts.encode()), counts);
    expect(() => counts.values.add(2), throwsUnsupportedError);
    for (final value in <Object>['', '1,,2', '2,2', '0', '4', '1.0', 'auto']) {
      expect(
        () => OperationCounts.decode(value as String),
        throwsFormatException,
      );
    }
    for (final value in <Object>[
      [],
      [1, 1],
      [0],
      [4],
      [1.0],
      ['2'],
    ]) {
      expect(() => OperationCounts.fromJson(value), throwsFormatException);
    }
  });

  for (final base in GradePresets.all) {
    for (final level in DifficultyLevel.values) {
      final config = DifficultyAdjuster.adjust(base, level).withAllowed(
        modes: {
          ...DifficultyAdjuster.adjust(base, level).allowedModes,
          ProblemMode.chain,
        },
      );
      test('${base.label}/${level.name} 七种次数组合均匀、合法且判分一致', () {
        for (var mask = 1; mask <= 7; mask++) {
          final counts = OperationCounts([
            for (var n = 1; n <= 3; n++)
              if (mask & (1 << (n - 1)) != 0) n,
          ]);
          final problems = MathEngine.generateBatch(
            grade: base.grade,
            semester: base.semester,
            difficulty: level,
            count: 11,
            operationCounts: counts,
            random: Random(1700 + mask),
          );
          expect(problems, hasLength(11));
          final totals = {for (final n in counts.values) n: 0};
          for (final p in problems) {
            expect(counts.contains(p.operators.length), isTrue);
            totals[p.operators.length] = totals[p.operators.length]! + 1;
            expect(p.operands, hasLength(p.operators.length + 1));
            _verify(p, config);
          }
          expect(
            totals.values.reduce(max) - totals.values.reduce(min),
            lessThanOrEqualTo(1),
          );
        }
      });

      test('${base.label}/${level.name} 显式题型与两三步一致', () {
        for (final mode in MathEngine.supportedModes(
          grade: base.grade,
          semester: base.semester,
          difficulty: level,
          explicitOperationCounts: true,
        ).where((m) => m != ProblemMode.vertical)) {
          final problems = MathEngine.generateBatch(
            grade: base.grade,
            semester: base.semester,
            difficulty: level,
            count: 6,
            mode: mode,
            operationCounts: OperationCounts([2, 3]),
            random: Random(3400 + mode.index),
          );
          expect(problems.where((p) => p.operators.length == 2), hasLength(3));
          expect(problems.where((p) => p.operators.length == 3), hasLength(3));
          for (final p in problems) {
            expect(p.mode, mode);
            if (mode == ProblemMode.withBrackets) {
              expect(p.bracketRange, isNotNull);
            }
            if (mode == ProblemMode.chain) expect(p.bracketRange, isNull);
            _verify(p, config);
          }
        }
      });
    }
  }

  test('括号和中间步骤的约束针对真实计算值', () {
    final trace = ExpressionEvaluator.evaluateWithSteps(
      [8, 4, 3, 6].map(NumberValue.fromInt).toList(),
      [Operator.add, Operator.divide, Operator.add],
      bracketRange: (0, 2),
    )!;
    expect(
      trace.steps.map(
        (s) => (
          s.left.asInteger,
          s.operator,
          s.right.asInteger,
          s.value.asInteger,
        ),
      ),
      [
        (8, Operator.add, 4, 12),
        (12, Operator.divide, 3, 4),
        (4, Operator.add, 6, 10),
      ],
    );
    final noCarry = DifficultyAdjuster.adjust(
      GradePresets.grade3b,
      DifficultyLevel.easy,
    );
    expect(ConstraintChecker.checkIntegerSteps(trace, noCarry), '中间步骤需要进退位');
    final fraction = ExpressionEvaluator.evaluateWithSteps(
      [5, 2, 2].map(NumberValue.fromInt).toList(),
      [Operator.divide, Operator.multiply],
    );
    expect(
      ConstraintChecker.checkIntegerSteps(fraction, GradePresets.grade3b),
      '中间结果不是整数',
    );
    final overflow = ExpressionEvaluator.evaluateWithSteps(
      [9, 9, 9].map(NumberValue.fromInt).toList(),
      [Operator.add, Operator.subtract],
    );
    expect(
      ConstraintChecker.checkIntegerSteps(overflow, GradePresets.grade1a),
      '中间结果超出范围',
    );
  });

  test('两步括号和三步括号题都能生成；除法和四则混合没有被兜底挤掉', () {
    final problems = MathEngine.generateBatch(
      grade: 3,
      semester: '下',
      count: 100,
      mode: ProblemMode.withBrackets,
      operationCounts: OperationCounts([2, 3]),
      random: Random(86),
    );
    expect(problems.where((p) => p.operators.length == 2), hasLength(50));
    expect(problems.where((p) => p.operators.length == 3), hasLength(50));
    expect(
      problems.where((p) => p.operators.contains(Operator.divide)).length,
      greaterThan(5),
    );
    expect(
      problems.where((p) => p.operators.contains(Operator.multiply)).length,
      greaterThan(5),
    );
    expect(problems.take(50).any((p) => p.operators.length == 2), isTrue);
    expect(problems.take(50).any((p) => p.operators.length == 3), isTrue);
  });

  test('不兼容请求直接拒绝，不能按一步或自动模式补题', () {
    for (final mode in [
      ProblemMode.chain,
      ProblemMode.withBrackets,
      ProblemMode.vertical,
    ]) {
      expect(
        () => MathEngine.generateBatch(
          grade: 3,
          semester: '下',
          mode: mode,
          operationCounts: OperationCounts([1, 3]),
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => MathEngine.generate(
        grade: 1,
        semester: '上',
        operationCount: 3,
        mode: ProblemMode.withBrackets,
      ),
      throwsArgumentError,
    );
    expect(
      () => MathEngine.generateBatch(
        grade: 3,
        semester: '下',
        skillId: 'addition',
        operationCounts: OperationCounts([2]),
      ),
      throwsArgumentError,
    );
    final impossible = MixedOperationGen(
      const GradeConfig(
        grade: 1,
        semester: '上',
        label: '无解',
        allowedOperators: {Operator.add},
        allowedModes: {ProblemMode.chain},
        minOperand: 2,
        maxOperand: 2,
        maxResult: 4,
      ),
      operationCount: 3,
      random: Random(1),
    );
    expect(impossible.generate, throwsStateError);
  });
}
