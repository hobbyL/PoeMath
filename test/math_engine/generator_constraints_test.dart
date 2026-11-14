import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/generators/addition_subtraction_gen.dart';
import 'package:poemath/math_engine/generators/multi_digit_mul_div_gen.dart';
import 'package:poemath/math_engine/generators/negative_number_gen.dart';
import 'package:poemath/math_engine/models/grade_config.dart';
import 'package:poemath/math_engine/models/math_problem.dart';

void main() {
  test('无解加法约束返回可处理的错误，不能递归耗尽调用栈', () {
    final generator = AdditionSubtractionGen(
      const GradeConfig(
        grade: 1,
        semester: '上',
        label: '自有无解范围',
        allowedOperators: {Operator.add},
        allowedModes: {ProblemMode.findResult},
        minOperand: 5,
        maxOperand: 5,
        maxResult: 1,
      ),
      random: Random(1),
    );
    expect(generator.generate, throwsStateError);
  });

  test('只允许除法且范围不能整除时明确失败，不退回乘法', () {
    final generator = MultiDigitMulDivGen(
      const GradeConfig(
        grade: 3,
        semester: '上',
        label: '自有只除法范围',
        allowedOperators: {Operator.divide},
        allowedModes: {ProblemMode.findResult},
        maxOperand: 3,
        maxDividend: 3,
        maxResult: 10,
      ),
      random: Random(2),
    );
    expect(generator.generate, throwsStateError);
  });

  for (final operator in [Operator.multiply, Operator.divide]) {
    test('${operator.name} 结果上限无解时明确失败', () {
      final generator = MultiDigitMulDivGen(
        GradeConfig(
          grade: 3,
          semester: '上',
          label: '自有结果上限',
          allowedOperators: {operator},
          allowedModes: {ProblemMode.findResult},
          maxOperand: 20,
          maxMultiplier: 20,
          maxDividend: 20,
          maxResult: 1,
        ),
        random: Random(3),
      );
      expect(generator.generate, throwsStateError);
    });
  }

  test('负数只生成已允许运算，结果绝对值遵守本课上限', () {
    final generator = NegativeNumberGen(
      const GradeConfig(
        grade: 6,
        semester: '下',
        label: '自有负数范围',
        allowedOperators: {Operator.subtract},
        allowedModes: {ProblemMode.findResult},
        maxOperand: 20,
        maxResult: 1,
        allowNegative: true,
      ),
      random: Random(4),
    );
    for (var index = 0; index < 100; index++) {
      final problem = generator.generate();
      expect(problem.operators, [Operator.subtract]);
      expect(problem.operands.any((value) => value.asInteger < 0), isTrue);
      expect(problem.result.asInteger.abs(), lessThanOrEqualTo(1));
      expect(
        problem.result.asInteger,
        problem.operands[0].asInteger - problem.operands[1].asInteger,
      );
    }
  });
}
