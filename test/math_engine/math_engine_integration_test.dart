// test/math_engine/math_engine_integration_test.dart
//
// 端到端集成测试：generate → answer → judge → diagnose → explain。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine.dart';
import 'package:poemath/math_engine/models/math_problem.dart';
import 'package:poemath/math_engine/models/number_value.dart';

void main() {
  group('MathEngine 集成测试', () {
    test('一年级上 生成 + 判定正确', () {
      final p = MathEngine.generate(
        grade: 1,
        semester: '上',
        random: Random(100),
      );
      expect(p.grade, 1);
      expect(p.result.asInteger, lessThanOrEqualTo(10));
      expect(p.result.asInteger, greaterThanOrEqualTo(0));

      // 正确答案
      final j = MathEngine.judge(p, p.answerText);
      expect(j.isCorrect, isTrue);
      expect(j.diagnosis, isNull);
      expect(j.correctSteps, isNotEmpty);
    });

    test('一年级下 生成 + 判定错误 + 诊断', () {
      final p = MathEngine.generate(
        grade: 1,
        semester: '下',
        random: Random(101),
      );

      // 故意给错误答案
      final wrongAnswer = (p.result.asInteger + 10).toString();
      final j = MathEngine.judge(p, wrongAnswer);
      expect(j.isCorrect, isFalse);
      expect(j.correctSteps, isNotEmpty);
    });

    test('二年级上 乘法范围正确', () {
      for (var i = 0; i < 20; i++) {
        final p = MathEngine.generate(
          grade: 2,
          semester: '上',
          random: Random(200 + i),
        );
        expect(p.result.asDouble.abs(), lessThanOrEqualTo(100));
      }
    });

    test('二年级下 可能出现余数', () {
      var hasRemainder = false;
      for (var i = 0; i < 50; i++) {
        final p = MathEngine.generate(
          grade: 2,
          semester: '下',
          random: Random(300 + i),
        );
        if (p.resultForm == ResultForm.withRemainder) {
          hasRemainder = true;
          // 验证余数答案格式
          expect(p.answerText, contains('…'));
          break;
        }
      }
      // 应在 50 次中出现余数题
      expect(hasRemainder, isTrue);
    });

    test('三年级 混合运算', () {
      for (var i = 0; i < 10; i++) {
        final p = MathEngine.generate(
          grade: 3,
          semester: '下',
          random: Random(400 + i),
        );
        expect(p.operands.length, greaterThanOrEqualTo(2));
      }
    });

    test('四年级下 小数运算', () {
      var hasDecimal = false;
      for (var i = 0; i < 30; i++) {
        final p = MathEngine.generate(
          grade: 4,
          semester: '下',
          random: Random(500 + i),
        );
        if (p.resultForm == ResultForm.decimal) {
          hasDecimal = true;
          break;
        }
      }
      expect(hasDecimal, isTrue);
    });

    test('五年级下 分数运算', () {
      var hasFraction = false;
      for (var i = 0; i < 30; i++) {
        final p = MathEngine.generate(
          grade: 5,
          semester: '下',
          random: Random(600 + i),
        );
        if (p.resultForm == ResultForm.fraction) {
          hasFraction = true;
          break;
        }
      }
      expect(hasFraction, isTrue);
    });

    test('六年级下 负数运算', () {
      var hasNeg = false;
      for (var i = 0; i < 30; i++) {
        final p = MathEngine.generate(
          grade: 6,
          semester: '下',
          random: Random(700 + i),
        );
        final anyNeg = p.operands.any((op) => op.isNegative);
        if (anyNeg) {
          hasNeg = true;
          break;
        }
      }
      expect(hasNeg, isTrue);
    });

    test('explain 返回非空步骤', () {
      final p = MathEngine.generate(
        grade: 1,
        semester: '上',
        random: Random(800),
      );
      final steps = MathEngine.explain(p);
      expect(steps, isNotEmpty);
    });

    test('generateBatch 批量生成', () {
      final problems = MathEngine.generateBatch(
        grade: 1,
        semester: '上',
        count: 10,
        random: Random(900),
      );
      expect(problems.length, 10);
      for (final p in problems) {
        expect(p.grade, 1);
      }
    });

    test('全流程：生成 → 正确判定 → 解释', () {
      final p = MathEngine.generate(
        grade: 2,
        semester: '上',
        random: Random(1000),
      );

      // 正确答案判定
      final j = MathEngine.judge(p, p.answerText);
      expect(j.isCorrect, isTrue);

      // 解释
      final steps = MathEngine.explain(p);
      expect(steps, isNotEmpty);
    });

    test('全流程：生成 → 错误判定 → 诊断', () {
      // 固定生成一道加法题
      final p = MathProblem(
        operands: [NumberValue.fromInt(18), NumberValue.fromInt(25)],
        operators: [Operator.add],
        result: NumberValue.fromInt(43),
        mode: ProblemMode.findResult,
        grade: 1,
      );

      // 故意少进位
      final j = MathEngine.judge(p, '33');
      expect(j.isCorrect, isFalse);
      expect(j.diagnosis, isNotNull);
      expect(j.diagnosis!.category, 'carry_omission');
      expect(j.correctSteps, isNotEmpty);
    });

    test('分数答案判定', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 3),
          NumberValue.fromFraction(1, 6),
        ],
        operators: [Operator.add],
        result: NumberValue.fromFraction(1, 2),
        mode: ProblemMode.findResult,
        grade: 5,
        resultForm: ResultForm.fraction,
      );

      final j = MathEngine.judge(p, '1/2');
      expect(j.isCorrect, isTrue);
    });

    test('比较模式判定', () {
      final p = MathProblem(
        operands: [NumberValue.fromInt(3), NumberValue.fromInt(5)],
        operators: [Operator.add],
        result: NumberValue.fromInt(8),
        mode: ProblemMode.compare,
        grade: 2,
        compareRelation: CompareRelation.greaterThan,
        compareTarget: NumberValue.fromInt(7),
      );

      final j1 = MathEngine.judge(p, '>');
      expect(j1.isCorrect, isTrue);

      final j2 = MathEngine.judge(p, '<');
      expect(j2.isCorrect, isFalse);
      expect(j2.diagnosis, isNotNull);
    });

    test('所有年级都能生成题目（无异常）', () {
      for (var grade = 1; grade <= 6; grade++) {
        for (final sem in ['上', '下']) {
          final p = MathEngine.generate(
            grade: grade,
            semester: sem,
            random: Random(grade * 100 + (sem == '上' ? 1 : 2)),
          );
          expect(p.grade, grade);
          expect(p.operands, isNotEmpty);
          expect(p.operators, isNotEmpty);

          // 每道题都应该能正确判定
          final j = MathEngine.judge(p, p.answerText);
          expect(
            j.isCorrect,
            isTrue,
            reason: '$grade$sem: ${p.problemText} = ${p.answerText}',
          );
        }
      }
    });
  });
}
