// test/features/math/word_problem/word_problem_validator_test.dart
//
// 应用题草稿四重校验器测试：数字一致性、语义一致、数学正确、形态约束。
// 全部正反用例（null = 通过，String = 违规原因）。

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/features/math/word_problem/word_problem_validator.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

LlmWordProblemDraft _draft({
  int index = 1,
  required String text,
  String unit = '支',
  String explanation = '',
}) =>
    LlmWordProblemDraft(
      index: index,
      text: text,
      unit: unit,
      explanation: explanation,
    );

void main() {
  // 骨架：12 + 4 = 16，单位「支」。
  const additionSkeleton = ProblemSkeleton(
    operands: [12, 4],
    operators: [Operator.add],
    answer: 16,
    unitHint: '支',
    difficulty: 1,
  );

  // 骨架：20 - 8 = 12，单位「个」。
  const subtractionSkeleton = ProblemSkeleton(
    operands: [20, 8],
    operators: [Operator.subtract],
    answer: 12,
    unitHint: '个',
    difficulty: 1,
  );

  // 骨架：6 × 7 = 42，单位「朵」。
  const multiplicationSkeleton = ProblemSkeleton(
    operands: [6, 7],
    operators: [Operator.multiply],
    answer: 42,
    unitHint: '朵',
    difficulty: 1,
  );

  // 骨架：36 ÷ 4 = 9，单位「瓶」。
  const divisionSkeleton = ProblemSkeleton(
    operands: [36, 4],
    operators: [Operator.divide],
    answer: 9,
    unitHint: '瓶',
    difficulty: 1,
  );

  group('正用例（返回 null = 通过）', () {
    test('加法题面通过', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '小明有12支铅笔，妈妈又买了4支，小明现在有多少支铅笔？',
          explanation: '把12支和4支合起来，是16支。',
        ),
        skeleton: additionSkeleton,
      );
      expect(error, isNull);
    });

    test('减法题面通过', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '树上原来有20个苹果，摘走了8个，还剩多少个苹果？',
          unit: '个',
          explanation: '从20个里去掉8个，还剩12个。',
        ),
        skeleton: subtractionSkeleton,
      );
      expect(error, isNull);
    });

    test('乘法题面通过', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '每朵花有6片花瓣，这样的7朵花一共有多少片花瓣？',
          unit: '朵',
          explanation: '6片乘7等于42片。',
        ),
        skeleton: multiplicationSkeleton,
      );
      expect(error, isNull);
    });

    test('除法题面通过', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '36瓶水平均分给4个小组，每组分到多少瓶水？',
          unit: '瓶',
          explanation: '36除以4等于9瓶。',
        ),
        skeleton: divisionSkeleton,
      );
      expect(error, isNull);
    });

    test('讲解引用答案与操作数均通过', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '小明有12支铅笔，妈妈又买了4支，小明现在有多少支铅笔？',
          explanation: '12加4等于16。',
        ),
        skeleton: additionSkeleton,
      );
      expect(error, isNull);
    });
  });

  group('1) 数字一致性', () {
    test('题面数字与骨架不一致被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了5支，现在有多少支？'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('数字与骨架不一致'));
    });

    test('题面缺少操作数被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，现在有多少支？'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('数字与骨架不一致'));
    });

    test('题面数字重复次数不匹配被拒', () {
      // 骨架是 [12, 4]，题面出现 12 两次、4 一次。
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，同学也有12支，妈妈买了4支，共有多少？'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('数字与骨架不一致'));
    });

    test('题面出现答案被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，一共有16支铅笔。'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('答案'));
    });

    test('题面包含小数数字被拒（即使乘 10 恰为操作数）', () {
      // 骨架操作数为 125：题面写「12.5」不得因 12.5×10=125 误放行。
      const decimalTrap = ProblemSkeleton(
        operands: [125, 5],
        operators: [Operator.multiply],
        answer: 625,
        unitHint: '个',
        difficulty: 1,
      );
      final error = WordProblemValidator.validate(
        draft: _draft(text: '每份12.5个，有这样的125份，共多少个？', unit: '个'),
        skeleton: decimalTrap,
      );
      expect(error, contains('非整数数字'));
    });
  });

  group('2) 语义一致', () {
    test('加法题面出现「还剩」被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，还剩多少支铅笔？'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('还剩'));
    });

    test('乘法题面出现「找回」被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '每朵花有6片花瓣，7朵花找回多少片花瓣？',
          unit: '朵',
        ),
        skeleton: multiplicationSkeleton,
      );
      expect(error, contains('找回'));
    });

    test('减法题面出现「一共」被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '树上原来有20个苹果，摘走了8个，一共多少个苹果？',
          unit: '个',
        ),
        skeleton: subtractionSkeleton,
      );
      expect(error, contains('一共'));
    });

    test('除法题面出现「总共」被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '36瓶水平均分给4个小组，总共每组分多少瓶水？',
          unit: '瓶',
        ),
        skeleton: divisionSkeleton,
      );
      expect(error, contains('总共'));
    });
  });

  group('3) 数学正确（骨架防御性复算）', () {
    test('答案与算式求值不一致被拒', () {
      const tampered = ProblemSkeleton(
        operands: [12, 4],
        operators: [Operator.add],
        answer: 17, // 被篡改的错误答案
        unitHint: '支',
        difficulty: 1,
      );
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，现在有多少支？'),
        skeleton: tampered,
      );
      expect(error, contains('求值与答案不一致'));
    });

    test('除零骨架被拒', () {
      const tampered = ProblemSkeleton(
        operands: [12, 0],
        operators: [Operator.divide],
        answer: 6,
        unitHint: '支',
        difficulty: 1,
      );
      final error = WordProblemValidator.validate(
        draft: _draft(text: '12支铅笔平均分给0个人，每人多少支？'),
        skeleton: tampered,
      );
      expect(error, isNotNull);
    });
  });

  group('4) 形态约束', () {
    test('题面为空被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '   '),
        skeleton: additionSkeleton,
      );
      expect(error, contains('为空'));
    });

    test('题面超过 120 字被拒', () {
      final long = '小明有12支铅笔，' * 20; // 140 字，含数字 12 × 20 次
      final error = WordProblemValidator.validate(
        draft: _draft(text: long),
        skeleton: additionSkeleton,
      );
      expect(error, contains('120'));
    });

    test('题面包含运算符号被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，即 12+4，现在有多少支？'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('运算符号'));
    });

    test('题面含 ASCII 减号算式「12 - 4」被拒（V1a）', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '树上原来有20个苹果，摘走了8个，算式是 12 - 4，还剩几个？',
          unit: '个',
        ),
        skeleton: subtractionSkeleton,
      );
      expect(error, contains('运算符号'));
    });

    test('题面含 ASCII 星号「3 * 5」被拒（V1a）', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '每朵花有6片花瓣，即 3 * 5，这样的7朵花一共有多少片花瓣？',
          unit: '朵',
        ),
        skeleton: multiplicationSkeleton,
      );
      expect(error, contains('运算符号'));
    });

    test('题面含 ASCII 斜杠「12 / 4」被拒（V1a）', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '36瓶水平均分给4个小组，即 12 / 4，每组分到多少瓶水？',
          unit: '瓶',
        ),
        skeleton: divisionSkeleton,
      );
      expect(error, contains('运算符号'));
    });

    test('题面含全角等号「12 ＝ 4」被拒（V1a）', () {
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，即 12 ＝ 4，现在有多少支？'),
        skeleton: additionSkeleton,
      );
      expect(error, contains('运算符号'));
    });

    test('原有全角符号用例不回归（＋ － ＊ ／ × ÷）', () {
      for (final symbol in ['＋', '－', '＊', '／', '×', '÷']) {
        final error = WordProblemValidator.validate(
          draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，即 12$symbol 4，现在有多少支？'),
          skeleton: additionSkeleton,
        );
        expect(error, contains('运算符号'), reason: '符号 $symbol 应被拒绝');
      }
    });

    test('题面含全角数字（还剩８个）被拒（V1b）', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '树上原来有20个苹果，摘走了8个，还剩８个，对吗？',
          unit: '个',
        ),
        skeleton: subtractionSkeleton,
      );
      expect(error, contains('非阿拉伯数字'));
    });

    test('讲解含全角数字被拒（V1b）', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '树上原来有20个苹果，摘走了8个，还剩几个苹果？',
          unit: '个',
          explanation: '20减8等于１２个。',
        ),
        skeleton: subtractionSkeleton,
      );
      expect(error, contains('非阿拉伯数字'));
    });

    test('answer=8 非操作数、题面含「八个」被拒（V1c）', () {
      // 12 - 4 = 8：答案 8 不是操作数，汉字表述即为答案泄露。
      const skeleton = ProblemSkeleton(
        operands: [12, 4],
        operators: [Operator.subtract],
        answer: 8,
        unitHint: '个',
        difficulty: 1,
      );
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '树上原来有12个苹果，摘走了4个，是不是还剩八个？',
          unit: '个',
        ),
        skeleton: skeleton,
      );
      expect(error, contains('汉字表述'));
    });

    test('answer=8 是操作数（64÷8=8）、题面含「八」不误杀（V1c 豁免）', () {
      const skeleton = ProblemSkeleton(
        operands: [64, 8],
        operators: [Operator.divide],
        answer: 8,
        unitHint: '个',
        difficulty: 1,
      );
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '64个松果平均分给8只松鼠，八只松鼠每只分到几个松果？',
          unit: '个',
        ),
        skeleton: skeleton,
      );
      expect(error, isNull);
    });

    test('answer>10 的汉字组合表述不做检测（家长预览兜底）', () {
      // 12 + 4 = 16：题面写「十六」不触发本地检测（设计取舍）。
      final error = WordProblemValidator.validate(
        draft: _draft(text: '小明有12支铅笔，妈妈又买了4支，是不是一共有十六支？'),
        skeleton: additionSkeleton,
      );
      expect(error, isNull);
    });

    test('单位与骨架不一致被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '小明有12支铅笔，妈妈又买了4支，现在有多少支？',
          unit: '个',
        ),
        skeleton: additionSkeleton,
      );
      expect(error, contains('单位'));
    });
  });

  group('讲解数字检查', () {
    test('讲解引入新数字被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '小明有12支铅笔，妈妈又买了4支，现在有多少支？',
          explanation: '12加4等于16，再送出3支还剩13支。',
        ),
        skeleton: additionSkeleton,
      );
      expect(error, contains('新数字'));
    });

    test('讲解包含小数数字被拒', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '小明有12支铅笔，妈妈又买了4支，现在有多少支？',
          explanation: '12.5支约等于16支。',
        ),
        skeleton: additionSkeleton,
      );
      expect(error, contains('非整数数字'));
    });

    test('讲解只引用操作数与答案通过', () {
      final error = WordProblemValidator.validate(
        draft: _draft(
          text: '小明有12支铅笔，妈妈又买了4支，现在有多少支？',
          explanation: '第一步：12加4。第二步：得到16支。',
        ),
        skeleton: additionSkeleton,
      );
      expect(error, isNull);
    });
  });
}
