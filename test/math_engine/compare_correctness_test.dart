// test/math_engine/compare_correctness_test.dart
//
// R2（toCompare 数学正确性）专项测试：
// - 批量生成 compare 题，断言 compareRelation 与「表达式值 vs compareTarget」
//   的实际关系一致（用测试内独立实现的求值器交叉验证，不依赖
//   ExpressionEvaluator）。
// - findMissing 源题（有 expressionResult）比较基准正确。
// - 整数、小数、分数的合法比较关系等概率，目标不越过课程边界。

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
  _ConvGen({required Random random, GradeConfig config = _convConfig})
    : super(config, random: random);

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
        final diff =
            cmp.compareTarget!.asFraction - src.expressionResult!.asFraction;
        expect(diff.isInteger, isTrue);
        expect(diff.asInteger, inInclusiveRange(-3, 3));
      }
    });

    test('分数源题覆盖三种比较关系且目标非负', () {
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

      final relations = <CompareRelation>{};
      for (var seed = 0; seed < 100; seed++) {
        final gen = _ConvGen(random: Random(seed));
        final cmp = gen.toCompare(src);

        expectCompareConsistent(cmp);

        expect(cmp.compareTarget!.isNegative, isFalse);
        relations.add(cmp.compareRelation!);
      }
      expect(relations, CompareRelation.values.toSet());
    });

    for (final (label, left, right, result) in [
      (
        '整数',
        NumberValue.fromInt(25),
        NumberValue.fromInt(38),
        NumberValue.fromInt(63),
      ),
      (
        '小数',
        NumberValue.fromDouble(0.5),
        NumberValue.fromDouble(0.75),
        NumberValue.fromDouble(1.25),
      ),
      (
        '分数',
        NumberValue.fromFraction(1, 2),
        NumberValue.fromFraction(1, 3),
        NumberValue.fromFraction(5, 6),
      ),
      (
        '接近上限',
        NumberValue.fromInt(9999),
        NumberValue.fromDouble(0.9),
        NumberValue.fromDouble(9999.9),
      ),
    ]) {
      test('$label的三种合法答案接近等概率', () {
        final source = MathProblem(
          operands: [left, right],
          operators: const [Operator.add],
          result: result,
          mode: ProblemMode.findResult,
          grade: 6,
          resultForm: MathProblem.formFor(result),
        );
        final generator = _ConvGen(random: Random(20261128));
        final counts = {for (final r in CompareRelation.values) r: 0};
        for (var i = 0; i < 900; i++) {
          final problem = generator.toCompare(source);
          expectCompareConsistent(problem);
          expect(problem.compareTarget!.asDouble, inInclusiveRange(0, 10000));
          counts[problem.compareRelation!] =
              counts[problem.compareRelation!]! + 1;
        }
        // 固定种子的大样本：旧 offset 均匀抽样下等号只有约 1/7。
        expect(
          counts.values,
          everyElement(inInclusiveRange(240, 360)),
          reason: '$label答案分布：$counts',
        );
      });
    }

    test('边界只能选择合法关系，单值范围也能结束', () {
      for (final (value, maxResult, allowNegative, expected) in [
        (0, 10, false, {CompareRelation.lessThan, CompareRelation.equal}),
        (10, 10, false, {CompareRelation.greaterThan, CompareRelation.equal}),
        (-10, 10, true, {CompareRelation.lessThan, CompareRelation.equal}),
        (0, 10, true, CompareRelation.values.toSet()),
        (0, 0, false, {CompareRelation.equal}),
      ]) {
        final config = GradeConfig(
          grade: 6,
          semester: '下',
          label: '比较边界',
          allowedOperators: const {Operator.add},
          allowedModes: const {ProblemMode.compare},
          minOperand: allowNegative ? -10 : 0,
          maxOperand: 10,
          maxResult: maxResult,
          allowNegative: allowNegative,
        );
        final source = MathProblem(
          operands: [NumberValue.fromInt(value), NumberValue.fromInt(0)],
          operators: const [Operator.add],
          result: NumberValue.fromInt(value),
          mode: ProblemMode.findResult,
          grade: 6,
        );
        final generator = _ConvGen(config: config, random: Random(42));
        final seen = <CompareRelation>{};
        for (var i = 0; i < 100; i++) {
          final problem = generator.toCompare(source);
          expectCompareConsistent(problem);
          expect(
            problem.compareTarget!.asDouble,
            inInclusiveRange(allowNegative ? -maxResult : 0, maxResult),
          );
          seen.add(problem.compareRelation!);
        }
        expect(seen, expected, reason: 'value=$value max=$maxResult');
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
    const specs = [(2, '上'), (2, '下'), (4, '下'), (5, '上'), (6, '上'), (6, '下')];

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
