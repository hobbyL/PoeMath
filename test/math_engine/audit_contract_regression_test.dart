import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/generators/base_generator.dart';

class _Converter extends BaseGenerator {
  _Converter() : super(GradePresets.get(4, '上'), random: Random(14));
  @override
  MathProblem generate() => throw UnimplementedError();
}

void main() {
  test('转换括号题保留显示语义和未知项形态', () {
    final source = MathProblem(
      operands: [69, 31, 9].map(NumberValue.fromInt).toList(),
      operators: const [Operator.add, Operator.multiply],
      result: NumberValue.fromInt(900),
      bracketRange: (0, 2),
      mode: ProblemMode.withBrackets,
      grade: 4,
    );
    final converter = _Converter();
    final compare = converter.toCompare(source);
    expect(compare.problemText, contains('(69 + 31) × 9'));
    final target = compare.compareTarget!.asInteger;
    expect(
      compare.answerText,
      900 > target
          ? '>'
          : 900 < target
              ? '<'
              : '=',
    );
    final missing = converter.toFindMissing(source);
    expect(missing.bracketRange, (0, 2));
    expect(missing.problemText, contains('('));
    // Independently substitute the answer into the displayed structure.
    final values = source.operands.map((n) => n.asInteger).toList();
    values[missing.missingIndex!] = int.parse(missing.answerText);
    expect(
      (values[0] + values[1]) * values[2],
      missing.expressionResult!.asInteger,
    );
    for (final sample in [(6, '上', 3), (6, '下', 30)]) {
      final p = MathEngine.generate(
        grade: sample.$1,
        semester: sample.$2,
        mode: ProblemMode.findMissing,
        random: Random(sample.$3),
      );
      expect(p.resultForm, MathProblem.formFor(p.result));
      expect(MathEngine.judge(p, p.answerText).isCorrect, isTrue);
    }
  });

  test('零答案不接受非法输入，非有限值不抛异常', () {
    final p = MathProblem(
      operands: [NumberValue.fromInt(2), NumberValue.fromInt(2)],
      operators: const [Operator.subtract],
      result: NumberValue.fromInt(0),
      mode: ProblemMode.findResult,
      grade: 1,
    );
    for (final input in [
      '.',
      '-',
      '/',
      '1/0',
      'hello',
      'NaN',
      'Infinity',
      '0x0',
      '9223372036854775807 0/2',
      '4294967296 0/4294967296',
      '',
    ]) {
      expect(MathEngine.judge(p, input).isCorrect, isFalse, reason: input);
    }
    expect(MathEngine.judge(p, '0').isCorrect, isTrue);
    expect(MathEngine.parseAnswer('4294967296 0/4294967296'),
        NumberValue.fromInt(4294967296),);
  });

  test('精确小数判分与错题快照判分一致', () {
    expect(MathEngine.answersEquivalent('485.829', '485.83'), isFalse);
    expect(MathEngine.answersEquivalent('485.83001', '485.83'), isFalse);
    expect(MathEngine.answersEquivalent('2/4', '1/2'), isTrue);
    expect(MathEngine.answersEquivalent('0.50', '0.5'), isTrue);
    expect(MathEngine.answersEquivalent('1/0', '0'), isFalse);
    expect(MathEngine.answersEquivalent('-0 1/2', '-1/2'), isTrue);
    expect(const Fraction(-5, 3).toString(), '-1 2/3');
  });

  test('小数和负数不套整数位值讲解或口诀诊断', () {
    for (final values in [(1.9, 2.3), (-1.0, 2.0)]) {
      final a = NumberValue.fromDouble(values.$1);
      final b = NumberValue.fromDouble(values.$2);
      final p = MathProblem(
        operands: [a, b],
        operators: const [Operator.add],
        result: a + b,
        mode: ProblemMode.findResult,
        grade: 5,
      );
      expect(
        MathEngine.explain(p).map((s) => s.description).join(),
        isNot(contains('个位')),
      );
    }
    final p = MathProblem(
      operands: [NumberValue.fromDouble(1.5), NumberValue.fromDouble(2.5)],
      operators: const [Operator.multiply],
      result: NumberValue.fromDouble(3.75),
      resultForm: ResultForm.decimal,
      mode: ProblemMode.findResult,
      grade: 5,
    );
    expect(
      MathEngine.judge(p, '4').diagnosis?.category,
      isNot('multiplication_table'),
    );
  });

  test('所有学期指定模式准确兑现，目标值遵守负数约束', () {
    for (var grade = 1; grade <= 6; grade++) {
      for (final semester in ['上', '下']) {
        final config = GradePresets.get(grade, semester);
        for (final mode in config.allowedModes) {
          for (var seed = 0; seed < 60; seed++) {
            final p = MathEngine.generate(
              grade: grade,
              semester: semester,
              mode: mode,
              random: Random(seed),
            );
            expect(p.mode, mode, reason: '$grade$semester $mode $seed');
            expect(ConstraintChecker.check(p, config), isNull);
            if (!config.allowNegative) {
              expect(p.compareTarget?.isNegative ?? false, isFalse);
            }
          }
        }
      }
    }
  });

  test('退化挖空题被拒绝，不生成零分子导致任意除数都正确的题目', () {
    final problem = MathProblem(
        operands: [47, 47, 47, 72].map(NumberValue.fromInt).toList(),
        operators: const [Operator.subtract, Operator.divide, Operator.add],
        bracketRange: (0, 2),
        result: NumberValue.fromInt(47),
        expressionResult: NumberValue.fromInt(72),
        mode: ProblemMode.findMissing,
        missingIndex: 2,
        grade: 3,);
    expect(
        ConstraintChecker.check(problem, GradePresets.get(3, '下')), '未知项不唯一',);
    for (final sample in [(3, '下', 3538), (4, '上', 2301)]) {
      final generated = MathEngine.generate(
          grade: sample.$1,
          semester: sample.$2,
          mode: ProblemMode.findMissing,
          random: Random(sample.$3),);
      expect(
          ConstraintChecker.check(
              generated, GradePresets.get(sample.$1, sample.$2),),
          isNull,);
    }
  });

  test('全部年级难度只生成支持的模式，拒绝的组合可在UI预先判断', () {
    for (var grade = 1; grade <= 6; grade++) {
      for (final semester in ['上', '下']) {
        for (final difficulty in DifficultyLevel.values) {
          final modes = MathEngine.supportedModes(
              grade: grade, semester: semester, difficulty: difficulty,);
          for (final mode in ProblemMode.values) {
            if (!modes.contains(mode)) {
              expect(
                  () => MathEngine.generate(
                      grade: grade,
                      semester: semester,
                      difficulty: difficulty,
                      mode: mode,),
                  throwsArgumentError,);
              continue;
            }
            for (var seed = 0; seed < 30; seed++) {
              final p = MathEngine.generate(
                  grade: grade,
                  semester: semester,
                  difficulty: difficulty,
                  mode: mode,
                  random: Random(seed),);
              expect(p.mode, mode);
              expect(MathEngine.judge(p, p.answerText).isCorrect, isTrue);
            }
          }
        }
      }
    }
  });
}
