import 'dart:math';

import 'models/problem_skeleton.dart';
import 'models/difficulty_level.dart';
import 'models/math_problem.dart';
import 'models/word_problem_plan.dart';
import 'word_problem_catalog.dart';
import 'word_problem_plan_rules.dart';
import 'word_problem_skeleton.dart';

typedef WordProblemSkeletonFactory = List<ProblemSkeleton> Function({
  required int grade,
  required String semester,
  required String topic,
  required int count,
  DifficultyLevel difficulty,
});

class WordProblemPlanGenerator {
  const WordProblemPlanGenerator._();

  static const maxSkeletonCallsPerProblem = 32;

  static List<WordProblemPlan> generate({
    required int grade,
    required String semester,
    required String topic,
    required int count,
    DifficultyLevel difficulty = DifficultyLevel.medium,
    Random? random,
    WordProblemSkeletonFactory? skeletonFactory,
  }) {
    if (grade < 1 ||
        grade > 6 ||
        !['上', '下'].contains(semester) ||
        count < 1 ||
        count > 20) {
      throw ArgumentError('年级、学期或生成数量无效');
    }
    final parsed = WordProblemTopic.tryParse(topic);
    if (parsed == null ||
        !WordProblemSkeletonGenerator.availableTopics(
          grade: grade,
          semester: semester,
          difficulty: difficulty,
        ).contains(parsed)) {
      throw ArgumentError('该学期不学习此知识点');
    }
    final r = random ?? Random();
    List<ProblemSkeleton> create(int quantity) => skeletonFactory != null
        ? skeletonFactory(
            grade: grade,
            semester: semester,
            topic: topic,
            count: quantity,
            difficulty: difficulty,
          )
        : WordProblemSkeletonGenerator.generate(
            grade: grade,
            semester: semester,
            topic: topic,
            count: quantity,
            difficulty: difficulty,
            random: r,
          );
    final initial = create(count);
    if (initial.length != count) throw StateError('题目结构生成数量不足');
    final plans = <WordProblemPlan>[];
    final used = <String>{};
    for (var i = 0; i < count; i++) {
      var candidate = initial[i];
      // 去重重选时保留初始批次分配的乘除类型。
      final mixedOperator = candidate.operators.lastOrNull;
      WordProblemPlan? plan;
      WordProblemPlan? duplicate;
      for (var attempt = 0; attempt < maxSkeletonCallsPerProblem; attempt++) {
        var relations = WordProblemPlanRules.relationsFor(candidate.operators);
        if (parsed == WordProblemTopic.mixed) {
          relations = relations
              .where(
                (relation) =>
                    relation == WordProblemRelation.groupedChange ||
                    relation == WordProblemRelation.sharedChange,
              )
              .where(
                (_) =>
                    ![Operator.multiply, Operator.divide]
                        .contains(mixedOperator) ||
                    candidate.operators.last == mixedOperator,
              )
              .toList();
        }
        final reverse =
            relations.where((r) => WordProblemPlanRules.isInverse(r)).toList();
        final direct =
            relations.where((r) => !WordProblemPlanRules.isInverse(r)).toList();
        if (difficulty == DifficultyLevel.easy) {
          relations = direct;
        } else if (reverse.isNotEmpty &&
            (difficulty == DifficultyLevel.hard || i.isOdd)) {
          relations = reverse;
        } else {
          relations = direct;
        }
        if (relations.isNotEmpty) {
          final relation = relations[r.nextInt(relations.length)];
          final scenes = WordProblemCatalog.forRelation(relation);
          final scene = scenes[r.nextInt(scenes.length)];
          final bound = withScene(
            candidate,
            relation,
            scene.id,
            version: grade == 2 && parsed == WordProblemTopic.mixed ? 2 : null,
          );
          if (WordProblemPlanRules.validateContext(
            bound,
            grade: grade,
            semester: semester,
            topic: topic,
          ).canSave) {
            final key =
                '${candidate.operands}|${candidate.operators}|$relation';
            if (used.add(key)) {
              plan = bound;
              break;
            }
            duplicate ??= bound;
          }
        }
        if (attempt + 1 < maxSkeletonCallsPerProblem) {
          candidate = create(1).single;
        }
      }
      plan ??= duplicate;
      if (plan == null) throw StateError('无法生成可执行的应用题数量关系');
      plans.add(plan);
    }
    return List.unmodifiable(plans);
  }

  static WordProblemPlan withScene(
    ProblemSkeleton skeleton,
    WordProblemRelation relation,
    String sceneId, {
    String variantId = 'standard',
    int? version,
  }) {
    final scene = WordProblemCatalog.find(sceneId);
    if (scene == null) throw ArgumentError('未知情境素材');
    return WordProblemPlan(
      skeleton: ProblemSkeleton(
        operands: skeleton.operands,
        operators: skeleton.operators,
        answer: skeleton.answer,
        unitHint: WordProblemPlanRules.answerUnit(relation, scene),
        difficulty: skeleton.difficulty,
      ),
      relation: relation,
      sceneId: sceneId,
      variantId: variantId,
      version: version,
    );
  }
}
