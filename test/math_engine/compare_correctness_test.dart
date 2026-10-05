// test/math_engine/compare_correctness_test.dart
//
// R2（toCompare 数学正确性）专项测试：
// - 批量生成 compare 题，断言 compareRelation 与「表达式值 vs compareTarget」
//   的实际关系一致（用测试内独立实现的求值器交叉验证，不依赖
//   ExpressionEvaluator）。
// - findMissing 源题（有 expressionResult）比较基准正确。
// - 非整数基准（分数/小数）不产负 offset。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/generators/base_generator.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/grade_config.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';

/// 测试内独立求值器：两遍折叠（先乘除、后加减，同级从左到右），
/// 与 ExpressionEvaluator 的折叠实现相互独立。
Fraction? evalExpr(List<NumberValue> operands, List<Operator> ops) {
  final values = operands.map((o) => o.asFraction).toList();
  final operators = [...ops];

  // 第一遍：乘除
  var i = 0;
  while (i < operators.length) {
    final op = operators[i];
    if (op == Operator.multiply || op == Operator.divide) {
      final rhs = values[i + 1];
      if (op == Operator.divide && rhs.numerator == 0) return null;
      final r = op == Operator.multiply ? values[i] * rhs : values[i] / rhs;
      values.replaceRange(i, i + 2, [r]);
      operators.removeAt(i);
    } else {
      i++;
    }
  }

  // 第二遍：加减
  var result = values[0];
  for (var j = 0; j < operators.length; j++) {
    result = operators[j] == Operator.add
        ? result + values[j + 1]
        : result - values[j + 1];
  }
  return result;
}

/// 精确比较两个分数的大小关系符号（交叉相乘，无 double 误差）。
String relationOf(Fraction a, Fraction b) {
  final cross = a.numerator * b.denominator - b.numerator * a.denominator;
  if (cross == 0) return '=';
  return cross > 0 ? '>' : '<';
}

/// 仅用 to* 模式转换方法的测试生成器。
class _ConvGen extends BaseGenerator {
  _ConvGen({required Random random})
      : super(_convConfig, random: random);

  @override
  MathProblem generate() => throw UnimplementedError();
}

const _convConfig = GradeConfig(
  grade: 6,
  semester: '上',
  label: '测试',
  allowedOperators: {Operator.add, Operator.subtract, Operator.multiply},
  allowedModes: {
    ProblemMode.findResult,
    ProblemMode.findMissing,
    ProblemMode.compare,
  },
  maxOperand: 100,
  maxResult: 10000,
);

void expectCompareConsistent(MathProblem p) {
  expect(p.mode, ProblemMode.compare, reason: '题目不是 compare 模式');
  expect(p.compareRelation, isNotNull);
  expect(p.compareTarget, isNotNull);

  final lhs = evalExpr(p.operands, p.operators);
  expect(lhs, isNotNull, reason: '表达式求值失败：${p.problemText}');
  final target = p.compareTarget!.asFraction;
  final actual = relationOf(lhs!, target);
  expect(
    actual,
    p.compareRelation!.symbol,
    reason:
        '比较关系不一致：${p.problemText}，表达式值=$lhs，target=$target，'
        '实际关系=$actual，声明=${p.compareRelation!.symbol}',
  );
}

void main() {
  group('toCompare 单元行为（BaseGenerator）', () {
    test('findMissing 源题以表达式值为比较基准', () {
      // x + 38 = 63，x = 25（result=缺失项答案，expressionResult=表达式值）
      final src = MathProblem(
        operands: [NumberValue.fromInt(25), NumberValue.fromInt(38)],
        operators: [Operator.add],
        result: NumberValue.fromInt(25),
        mode: ProblemMode.findMissing,
        grade: 5,
        missingIndex: 0,
        expressionResult: NumberValue.fromInt(63),
      );

      for (var seed = 0; seed < 40; seed++) {
        final gen = _ConvGen(random: Random(seed));
        final cmp = gen.toCompare(src);

        // compare 题的 result 语义 = 表达式值
        expect(cmp.result.asInteger, 63);
        expectCompareConsistent(cmp);

        // target = 63 + offset，offset ∈ [-3, 3]
        final diff = cmp.compareTarget!.asFraction - src.expressionResult!.asFraction;
        expect(diff.isInteger, isTrue);
        expect(diff.asInteger, inInclusiveRange(-3, 3));
      }
    });

    test('分数源题（非整数基准）不产负 offset', () {
      // 1/2 + 1/3 = 5/6
      final src = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 2),
          NumberValue.fromFraction(1, 3),
        ],
        operators: [Operator.add],
        result: NumberValue.fromFraction(5, 6),
        mode: ProblemMode.findResult,
        grade: 5,
        resultForm: ResultForm.fraction,
      );

      for (var seed = 0; seed < 40; seed++) {
        final gen = _ConvGen(random: Random(seed));
        final cmp = gen.toCompare(src);

        expectCompareConsistent(cmp);

        // 非整数基准：target ≥ base（offset ∈ [0, 3]），不出现 greaterThan
        final base = src.result.asFraction;
        final diff = cmp.compareTarget!.asFraction - base;
        expect(diff.numerator >= 0, isTrue, reason: '分数基准出现负 offset');
        expect(
          cmp.compareRelation,
          isNot(CompareRelation.greaterThan),
          reason: '分数基准不应产出 > 关系',
        );
      }
    });

    test('offset=0 时 target 与基准精确相等（分数不截断）', () {
      final src = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 2),
          NumberValue.fromFraction(1, 3),
        ],
        operators: [Operator.add],
        result: NumberValue.fromFraction(5, 6),
        mode: ProblemMode.findResult,
        grade: 5,
        resultForm: ResultForm.fraction,
      );

      var seenEqual = false;
      for (var seed = 0; seed < 200; seed++) {
        final gen = _ConvGen(random: Random(seed));
        final cmp = gen.toCompare(src);
        final diff = cmp.compareTarget!.asFraction - src.result.asFraction;
        if (diff.numerator == 0) {
          seenEqual = true;
          expect(cmp.compareRelation, CompareRelation.equal);
          // 精确分数相等，而非 asInteger 截断后的 0 == 0
          expect(cmp.compareTarget!.asFraction, src.result.asFraction);
        }
      }
      expect(seenEqual, isTrue, reason: '200 个种子中应出现 offset=0 的等式比较');
    });
  });

  group('compare 批量生成正确性（MathEngine）', () {
    // 覆盖整数、小数、分数、负数、findMissing（简易方程）源题
    const specs = [
      (2, '上'),
      (2, '下'),
      (4, '下'),
      (5, '上'),
      (6, '上'),
      (6, '下'),
    ];

    for (final (grade, semester) in specs) {
      test('$grade年级$semester学期 compare 题关系一致', () {
        for (var seed = 0; seed < 60; seed++) {
          final p = MathEngine.generate(
            grade: grade,
            semester: semester,
            mode: ProblemMode.compare,
            random: Random(seed * 31 + 7),
          );
          // 模式转换可能回退（如 2 下余数生成器不兼容），只校验成功转换的题
          if (p.mode != ProblemMode.compare) continue;
          expectCompareConsistent(p);
        }
      });
    }

    test('六上 compare 题成功转换率大于 0（含分数/方程源题）', () {
      var compareCount = 0;
      for (var seed = 0; seed < 60; seed++) {
        final p = MathEngine.generate(
          grade: 6,
          semester: '上',
          mode: ProblemMode.compare,
          random: Random(seed * 31 + 7),
        );
        if (p.mode == ProblemMode.compare) compareCount++;
      }
      expect(compareCount, greaterThan(0));
    });
  });
}
