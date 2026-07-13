import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

void main() {
  group('各年级大量生成无异常', () {
    for (final grade in [1, 2, 3, 4, 5, 6]) {
      for (final sem in ['上', '下']) {
        final config = GradePresets.get(grade, sem);
        test('${config.label} 生成 100 道题无异常', () {
          final rng = Random(grade * 10 + (sem == '上' ? 1 : 2));
          final problems = MathEngine.generateBatch(
            grade: grade, semester: sem, count: 100, random: rng,
          );
          expect(problems.length, 100);
        });
      }
    }
  });

  group('约束验证：操作数和结果在范围内', () {
    for (final grade in [1, 2, 3, 4, 5, 6]) {
      for (final sem in ['上', '下']) {
        final config = GradePresets.get(grade, sem);
        test('${config.label} 所有题目满足约束', () {
          final rng = Random(grade * 100 + (sem == '上' ? 10 : 20));
          final problems = MathEngine.generateBatch(
            grade: grade, semester: sem, count: 50, random: rng,
          );
          for (final p in problems) {
            // 结果不超范围
            expect(
              p.result.asDouble.abs() <= config.maxResult,
              isTrue,
              reason: '${config.label}: 结果 ${p.result} 超出 ${config.maxResult}，题目: ${p.problemText}',
            );
            // 非负数模式结果非负
            if (!config.allowNegative && p.mode != ProblemMode.findMissing) {
              expect(
                p.result.asDouble >= 0,
                isTrue,
                reason: '${config.label}: 结果为负 ${p.result}，题目: ${p.problemText}',
              );
            }
          }
        });
      }
    }
  });

  group('判定验证：正确答案能判对', () {
    for (final grade in [1, 2, 3, 4, 5, 6]) {
      for (final sem in ['上', '下']) {
        final config = GradePresets.get(grade, sem);
        test('${config.label} 正确答案判定为正确', () {
          final rng = Random(grade * 1000 + (sem == '上' ? 100 : 200));
          final problems = MathEngine.generateBatch(
            grade: grade, semester: sem, count: 30, random: rng,
          );
          for (final p in problems) {
            final judgement = MathEngine.judge(p, p.answerText);
            expect(
              judgement.isCorrect,
              isTrue,
              reason: '${config.label}: 正确答案 "${p.answerText}" 判定为错误，题目: ${p.problemText}',
            );
          }
        });
      }
    }
  });

  group('题目文本完整性', () {
    for (final grade in [1, 2, 3, 4, 5, 6]) {
      for (final sem in ['上', '下']) {
        final config = GradePresets.get(grade, sem);
        test('${config.label} 题目文本和答案非空', () {
          final rng = Random(grade + (sem == '上' ? 0 : 6));
          final problems = MathEngine.generateBatch(
            grade: grade, semester: sem, count: 30, random: rng,
          );
          for (final p in problems) {
            expect(
                p.problemText.isNotEmpty, isTrue,
                reason: '${config.label}: 题目文本为空',
            );
            expect(
                p.answerText.isNotEmpty, isTrue,
                reason: '${config.label}: 答案文本为空，题目: ${p.problemText}',
            );
          }
        });
      }
    }
  });

  test('一年级上不应有进位', () {
    final rng = Random(999);
    final problems = MathEngine.generateBatch(
      grade: 1, semester: '上', count: 100, random: rng,
    );
    for (final p in problems) {
      if (p.mode == ProblemMode.findResult) {
        expect(
            p.result.asDouble <= 10, isTrue,
            reason: '一年级上结果 ${p.result} > 10，题目: ${p.problemText}',
        );
      }
    }
  });

  test('二年级下可出余数除法', () {
    final rng = Random(222);
    final problems = MathEngine.generateBatch(
      grade: 2, semester: '下', count: 100, random: rng,
    );
    final hasRemainder = problems.any(
      (p) => p.resultForm == ResultForm.withRemainder,
    );
    expect(hasRemainder, isTrue, reason: '100 道题中没有出现余数除法');
  });

  test('五年级上应有小数和乘除', () {
    final rng = Random(555);
    final problems = MathEngine.generateBatch(
      grade: 5, semester: '上', count: 100, random: rng,
    );
    final hasDecimal = problems.any(
      (p) => p.resultForm == ResultForm.decimal,
    );
    final hasMulDiv = problems.any(
      (p) => p.operators.contains(Operator.multiply) ||
          p.operators.contains(Operator.divide),
    );
    expect(hasDecimal, isTrue, reason: '五年级上 100 道题中没有小数');
    expect(hasMulDiv, isTrue, reason: '五年级上 100 道题中没有乘除法');
  });

  test('六年级上应有分数、小数、百分数、乘除', () {
    final rng = Random(666);
    final problems = MathEngine.generateBatch(
      grade: 6, semester: '上', count: 100, random: rng,
    );
    final hasFraction = problems.any(
      (p) => p.resultForm == ResultForm.fraction,
    );
    final hasDecimal = problems.any(
      (p) => p.resultForm == ResultForm.decimal,
    );
    final hasMulDiv = problems.any(
      (p) => p.operators.contains(Operator.multiply) ||
          p.operators.contains(Operator.divide),
    );
    expect(hasFraction, isTrue, reason: '六年级上 100 道题中没有分数');
    expect(hasDecimal, isTrue, reason: '六年级上 100 道题中没有小数');
    expect(hasMulDiv, isTrue, reason: '六年级上 100 道题中没有乘除法');
  });

  test('六年级下应有负数', () {
    final rng = Random(667);
    final problems = MathEngine.generateBatch(
      grade: 6, semester: '下', count: 100, random: rng,
    );
    final hasNegativeOperand = problems.any(
      (p) => p.operands.any((o) => o.isNegative),
    );
    expect(hasNegativeOperand, isTrue, reason: '六年级下 100 道题中没有负数');
  });
}
