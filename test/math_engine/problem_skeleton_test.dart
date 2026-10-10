// test/math_engine/problem_skeleton_test.dart
//
// 应用题知识点定向骨架生成测试（Step 1）：
// 5 知识点 × ≥20 例带 seed，断言整数不变量、操作数边界与结果上限。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

void main() {
  group('WordProblemSkeletonGenerator.generate', () {
    test('未知知识点抛 ArgumentError', () {
      expect(
        () => WordProblemSkeletonGenerator.generate(
          grade: 3,
          semester: '上',
          topic: 'percentage',
          count: 1,
          random: Random(1),
        ),
        throwsArgumentError,
      );
    });

    test('count < 1 抛 ArgumentError', () {
      expect(
        () => WordProblemSkeletonGenerator.generate(
          grade: 3,
          semester: '上',
          topic: 'addition',
          count: 0,
          random: Random(1),
        ),
        throwsArgumentError,
      );
    });

    test('一年级上不学习乘法抛 ArgumentError', () {
      expect(
        () => WordProblemSkeletonGenerator.generate(
          grade: 1,
          semester: '上',
          topic: 'multiplication',
          count: 1,
          random: Random(1),
        ),
        throwsArgumentError,
      );
    });

    test('二年级上不学习混合运算抛 ArgumentError', () {
      expect(
        () => WordProblemSkeletonGenerator.generate(
          grade: 2,
          semester: '上',
          topic: 'mixed',
          count: 1,
          random: Random(1),
        ),
        throwsArgumentError,
      );
    });

    // ============ addition（12 学期均支持） ============
    for (final config in GradePresets.all) {
      test('addition ${config.label} × 20 例整数不变量与边界', () {
        final skeletons = WordProblemSkeletonGenerator.generate(
          grade: config.grade,
          semester: config.semester,
          topic: 'addition',
          count: 20,
          random: Random(42),
        );
        expect(skeletons, hasLength(20));
        for (final s in skeletons) {
          _assertSkeletonInvariants(s, config);
          expect(s.operators, hasLength(1));
          expect(s.operators.first, Operator.add);
          // 结果 = 两操作数之和（独立复算）
          expect(s.answer, s.operands[0] + s.operands[1]);
        }
      });
    }

    // ============ subtraction ============
    for (final config in GradePresets.all) {
      test('subtraction ${config.label} × 20 例整数不变量与边界', () {
        final skeletons = WordProblemSkeletonGenerator.generate(
          grade: config.grade,
          semester: config.semester,
          topic: 'subtraction',
          count: 20,
          random: Random(7),
        );
        expect(skeletons, hasLength(20));
        for (final s in skeletons) {
          _assertSkeletonInvariants(s, config);
          expect(s.operators, hasLength(1));
          expect(s.operators.first, Operator.subtract);
          expect(s.answer, s.operands[0] - s.operands[1]);
          // 减法结果非负（应用题情境语义要求）
          expect(s.answer, greaterThanOrEqualTo(0));
        }
      });
    }

    // ============ multiplication（学期允许乘法时） ============
    for (final config in GradePresets.all
        .where((c) => c.allowedOperators.contains(Operator.multiply))) {
      test('multiplication ${config.label} × 20 例整数不变量与边界', () {
        final skeletons = WordProblemSkeletonGenerator.generate(
          grade: config.grade,
          semester: config.semester,
          topic: 'multiplication',
          count: 20,
          random: Random(11),
        );
        expect(skeletons, hasLength(20));
        for (final s in skeletons) {
          _assertSkeletonInvariants(s, config);
          expect(s.operators, hasLength(1));
          expect(s.operators.first, Operator.multiply);
          expect(s.answer, s.operands[0] * s.operands[1]);
        }
      });
    }

    // ============ division（2 年级下起） ============
    for (final config in GradePresets.all
        .where((c) => c.allowedOperators.contains(Operator.divide))) {
      test('division ${config.label} × 20 例整除不变量', () {
        final skeletons = WordProblemSkeletonGenerator.generate(
          grade: config.grade,
          semester: config.semester,
          topic: 'division',
          count: 20,
          random: Random(13),
        );
        expect(skeletons, hasLength(20));
        for (final s in skeletons) {
          _assertSkeletonInvariants(s, config);
          expect(s.operators, hasLength(1));
          expect(s.operators.first, Operator.divide);
          // 整除复算
          expect(s.operands[0] % s.operands[1], 0);
          expect(s.answer, s.operands[0] ~/ s.operands[1]);
          expect(s.answer, greaterThanOrEqualTo(1));
        }
      });
    }

    // ============ mixed（3 年级起且允许乘除的学期） ============
    for (final config in GradePresets.all.where(
      (c) => c.grade >= 3 && c.allowedOperators.length >= 3,
    )) {
      test('mixed ${config.label} × 20 例 chain 无括号不变量', () {
        final skeletons = WordProblemSkeletonGenerator.generate(
          grade: config.grade,
          semester: config.semester,
          topic: 'mixed',
          count: 20,
          random: Random(17),
        );
        expect(skeletons, hasLength(20));
        for (final s in skeletons) {
          _assertSkeletonInvariants(s, config);
          // chain：2-3 步运算
          expect(s.operators.length, inInclusiveRange(2, 3));
          // 独立参考求值（先乘除后加减、同级从左到右）必须等于答案
          expect(_foldByPriority(s.operands, s.operators), s.answer);
        }
      });
    }

    test('unitHint 全部来自单位池', () {
      final skeletons = WordProblemSkeletonGenerator.generate(
        grade: 3,
        semester: '上',
        topic: 'addition',
        count: 20,
        random: Random(99),
      );
      for (final s in skeletons) {
        expect(kWordProblemUnitPool, contains(s.unitHint));
      }
    });

    test('同 seed 结果确定性一致', () {
      final a = WordProblemSkeletonGenerator.generate(
        grade: 4,
        semester: '上',
        topic: 'mixed',
        count: 5,
        random: Random(2024),
      );
      final b = WordProblemSkeletonGenerator.generate(
        grade: 4,
        semester: '上',
        topic: 'mixed',
        count: 5,
        random: Random(2024),
      );
      expect(a, equals(b));
    });
  });

  group('WordProblemSkeletonGenerator.availableTopics / isTopicAvailable', () {
    test('二年级上：加/减/乘，隐藏除法与混合运算', () {
      expect(
        WordProblemSkeletonGenerator.availableTopics(grade: 2, semester: '上'),
        const [
          WordProblemTopic.addition,
          WordProblemTopic.subtraction,
          WordProblemTopic.multiplication,
        ],
      );
    });

    test('二年级下：出现除法，仍无混合运算', () {
      final topics = WordProblemSkeletonGenerator.availableTopics(
        grade: 2,
        semester: '下',
      );
      expect(topics, contains(WordProblemTopic.division));
      expect(topics, isNot(contains(WordProblemTopic.mixed)));
    });

    test('三年级上：五个知识点全部可用（含混合运算）', () {
      expect(
        WordProblemSkeletonGenerator.availableTopics(grade: 3, semester: '上'),
        WordProblemTopic.values,
      );
    });

    test('四年级下 / 五年级下：仅加减（小数 / 分数加减学期）', () {
      const addSub = [WordProblemTopic.addition, WordProblemTopic.subtraction];
      expect(
        WordProblemSkeletonGenerator.availableTopics(grade: 4, semester: '下'),
        addSub,
      );
      expect(
        WordProblemSkeletonGenerator.availableTopics(grade: 5, semester: '下'),
        addSub,
      );
    });

    test('可用列表恒非空且保持 WordProblemTopic.values 顺序', () {
      for (final config in GradePresets.all) {
        final topics = WordProblemSkeletonGenerator.availableTopics(
          grade: config.grade,
          semester: config.semester,
        );
        expect(topics, isNotEmpty, reason: '${config.label} 可用知识点不应为空');
        final ordered =
            WordProblemTopic.values.where(topics.contains).toList();
        expect(topics, ordered, reason: '${config.label} 顺序应与枚举一致');
      }
    });

    test('isTopicAvailable 与 generate 守卫一致：不可用必抛 ArgumentError、可用必能生成',
        () {
      for (final config in GradePresets.all) {
        for (final topic in WordProblemTopic.values) {
          final available =
              WordProblemSkeletonGenerator.isTopicAvailable(config, topic);
          if (available) {
            final skeletons = WordProblemSkeletonGenerator.generate(
              grade: config.grade,
              semester: config.semester,
              topic: topic.name,
              count: 1,
              random: Random(2026),
            );
            expect(
              skeletons,
              hasLength(1),
              reason: '${config.label} ${topic.label} 判定可用却生成失败',
            );
          } else {
            expect(
              () => WordProblemSkeletonGenerator.generate(
                grade: config.grade,
                semester: config.semester,
                topic: topic.name,
                count: 1,
                random: Random(2026),
              ),
              throwsArgumentError,
              reason: '${config.label} ${topic.label} 判定不可用却未抛 ArgumentError',
            );
          }
        }
      }
    });
  });
}

