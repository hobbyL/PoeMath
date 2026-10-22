import 'models/math_problem.dart';
import 'models/difficulty_level.dart';
import 'models/number_value.dart';
import 'models/problem_skeleton.dart';
import 'models/word_problem_plan.dart';
import 'validators/constraint_checker.dart';
import 'validators/expression_evaluator.dart';
import 'word_problem_catalog.dart';
import 'word_problem_skeleton.dart';

/// 关系的数量绑定和依赖步骤只有此处生成，渲染/存储共用。
class WordProblemPlanRules {
  const WordProblemPlanRules._();

  static List<WordProblemRelation> relationsFor(List<Operator> operators) {
    if (operators.length == 1) {
      return switch (operators.single) {
        Operator.add => [
            WordProblemRelation.merge,
            WordProblemRelation.increase,
            WordProblemRelation.more,
            WordProblemRelation.restoreInitial,
            WordProblemRelation.inverseLess,
          ],
        Operator.subtract => [
            WordProblemRelation.decrease,
            WordProblemRelation.less,
            WordProblemRelation.difference,
            WordProblemRelation.findAdded,
            WordProblemRelation.inverseMore,
          ],
        Operator.multiply => [WordProblemRelation.equalGroups],
        Operator.divide => [
            WordProblemRelation.equalShare,
            WordProblemRelation.groupCount,
          ],
      };
    }
    if (operators.length != 2 ||
        ![Operator.add, Operator.subtract].contains(operators.first)) {
      return [];
    }
    return [
      switch (operators.last) {
        Operator.add || Operator.subtract => WordProblemRelation.sequential,
        Operator.multiply => WordProblemRelation.groupedChange,
        Operator.divide => WordProblemRelation.sharedChange,
      },
    ];
  }

  static bool isInverse(WordProblemRelation relation) => switch (relation) {
        WordProblemRelation.restoreInitial ||
        WordProblemRelation.findAdded ||
        WordProblemRelation.inverseMore ||
        WordProblemRelation.inverseLess =>
          true,
        _ => false,
      };

  static String answerUnit(
    WordProblemRelation relation,
    WordProblemScene scene,
  ) =>
      relation == WordProblemRelation.groupCount ? scene.group : scene.unit;

  /// 生成、确认和恢复共用学期合同，避免正确题意挂到错误知识点。
  static WordProblemValidationResult validateContext(
    WordProblemPlan plan, {
    required int grade,
    required String semester,
    required String topic,
  }) {
    final structural = validate(plan);
    if (!structural.canSave) return structural;
    final issues = <WordProblemIssue>[];
    void fail(String message) =>
        issues.add(WordProblemIssue('curriculum', message, field: 'topic'));
    final parsed = WordProblemTopic.tryParse(topic);
    if (grade < 1 ||
        grade > 6 ||
        !['上', '下'].contains(semester) ||
        parsed == null) {
      fail('年级、学期或知识点无效');
    } else {
      final config = WordProblemSkeletonGenerator.configuration(
        grade: grade,
        semester: semester,
      );
      final skeleton = plan.skeleton;
      if (grade == 2 && skeleton.operators.length == 2 && plan.version < 2) {
        fail('二年级两步题需要新版题意快照');
      }
      final expectedOperator = switch (parsed) {
        WordProblemTopic.addition => Operator.add,
        WordProblemTopic.subtraction => Operator.subtract,
        WordProblemTopic.multiplication => Operator.multiply,
        WordProblemTopic.division => Operator.divide,
        WordProblemTopic.mixed => null,
      };
      // 存储校验依据实际课程结构，不依赖家长之后可能修改的难度设置。
      if (!WordProblemSkeletonGenerator.isTopicAvailable(
            config,
            parsed,
            difficulty: DifficultyLevel.hard,
          ) ||
          skeleton.operators
              .any((op) => !config.allowedOperators.contains(op)) ||
          (expectedOperator == null
              ? skeleton.operators.length != 2
              : skeleton.operators.length != 1 ||
                  skeleton.operators.single != expectedOperator)) {
        fail('数量关系与本学期知识点不一致');
      }
      final violation = ConstraintChecker.check(
        MathProblem(
          operands: skeleton.operands.map(NumberValue.fromInt).toList(),
          operators: skeleton.operators,
          result: NumberValue.fromInt(skeleton.answer),
          mode: parsed == WordProblemTopic.mixed
              ? ProblemMode.chain
              : ProblemMode.findResult,
          grade: grade,
          semester: semester,
          difficulty: skeleton.difficulty,
        ),
        config,
      );
      if (violation != null) fail(violation);
      if (grade == 2) {
        final quantitiesById = {
          for (final q in quantities(plan)) q.id: q.value,
        };
        for (final step in steps(plan)) {
          final a = quantitiesById[step.inputs[0]]!;
          final b = quantitiesById[step.inputs[1]]!;
          if (step.value > config.maxResult) fail('中间数量超出本学期范围');
          if (step.operator == Operator.multiply &&
              (a > config.maxMultiplier ||
                  b > config.maxMultiplier ||
                  b > (grade == 2 || semester == '上' ? 9 : 99))) {
            fail('乘法因数超出本学期范围');
          }
          if (step.operator == Operator.divide &&
              (a > config.maxDividend ||
                  b > (grade == 2 || semester == '上' ? 9 : 99) ||
                  grade == 2 && step.value > 9)) {
            fail('除法数量超出本学期范围');
          }
          if (step.operator == Operator.add &&
                  !config.allowCarry &&
                  _requiresRegrouping(a, b, subtract: false) ||
              step.operator == Operator.subtract &&
                  !config.allowBorrow &&
                  _requiresRegrouping(a, b, subtract: true)) {
            fail('本学期尚未学习进退位');
          }
        }
      }
      if (skeleton.operators.length == 1) {
        final a = skeleton.operands[0], b = skeleton.operands[1];
        if (expectedOperator == Operator.multiply &&
            (a > config.maxMultiplier ||
                b > config.maxMultiplier ||
                b > (grade == 2 || semester == '上' ? 9 : 99))) {
          fail('乘法因数超出本学期范围');
        }
        if (expectedOperator == Operator.divide &&
            (a > config.maxDividend ||
                b > (grade == 2 || semester == '上' ? 9 : 99) ||
                grade == 2 && skeleton.answer > 9)) {
          fail('除法数量超出本学期范围');
        }
        if (expectedOperator == Operator.add &&
                !config.allowCarry &&
                _requiresRegrouping(a, b, subtract: false) ||
            expectedOperator == Operator.subtract &&
                !config.allowBorrow &&
                _requiresRegrouping(a, b, subtract: true)) {
          fail('本学期尚未学习进退位');
        }
      }
    }
    return WordProblemValidationResult(
      issues.isEmpty
          ? WordProblemValidationStatus.verified
          : WordProblemValidationStatus.rejected,
      issues,
    );
  }

