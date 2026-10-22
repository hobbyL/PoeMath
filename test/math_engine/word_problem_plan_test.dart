import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

WordProblemPlan plan(
  List<int> operands,
  List<Operator> operators,
  WordProblemRelation relation, {
  String scene = 'pencils',
  int? version,
}) {
  final answer = ExpressionEvaluator.evaluate(
    operands.map(NumberValue.fromInt).toList(),
    operators,
  )!
      .asInteger;
  return WordProblemPlanGenerator.withScene(
    ProblemSkeleton(
      operands: operands,
      operators: operators,
      answer: answer,
      unitHint: '支',
      difficulty: 2,
    ),
    relation,
    scene,
    version: version,
  );
}

void main() {
  test('逆向数量关系题面、所求及实际求解算式一致', () {
    final cases = [
      (
        WordProblemRelation.restoreInitial,
        [17, 18],
        Operator.add,
        '文具室用去18支铅笔后，还剩17支铅笔，原来有多少支铅笔？',
        35
      ),
      (
        WordProblemRelation.findAdded,
        [35, 17],
        Operator.subtract,
        '文具室原有17支铅笔，又添了一些后有35支铅笔，添了多少支铅笔？',
        18
      ),
      (
        WordProblemRelation.inverseMore,
        [35, 18],
        Operator.subtract,
        '小红有35支铅笔，比小明多18支，小明有多少支铅笔？',
        17
      ),
      (
        WordProblemRelation.inverseLess,
        [17, 18],
        Operator.add,
        '小红有17支铅笔，比小明少18支，小明有多少支铅笔？',
        35
      ),
    ];
    for (final c in cases) {
      final p = plan(c.$2, [c.$3], c.$1);
      final rendered = WordProblemRenderer.render(p);
      expect(rendered.text, c.$4);
      expect(p.skeleton.answer, c.$5);
      expect(
        rendered.explanation,
        contains('${c.$2[0]} ${c.$3.symbol} ${c.$2[1]} = ${c.$5}'),
      );
      final metadata =
          WordProblemMetadata(plan: p, source: WordProblemSource.localTemplate);
      expect(metadata.toJson()['planVersion'], 2);
      expect(
        WordProblemMetadata.decode(metadata.encode())!.encode(),
        metadata.encode(),
      );
    }
  });

  test('固定历史v1快照的字段、题面与解释保持兼容', () {
    const raw =
        r'''{"schemaVersion":1,"planVersion":1,"templateVersion":1,"templateId":"equalShare:standard","relation":"equalShare","sceneId":"water","variantId":"standard","source":"localTemplate","operands":[36,4],"operators":["÷"],"answer":9,"unit":"瓶","difficulty":2,"targetQuantityId":"target","quantities":[{"id":"q0","role":"total","entity":"water","unit":"瓶","perUnit":null,"value":36,"known":true},{"id":"q1","role":"groupCount","entity":"groups","unit":"组","perUnit":null,"value":4,"known":true},{"id":"target","role":"target","entity":"water","unit":"瓶","perUnit":"组","value":9,"known":false}],"steps":[{"inputs":["q0","q1"],"output":"target","operator":"÷","value":9}]}''';
    final metadata = WordProblemMetadata.decode(raw)!;
    expect(metadata.toJson(), jsonDecode(raw));
    final rendered = WordProblemRenderer.render(metadata.plan);
    expect(rendered.text, '一共有36瓶水，平均分给4个小组，每组分到多少瓶水？');
    expect(rendered.explanation, '求每组数量，用总量除以组数。36 ÷ 4 = 9。\n答：9瓶。');
    final future = metadata.toJson()..['planVersion'] = 3;
    expect(WordProblemMetadata.decode(jsonEncode(future)), isNull);
  });

  test('全部学期三档均能生成，困难加减使用逆向关系，二年级困难开放两步', () {
    for (final config in GradePresets.all) {
      for (final level in DifficultyLevel.values) {
        for (final topic in WordProblemSkeletonGenerator.availableTopics(
          grade: config.grade,
          semester: config.semester,
          difficulty: level,
        )) {
          final plans = WordProblemPlanGenerator.generate(
            grade: config.grade,
            semester: config.semester,
            difficulty: level,
            topic: topic.name,
            count: 5,
            random: Random(42),
          );
          expect(plans, hasLength(5));
          if (topic == WordProblemTopic.addition ||
              topic == WordProblemTopic.subtraction) {
            expect(
              plans
                  .where((p) => WordProblemPlanRules.isInverse(p.relation))
                  .length,
              level == DifficultyLevel.hard
                  ? 5
                  : level == DifficultyLevel.easy
                      ? 0
                      : 2,
            );
          }
          for (final p in plans) {
            final adjusted = WordProblemSkeletonGenerator.configuration(
              grade: config.grade,
              semester: config.semester,
              difficulty: level,
            );
            if (topic == WordProblemTopic.multiplication) {
              expect(
                p.skeleton.operands,
                everyElement(lessThanOrEqualTo(adjusted.maxMultiplier)),
              );
            }
            if (topic == WordProblemTopic.division) {
              expect(
                p.skeleton.operands.first,
                lessThanOrEqualTo(adjusted.maxDividend),
              );
            }

            expect(
              WordProblemPlanRules.validateContext(
                p,
                grade: config.grade,
                semester: config.semester,
                topic: topic.name,
              ).canSave,
              isTrue,
            );
            expect(
              WordProblemMetadata.decode(
                WordProblemMetadata(
                  plan: p,
                  source: WordProblemSource.localTemplate,
                ).encode(),
              ),
              isNotNull,
            );
          }
        }
      }
    }
    for (final semester in ['上', '下']) {
      expect(
        WordProblemSkeletonGenerator.availableTopics(
          grade: 2,
          semester: semester,
          difficulty: DifficultyLevel.hard,
        ),
        contains(WordProblemTopic.mixed),
      );
    }
    final valid = plan(
      [
        50,
        7,
        4,
      ],
      [
        Operator.subtract,
        Operator.multiply,
      ],
      WordProblemRelation.groupedChange,
      version: 2,
    );
    expect(valid.skeleton.answer, 22);
    expect(
      WordProblemPlanRules.validateContext(
        valid,
        grade: 2,
        semester: '上',
        topic: 'mixed',
      ).canSave,
      isTrue,
    );
    for (final invalid in [
      plan(
        [
          100,
          10,
          5,
        ],
        [
          Operator.subtract,
          Operator.multiply,
        ],
        WordProblemRelation.groupedChange,
        version: 2,
      ),
      plan(
        [
          60,
          99,
          9,
        ],
        [
          Operator.subtract,
          Operator.divide,
        ],
        WordProblemRelation.sharedChange,
        version: 2,
      ),
      plan(
        [
          9900,
          200,
          200,
        ],
        [
          Operator.add,
          Operator.subtract,
        ],
        WordProblemRelation.sequential,
        version: 2,
      ),
    ]) {
      expect(
        WordProblemPlanRules.validateContext(
          invalid,
          grade: 2,
          semester: '下',
          topic: 'mixed',
        ).canSave,
        isFalse,
      );
    }
  });

  test('课程上下文拒绝知识点错配、未学运算、超范围和未学进位', () {
    final division =
        plan([36, 4], [Operator.divide], WordProblemRelation.equalShare);
    expect(
      WordProblemPlanRules.validateContext(
        division,
        grade: 3,
        semester: '上',
        topic: 'division',
      ).canSave,
      isTrue,
    );
    expect(
      WordProblemPlanRules.validateContext(
        division,
        grade: 3,
        semester: '上',
        topic: 'addition',
      ).canSave,
      isFalse,
    );
    expect(
      WordProblemPlanRules.validateContext(
        division,
        grade: 1,
        semester: '上',
        topic: 'division',
      ).canSave,
      isFalse,
    );
    final carry = plan([8, 5], [Operator.add], WordProblemRelation.increase);
    expect(
      WordProblemPlanRules.validateContext(
        carry,
        grade: 1,
        semester: '上',
        topic: 'addition',
      ).canSave,
      isFalse,
    );
    final oversized =
        plan([1000, 2], [Operator.multiply], WordProblemRelation.equalGroups);
    expect(
      WordProblemPlanRules.validateContext(
        oversized,
        grade: 2,
        semester: '下',
        topic: 'multiplication',
      ).canSave,
      isFalse,
    );
  });

  test('平均分明确每组目标，已知一共不被错误拒绝', () {
    final p = plan(
      [36, 4],
      [Operator.divide],
      WordProblemRelation.equalShare,
      scene: 'water',
    );
    final rendered = WordProblemRenderer.render(p);
    expect(rendered.text, '一共有36瓶水，平均分给4个小组，每组分到多少瓶水？');
    expect(p.skeleton.answer, 9);
    expect(p.skeleton.unitHint, '瓶');
    final quantities = WordProblemPlanRules.quantities(p);
    expect(quantities.map((q) => q.role), ['total', 'groupCount', 'target']);
    expect(quantities.last.perUnit, '组');
    expect(rendered.explanation, contains('36 ÷ 4 = 9'));
  });

  test('购物乘法总金额、花瓣总片数、求份数各自绑定所求单位', () {
    final price = plan(
      [6, 7],
      [Operator.multiply],
      WordProblemRelation.equalGroups,
      scene: 'bookPrice',
    );
    expect(WordProblemRenderer.render(price).text, '每本图书6元，买7本图书，一共花了多少元？');
    expect(price.skeleton.unitHint, '元');
    final petals = plan(
      [6, 7],
      [Operator.multiply],
      WordProblemRelation.equalGroups,
      scene: 'petals',
    );
    expect(petals.skeleton.unitHint, '片');
    expect(
      WordProblemRenderer.render(petals).text,
      '每朵纸花有6片花瓣，7朵这样的纸花共有多少片花瓣？',
    );
    final groups = plan(
      [36, 4],
      [Operator.divide],
      WordProblemRelation.groupCount,
      scene: 'water',
    );
    expect(groups.skeleton.unitHint, '盒');
    expect(groups.skeleton.answer, 9);
    expect(WordProblemRenderer.render(groups).text, contains('能装多少盒'));
  });

  test('加減事件每步可执行，拒绝负库存和不对应的关系', () {
    final good = plan(
      [12, 4, 5],
      [Operator.add, Operator.subtract],
      WordProblemRelation.sequential,
    );
    expect(WordProblemRenderer.render(good).text, contains('添了4支铅笔，又用去5支铅笔'));
    expect(WordProblemPlanRules.steps(good).map((s) => s.value), [16, 11]);
    final bad = plan(
      [5, 6, 8],
      [Operator.subtract, Operator.add],
      WordProblemRelation.sequential,
    );
    expect(WordProblemPlanRules.validate(bad).canSave, isFalse);
    final wrong = plan([12, 4], [Operator.add], WordProblemRelation.decrease);
    expect(
      WordProblemPlanRules.validate(wrong).issues.map((i) => i.code),
      contains('relation'),
    );
  });

  test('混合题乘除优先和讲解完整计算正确', () {
    final p = plan(
      [12, 4, 5],
      [Operator.add, Operator.multiply],
      WordProblemRelation.groupedChange,
    );
    expect(p.skeleton.answer, 32);
    expect(WordProblemPlanRules.steps(p).map((s) => s.value), [20, 32]);
    expect(WordProblemRenderer.render(p).explanation, contains('12 + 20 = 32'));
    final bad = plan(
      [55, 15, 4],
      [Operator.subtract, Operator.multiply],
      WordProblemRelation.groupedChange,
    );
    expect(WordProblemPlanRules.validate(bad).canSave, isFalse);
    final shared = plan(
      [12, 36, 4],
      [Operator.add, Operator.divide],
      WordProblemRelation.sharedChange,
    );
    expect(WordProblemPlanRules.steps(shared).map((s) => s.value), [9, 21]);
    final quantities = WordProblemPlanRules.quantities(shared);
    expect(quantities[2].unit, '份');
    expect(quantities[3].perUnit, '份');
  });

  test('相同值不混淆量角色，答案0和1能生成', () {
    final zero =
        plan([5, 5], [Operator.subtract], WordProblemRelation.decrease);
    expect(
      WordProblemPlanRules.quantities(zero).map((q) => q.id),
      ['q0', 'q1', 'target'],
    );
    expect(WordProblemPlanRules.validate(zero).canSave, isTrue);
    expect(WordProblemRenderer.render(zero).explanation, contains('答：0支'));
    final one = plan([9, 8], [Operator.subtract], WordProblemRelation.decrease);
    expect(WordProblemPlanRules.validate(one).canSave, isTrue);
  });

  test('快照重建并核对角色与步骤，拒绝篡改并保留未来版本', () {
    final p = plan([12, 4], [Operator.add], WordProblemRelation.increase);
    final metadata =
        WordProblemMetadata(plan: p, source: WordProblemSource.aiScene);
    expect(
      WordProblemMetadata.decode(metadata.encode())!.encode(),
      metadata.encode(),
    );
    final tampered = metadata.toJson();
    (tampered['quantities'] as List).last['unit'] = '朵';
    expect(
      () => WordProblemMetadata.decode(jsonEncode(tampered)),
      throwsFormatException,
    );
    final future = metadata.toJson()..['schemaVersion'] = 2;
    expect(WordProblemMetadata.decode(jsonEncode(future)), isNull);
  });

  test('每个现有可用年级学期知识点有结构化模板覆盖', () {
    for (final config in GradePresets.all) {
      for (final topic in WordProblemSkeletonGenerator.availableTopics(
        grade: config.grade,
        semester: config.semester,
      )) {
        for (var seed = 0; seed < 100; seed++) {
          final p = WordProblemPlanGenerator.generate(
            grade: config.grade,
            semester: config.semester,
            topic: topic.name,
            count: 1,
            random: Random(seed),
          ).single;
          expect(
            WordProblemPlanRules.validate(p).canSave,
            isTrue,
            reason: '${config.label}/${topic.name}/$seed',
          );
          expect(
            WordProblemPlanRules.validateContext(
              p,
              grade: config.grade,
              semester: config.semester,
              topic: topic.name,
            ).canSave,
            isTrue,
          );
          final quantities = WordProblemPlanRules.quantities(p);
          final known = {
            for (final q in quantities.where((q) => q.known)) q.id: q.value,
          };
          for (final step in WordProblemPlanRules.steps(p)) {
            final left = known[step.inputs[0]]!;
            final right = known[step.inputs[1]]!;
            if (step.operator == Operator.divide) {
              expect(right, greaterThan(0));
              expect(left % right, 0);
            }
            final computed = switch (step.operator) {
              Operator.add => left + right,
              Operator.subtract => left - right,
              Operator.multiply => left * right,
              Operator.divide => left ~/ right,
            };
            expect(computed, step.value);
            expect(computed, greaterThanOrEqualTo(0));
            known[step.output] = computed;
          }
          expect(known[p.targetQuantityId], p.skeleton.answer);
          expect(
            quantities.where((q) => q.role == 'target').single.known,
            isFalse,
          );
          final rendered = WordProblemRenderer.render(p);
          expect(rendered.text.length, lessThanOrEqualTo(120));
          expect(rendered.explanation.length, lessThanOrEqualTo(300));
          expect(rendered.text.endsWith('？'), isTrue);
        }
      }
    }
  });

  test('不支持混合形状有界重选，不学习的知识点仍拒绝', () {
    var calls = 0;
    expect(
      () => WordProblemPlanGenerator.generate(
        grade: 3,
        semester: '上',
        topic: 'mixed',
        count: 1,
        skeletonFactory: ({
          required grade,
          required semester,
          required topic,
          required count,
          DifficultyLevel difficulty = DifficultyLevel.medium,
        }) {
          calls++;
          return [
            const ProblemSkeleton(
              operands: [1, 2, 3, 4],
              operators: [Operator.add, Operator.add, Operator.add],
              answer: 10,
              unitHint: '个',
              difficulty: 2,
            ),
          ];
        },
      ),
      throwsStateError,
    );
    expect(calls, WordProblemPlanGenerator.maxSkeletonCallsPerProblem);
    expect(
      () => WordProblemPlanGenerator.generate(
        grade: 1,
        semester: '上',
        topic: 'division',
        count: 1,
      ),
      throwsArgumentError,
    );
  });
}