/// 骨架核心不变量：操作数/答案非负整数、答案 ≤ maxResult、
/// 操作数 ≤ maxOperand、ExpressionEvaluator 精确求值 == 答案。
void _assertSkeletonInvariants(
  ProblemSkeleton skeleton,
  GradeConfig config,
) {
  // 全操作数非负整数
  for (final operand in skeleton.operands) {
    expect(operand, greaterThanOrEqualTo(0));
    expect(operand, lessThanOrEqualTo(config.maxOperand),
        reason: '操作数 $operand 超出学期上限 ${config.maxOperand}',);
  }
  // 答案非负整数且 ≤ maxResult
  expect(skeleton.answer, greaterThanOrEqualTo(0));
  expect(skeleton.answer, lessThanOrEqualTo(config.maxResult),
      reason: '答案 ${skeleton.answer} 超出学期上限 ${config.maxResult}',);
  // 难度 1-5
  expect(skeleton.difficulty, inInclusiveRange(1, 5));
  // 运算符序列长度 = 操作数 - 1
  expect(skeleton.operators.length, skeleton.operands.length - 1);
  // 权威求值器复算 == 既定答案
  final operands = skeleton.operands
      .map((v) => NumberValue.fromInt(v))
      .toList();
  final evaluated = ExpressionEvaluator.evaluate(
    operands,
    skeleton.operators,
  );
  expect(evaluated, isNotNull, reason: '求值失败: ${skeleton.expressionText}');
  expect(evaluated!.isInteger, isTrue, reason: '结果非整数');
  expect(evaluated.asInteger, skeleton.answer,
      reason: '求值与答案不一致: ${skeleton.expressionText}',);
}

/// 测试内独立编写的参考求值（先乘除后加减、同级从左到右）。
int _foldByPriority(List<int> operands, List<Operator> operators) {
  final vals = List<int>.from(operands);
  final ops = List<Operator>.from(operators);
  var i = 0;
  while (i < ops.length) {
    if (ops[i] == Operator.multiply || ops[i] == Operator.divide) {
      vals[i] = ops[i] == Operator.multiply
          ? vals[i] * vals[i + 1]
          : vals[i] ~/ vals[i + 1];
      vals.removeAt(i + 1);
      ops.removeAt(i);
    } else {
      i++;
    }
  }
  var result = vals[0];
  for (var k = 0; k < ops.length; k++) {
    result = ops[k] == Operator.add
        ? result + vals[k + 1]
        : result - vals[k + 1];
  }
  return result;
}