  static bool _requiresRegrouping(int a, int b, {required bool subtract}) {
    while (a > 0 || b > 0) {
      if (subtract ? a % 10 < b % 10 : a % 10 + b % 10 >= 10) return true;
      a ~/= 10;
      b ~/= 10;
    }
    return false;
  }

  static WordProblemValidationResult validate(WordProblemPlan plan) {
    final issues = <WordProblemIssue>[];
    void fail(String code, String message, String field) =>
        issues.add(WordProblemIssue(code, message, field: field));
    final skeleton = plan.skeleton;
    if (plan.version < 1 ||
        plan.version > 2 ||
        isInverse(plan.relation) && plan.version < 2) {
      fail('version', '题目计划版本无效', 'planVersion');
    }
    final scene = WordProblemCatalog.find(plan.sceneId);
    if (scene == null ||
        !WordProblemCatalog.forRelation(plan.relation).contains(scene)) {
      fail('scene', '情境素材与数量关系不适配', 'sceneId');
    }
    if (!WordProblemCatalog.variantIds.contains(plan.variantId)) {
      fail('variant', '题目句式无效', 'variantId');
    }
    if (!relationsFor(skeleton.operators).contains(plan.relation) ||
        skeleton.operands.length != skeleton.operators.length + 1) {
      fail('relation', '数量关系与算式结构不一致', 'relation');
    }
    if (skeleton.operands.any((n) => n < 0) || skeleton.answer < 0) {
      fail('negative', '题目数量不能为负数', 'operands');
    }
    if (scene != null &&
        skeleton.unitHint != answerUnit(plan.relation, scene)) {
      fail('unit', '答案单位与所求数量不一致', 'unit');
    }
    if (skeleton.difficulty < 1 || skeleton.difficulty > 5) {
      fail('difficulty', '题目难度无效', 'difficulty');
    }
    final trace = ExpressionEvaluator.evaluateWithSteps(
      skeleton.operands.map(NumberValue.fromInt).toList(),
      skeleton.operators,
    );
    if (trace == null ||
        !trace.value.isInteger ||
        trace.value.asInteger != skeleton.answer) {
      fail('answer', '答案与本地计算不一致', 'answer');
    } else if (trace.steps
        .any((step) => !step.value.isInteger || step.value.numerator < 0)) {
      fail('event', '分配须整除，增减过程中数量不能为负', 'steps');
    }
    if (skeleton.operands.length == 2 &&
        skeleton.operators.length == 1 &&
        (plan.relation == WordProblemRelation.equalGroups &&
                skeleton.operands.last <= 0 ||
            plan.relation == WordProblemRelation.equalShare &&
                skeleton.operands.last <= 0 ||
            plan.relation == WordProblemRelation.groupCount &&
                skeleton.operands.last <= 0)) {
      fail('groups', '份数或每份数量必须大于零', 'operands');
    }
    if (plan.relation == WordProblemRelation.groupedChange &&
        skeleton.operands.length == 3 &&
        skeleton.operands.last <= 0) {
      fail('groups', '份数必须大于零', 'operands');
    }
    return WordProblemValidationResult(
      issues.isEmpty
          ? WordProblemValidationStatus.verified
          : WordProblemValidationStatus.rejected,
      issues,
    );
  }

