import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/domain/math_textbook_grading.dart';

void main() {
  MathTextbookAnswerRule number(
    String expected, {
    MathTextbookNumberForm form = MathTextbookNumberForm.any,
    String unit = '',
    bool convert = false,
    MathTextbookAnswerKind kind = MathTextbookAnswerKind.number,
  }) => MathTextbookAnswerRule.fromJson(
    MathTextbookAnswerRule(
      kind: kind,
      expected: expected,
      form: form,
      unit: unit,
      allowUnitConversion: convert,
    ).toJson(),
  );

  test('精确有理数、多种表示和百分数不会经过浮点近似', () {
    for (final (expected, answers) in [
      ('1/2', ['0.5', '2/4', '50%', '50％']),
      ('1/3', ['2/6', '(invalid)']),
      ('3/2', ['1 1/2', '1.5', '150%']),
      ('-3/2', ['-1 1/2', '-1.5', '-150%']),
      ('0.000001', ['1/1000000', '0.0001%']),
    ]) {
      for (final answer in answers.where((value) => value != '(invalid)')) {
        expect(
          gradeMathTextbookAnswer(number(expected), answer),
          isTrue,
          reason: '$expected ← $answer',
        );
      }
    }
    expect(
      gradeMathTextbookAnswer(number('1/3'), '0.3333333333333333'),
      isFalse,
    );
    for (final input in ['1/0', 'NaN', 'Infinity', '1 2', '1/2/3', '9' * 200]) {
      expect(
        gradeMathTextbookAnswer(number('1'), input),
        isFalse,
        reason: input,
      );
    }
  });
  test('表示要求与数值等价分别校验', () {
    final fraction = number(
      '1/2',
      form: MathTextbookNumberForm.simplestFraction,
    );
    expect(gradeMathTextbookAnswer(fraction, '1/2'), isTrue);
    for (final input in ['2/4', '0.5', '50%', '1/2 cm']) {
      expect(gradeMathTextbookAnswer(fraction, input), isFalse);
    }
    final mixed = number('3/2', form: MathTextbookNumberForm.mixedNumber);
    expect(gradeMathTextbookAnswer(mixed, '1 1/2'), isTrue);
    expect(
      gradeMathTextbookAnswer(
        number('1/2', form: MathTextbookNumberForm.mixedNumber),
        '0 1/2',
      ),
      isFalse,
    );
    expect(
      gradeMathTextbookAnswer(
        number('5', form: MathTextbookNumberForm.integer),
        '5.0',
      ),
      isFalse,
    );
    expect(
      gradeMathTextbookAnswer(
        number('5', form: MathTextbookNumberForm.decimal),
        '5.0',
      ),
      isTrue,
    );
    expect(
      gradeMathTextbookAnswer(
        number('1/2', form: MathTextbookNumberForm.percentage),
        '0.5',
      ),
      isFalse,
    );
  });
  test('长度、面积、体积、时间、质量和币值按量纲精确换算', () {
    for (final (expected, unit, input) in [
      ('1', 'm', '100厘米'),
      ('1', 'm²', '10000 cm2'),
      ('1', 'm³', '1000 L'),
      ('1', '小时', '60分钟'),
      ('1', 'kg', '1000克'),
      ('1', '元', '100分'),
      ('1', '公顷', '10000平方米'),
    ]) {
      expect(
        gradeMathTextbookAnswer(
          number(expected, unit: unit, convert: true),
          input,
        ),
        isTrue,
        reason: input,
      );
    }
    for (final input in ['1', '100厘米', '1kg', '1m²']) {
      expect(gradeMathTextbookAnswer(number('1', unit: 'm'), input), isFalse);
    }
    expect(gradeMathTextbookAnswer(number('1', unit: 'm'), '1米'), isTrue);
    expect(
      gradeMathTextbookAnswer(number('1', unit: 'm', convert: true), '1平方米'),
      isFalse,
    );
  });
  test('选项集合、比较、商余及多空不会遗漏作答', () {
    final choice = MathTextbookAnswerRule.fromJson({
      'kind': 'choice',
      'options': ['甲', '乙', '丙'],
      'correctChoices': ['甲', '丙'],
    });
    expect(gradeMathTextbookAnswer(choice, jsonEncode(['丙', '甲'])), isTrue);
    for (final answer in [
      jsonEncode(['甲']),
      jsonEncode(['甲', '甲', '丙']),
      jsonEncode(['甲', '乙', '丙']),
    ]) {
      expect(gradeMathTextbookAnswer(choice, answer), isFalse);
    }
    final remainder = MathTextbookAnswerRule.fromJson({
      'kind': 'remainder',
      'expected': '3…2',
      'divisor': 5,
    });
    expect(gradeMathTextbookAnswer(remainder, '3余2'), isTrue);
    for (final answer in ['3…5', '3…', '…2', '3']) {
      expect(gradeMathTextbookAnswer(remainder, answer), isFalse);
    }
    final exercise = MathTextbookExercise(
      id: 'multi',
      title: '多空',
      blockIds: ['q'],
      knowledgePointIds: ['kp'],
      fields: [
        MathTextbookAnswerField(id: 'n', label: '数量', rule: number('2')),
        MathTextbookAnswerField(
          id: 'paper',
          label: '纸上作答',
          rule: MathTextbookAnswerRule(kind: MathTextbookAnswerKind.parent),
        ),
      ],
    );
    expect(
      gradeMathTextbookExercise(exercise, {'n': '2', 'paper': '已画图'}).result,
      MathTextbookResult.pendingParent,
    );
    expect(
      gradeMathTextbookExercise(exercise, {'n': '3', 'paper': '已画图'}).result,
      MathTextbookResult.incorrect,
    );
    expect(
      () => gradeMathTextbookExercise(exercise, {'n': '2'}),
      throwsFormatException,
    );
    expect(
      mathTextbookAnswersComplete(exercise, {'n': '2', 'paper': ' '}),
      isFalse,
    );
  });
  test('白名单算式支持括号、带分数和方程结果并拒绝无效或过量输入', () {
    final rule = number('3/2', kind: MathTextbookAnswerKind.expression);
    for (final answer in ['(1+2)/2', 'x=1.5', '3/2=1.5', '1 1/2', '1 + 1/2']) {
      expect(gradeMathTextbookAnswer(rule, answer), isTrue, reason: answer);
    }
    expect(
      gradeMathTextbookAnswer(
        number('8', kind: MathTextbookAnswerKind.expression),
        '2³',
      ),
      isTrue,
    );
    for (final answer in [
      '1 2',
      'x+1=2',
      '1/0',
      '1.5=3',
      'eval(1.5)',
      '2^9',
      '${'(' * 20}1${')' * 20}',
      '${'1+' * 130}1',
      '1' * 513,
    ]) {
      expect(evaluateMathTextbookExpression(answer), isNull, reason: answer);
    }
  });
}
