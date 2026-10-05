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

    test('假分数与带分数答案均可判对（AC5）', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 2),
          NumberValue.fromInt(1),
        ],
        operators: [Operator.add],
        result: NumberValue.fromFraction(3, 2),
        mode: ProblemMode.findResult,
        grade: 5,
        resultForm: ResultForm.fraction,
      );

      expect(MathEngine.judge(p, '3/2').isCorrect, isTrue);
      expect(MathEngine.judge(p, '1 1/2').isCorrect, isTrue);
      expect(MathEngine.judge(p, '1½').isCorrect, isFalse); // 不支持的形式
    });

    test('负带分数答案解析', () {
      final p = MathProblem(
        operands: [
          NumberValue.fromFraction(1, 2),
          NumberValue.fromInt(-2),
        ],
        operators: [Operator.add],
        result: NumberValue.fromFraction(-3, 2),
        mode: ProblemMode.findResult,
        grade: 6,
        resultForm: ResultForm.fraction,
      );

      expect(MathEngine.judge(p, '-3/2').isCorrect, isTrue);
      expect(MathEngine.judge(p, '-1 1/2').isCorrect, isTrue);
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

  group('余数题模式转换防护（R4）', () {
    test('请求 findMissing 不产出「余数 + 挖空」混合模式', () {
      for (var seed = 0; seed < 50; seed++) {
        final p = MathEngine.generate(
          grade: 2,
          semester: '下',
          mode: ProblemMode.findMissing,
          random: Random(seed * 13 + 5),
        );
        expect(
          p.resultForm == ResultForm.withRemainder &&
              p.mode != ProblemMode.findResult,
          isFalse,
          reason:
              '余数题被转成 ${p.mode.name}：${p.problemText} = ${p.answerText}',
        );
        // 转换成功或回退的题都必须可判定正确
        expect(
          MathEngine.judge(p, p.answerText).isCorrect,
          isTrue,
          reason: '${p.problemText} = ${p.answerText}',
        );
      }
    });

    test('请求 compare 不产出「余数 + 比较」混合模式', () {
      for (var seed = 0; seed < 50; seed++) {
        final p = MathEngine.generate(
          grade: 2,
          semester: '下',
          mode: ProblemMode.compare,
          random: Random(seed * 17 + 3),
        );
        expect(
          p.resultForm == ResultForm.withRemainder &&
              p.mode != ProblemMode.findResult,
          isFalse,
          reason:
              '余数题被转成 ${p.mode.name}：${p.problemText} = ${p.answerText}',
        );
      }
    });

    test('余数题 findResult 模式（商…余 输入路径）行为不变', () {
      var remainderCount = 0;
      for (var seed = 0; seed < 100; seed++) {
        final p = MathEngine.generate(
          grade: 2,
          semester: '下',
          random: Random(300 + seed),
        );
        if (p.resultForm == ResultForm.withRemainder) {
          remainderCount++;
          expect(p.mode, ProblemMode.findResult);
          expect(p.answerText, matches(RegExp(r'^\d+…\d+$')));
          expect(MathEngine.judge(p, p.answerText).isCorrect, isTrue);
        }
      }
      expect(remainderCount, greaterThan(0), reason: '二年级下应能出余数题');
    });
  });

  group('六上分数除法恢复出题（R3）', () {
    test('真分数作为除数的除法题可稳定生成且判定正确', () {
      var fractionDivCount = 0;
      for (var seed = 0; seed < 300; seed++) {
        final p = MathEngine.generate(
          grade: 6,
          semester: '上',
          random: Random(seed),
        );
        final isFractionDiv = p.resultForm == ResultForm.fraction &&
            p.operators.length == 1 &&
            p.operators.first == Operator.divide &&
            !p.operands[1].isInteger;
        if (isFractionDiv) {
          fractionDivCount++;
          // 分数除法核心考点：不再被「除数为零」误拒，且答案可判对
          expect(
            MathEngine.judge(p, p.answerText).isCorrect,
            isTrue,
            reason: '${p.problemText} = ${p.answerText}',
          );
        }
      }
      expect(
        fractionDivCount,
        greaterThan(0),
        reason: '300 个种子中应出现真分数除数的分数除法题（修复前为 0）',
      );
    });
  });
}
