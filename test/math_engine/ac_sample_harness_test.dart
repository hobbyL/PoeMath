import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';
import 'package:poemath/math_engine/presets/grade_presets.dart';
import 'package:poemath/math_engine/validators/constraint_checker.dart';

void main() {
  test('AC3.2 1-6年级各100题约束采样', () {
    var violations = 0;
    final modesSeen = <ProblemMode>{};

    for (var grade = 1; grade <= 6; grade++) {
      for (final semester in ['上', '下']) {
        for (var i = 0; i < 100; i++) {
          final p = MathEngine.generate(
            grade: grade,
            semester: semester,
            random: Random(grade * 1000 + semester.codeUnitAt(0) + i),
          );
          modesSeen.add(p.mode);
          final config = GradePresets.get(grade, semester);
          final v = ConstraintChecker.check(p, config);
          if (v != null) {
            violations++;
            // print first few
            if (violations <= 10) {
              // ignore: avoid_print
              print('VIO g$grade$semester ${p.problemText}=${p.answerText} $v');
            }
          }
          final j = MathEngine.judge(p, p.answerText);
          expect(j.isCorrect, isTrue, reason: '${p.problemText} ans=${p.answerText}');
        }
      }
    }
    expect(violations, 0, reason: 'constraint violations=$violations');
    // ignore: avoid_print
    print('modes seen: $modesSeen');
  }, timeout: const Timeout(Duration(minutes: 2)),);

  test('五年级上 操作数不超过 maxOperand', () {
    for (var i = 0; i < 200; i++) {
      final p = MathEngine.generate(
        grade: 5,
        semester: '上',
        random: Random(50000 + i),
      );
      final config = GradePresets.grade5a;
      for (final op in p.operands) {
        expect(
          op.asDouble,
          inInclusiveRange(config.minOperand, config.maxOperand),
          reason: '${p.problemText} operand ${op.asDouble}',
        );
      }
      expect(ConstraintChecker.check(p, config), isNull);
    }
  });

  // 显示语义一致性小样本断言（CI 常跑；全量 3000×12 由
  // `dart run tools/bracket_audit.dart` 覆盖）。
  test('显示语义求值 == result（独立参考求值器互证）', () {
    for (final config in GradePresets.all) {
      for (var i = 0; i < 30; i++) {
        final p = MathEngine.generate(
          grade: config.grade,
          semester: config.semester,
          random: Random(config.grade * 7777 + config.semester.codeUnitAt(0) * 31 + i),
        );
        // 有余数除法按验算
        if (p.resultForm == ResultForm.withRemainder) {
          final dividend = p.operands[0].asInteger;
          final divisor = p.operands[1].asInteger;
          expect(
            divisor * p.result.asInteger + (p.remainder ?? 0),
            dividend,
            reason: '${config.label}: ${p.problemText}',
          );
          continue;
        }
        final expected = _refEvaluate(p.operands, p.operators,
            bracketRange: p.bracketRange,);
        // findMissing 题 result 是缺失项答案，显示语义对应 expressionResult
        final target = (p.expressionResult ?? p.result).asFraction;
        expect(expected, isNotNull, reason: '${config.label}: ${p.problemText}');
        expect(
          expected!.numerator * target.denominator,
          target.numerator * expected.denominator,
          reason: '${config.label}: ${p.problemText} '
              '显示语义=${expected.toString()} 判分=${p.answerText}',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)),);
}

/// 测试内独立编写的参考求值器（Fraction 模型 + 从左到右扫描折叠），
/// 与生产 ExpressionEvaluator 的实现路径不同，用于互证。
Fraction? _refEvaluate(
  List<NumberValue> operands,
  List<Operator> operators, {
  (int, int)? bracketRange,
}) {
  if (operands.length != operators.length + 1) return null;
  Fraction? apply(Fraction a, Fraction b, Operator op) {
    switch (op) {
      case Operator.add:
        return a + b;
      case Operator.subtract:
        return a - b;
      case Operator.multiply:
        return a * b;
      case Operator.divide:
        if (b.numerator == 0) return null;
        return Fraction(a.numerator * b.denominator,
            a.denominator * b.numerator,);
    }
  }

  final vals = operands.map((o) => o.asFraction).toList();
  final ops = operators.toList();

  // 括号内从左到右
  final br = bracketRange;
  if (br != null) {
    var acc = vals[br.$1];
    for (var k = br.$1; k < br.$2 - 1; k++) {
      final r = apply(acc, vals[k + 1], ops[k]);
      if (r == null) return null;
      acc = r;
    }
    final folded = [
      ...vals.sublist(0, br.$1),
      acc,
      ...vals.sublist(br.$2),
    ];
    final restOps = [...ops.sublist(0, br.$1), ...ops.sublist(br.$2 - 1)];
    return _foldPriority(folded, restOps, apply);
  }
  return _foldPriority(vals, ops, apply);
}

Fraction? _foldPriority(
  List<Fraction> vals,
  List<Operator> ops,
  Fraction? Function(Fraction, Fraction, Operator) apply,
) {
  final v = List<Fraction>.from(vals);
  final o = List<Operator>.from(ops);
  // 先乘除（从左到右）：遇到就折叠并回退一位继续扫描
  for (var i = 0; i < o.length;) {
    if (o[i] == Operator.multiply || o[i] == Operator.divide) {
      final r = apply(v[i], v[i + 1], o[i]);
      if (r == null) return null;
      v[i] = r;
      v.removeAt(i + 1);
      o.removeAt(i);
    } else {
      i++;
    }
  }
  // 后加减（从左到右）
  var acc = v[0];
  for (var k = 0; k < o.length; k++) {
    final r = apply(acc, v[k + 1], o[k]);
    if (r == null) return null;
    acc = r;
  }
  return acc;
}