  static List<WordProblemQuantity> quantities(WordProblemPlan plan) {
    final scene = WordProblemCatalog.find(plan.sceneId)!;
    final values = plan.skeleton.operands;
    final relation = plan.relation;
    final roles = switch (relation) {
      WordProblemRelation.merge => ['firstBatch', 'secondBatch'],
      WordProblemRelation.increase => ['initial', 'added'],
      WordProblemRelation.decrease => ['initial', 'removed'],
      WordProblemRelation.more || WordProblemRelation.less => [
          'reference',
          'difference',
        ],
      WordProblemRelation.difference => ['larger', 'smaller'],
      WordProblemRelation.restoreInitial => ['remaining', 'removed'],
      WordProblemRelation.findAdded => ['final', 'initial'],
      WordProblemRelation.inverseMore => ['larger', 'difference'],
      WordProblemRelation.inverseLess => ['smaller', 'difference'],
      WordProblemRelation.equalGroups => ['perGroup', 'groupCount'],
      WordProblemRelation.equalShare => ['total', 'groupCount'],
      WordProblemRelation.groupCount => ['total', 'perGroup'],
      WordProblemRelation.sequential => [
          'initial',
          'firstChange',
          'secondChange',
        ],
      WordProblemRelation.groupedChange => [
          'initial',
          'perGroup',
          'groupCount',
        ],
      WordProblemRelation.sharedChange => [
          'initial',
          'sharedTotal',
          'groupCount',
        ],
    };
    final groupUnit = switch (relation) {
      WordProblemRelation.equalShare => '组',
      WordProblemRelation.sharedChange => '份',
      _ => scene.group,
    };
    final quantities = <WordProblemQuantity>[];
    for (var i = 0; i < values.length; i++) {
      final isGroups = roles[i] == 'groupCount';
      quantities.add(
        WordProblemQuantity(
          id: 'q$i',
          role: roles[i],
          entity: isGroups ? 'groups' : scene.id,
          unit: isGroups ? groupUnit : scene.unit,
          perUnit: roles[i] == 'perGroup' ? groupUnit : null,
          value: values[i],
        ),
      );
    }
    for (final step in steps(plan)) {
      quantities.add(
        WordProblemQuantity(
          id: step.output,
          role:
              step.output == plan.targetQuantityId ? 'target' : 'intermediate',
          entity:
              relation == WordProblemRelation.groupCount ? 'groups' : scene.id,
          unit: step.output == plan.targetQuantityId
              ? plan.skeleton.unitHint
              : scene.unit,
          perUnit: (step.output == plan.targetQuantityId &&
                      relation == WordProblemRelation.equalShare ||
                  step.output == 'intermediate' &&
                      relation == WordProblemRelation.sharedChange)
              ? groupUnit
              : null,
          value: step.value,
          known: false,
        ),
      );
    }
    return List.unmodifiable(quantities);
  }

  static List<WordProblemPlanStep> steps(WordProblemPlan plan) {
    final skeleton = plan.skeleton;
    if (skeleton.operators.length == 1) {
      return [
        WordProblemPlanStep(
          inputs: ['q0', 'q1'],
          output: 'target',
          operator: skeleton.operators.single,
          value: skeleton.answer,
        ),
      ];
    }
    final highPriority = plan.relation == WordProblemRelation.groupedChange ||
        plan.relation == WordProblemRelation.sharedChange;
    final firstInputs = highPriority ? ['q1', 'q2'] : ['q0', 'q1'];
    final firstOp =
        highPriority ? skeleton.operators.last : skeleton.operators.first;
    final values = skeleton.operands;
    final firstValue = ExpressionEvaluator.evaluate(
      (highPriority ? values.sublist(1) : values.sublist(0, 2))
          .map(NumberValue.fromInt)
          .toList(),
      [firstOp],
    )!
        .asInteger;
    return [
      WordProblemPlanStep(
        inputs: firstInputs,
        output: 'intermediate',
        operator: firstOp,
        value: firstValue,
      ),
      WordProblemPlanStep(
        inputs: highPriority ? ['q0', 'intermediate'] : ['intermediate', 'q2'],
        output: 'target',
        operator:
            highPriority ? skeleton.operators.first : skeleton.operators.last,
        value: skeleton.answer,
      ),
    ];
  }
}
