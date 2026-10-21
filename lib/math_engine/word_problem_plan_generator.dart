import 'dart:math';

import 'models/problem_skeleton.dart';
import 'models/word_problem_plan.dart';
import 'word_problem_catalog.dart';
import 'word_problem_plan_rules.dart';
import 'word_problem_skeleton.dart';

typedef WordProblemSkeletonFactory = List<ProblemSkeleton> Function({
  required int grade,
  required String semester,
  required String topic,
  required int count,
});

class WordProblemPlanGenerator {
  const WordProblemPlanGenerator._();

  static const maxSkeletonCallsPerProblem = 32;

  static List<WordProblemPlan> generate({
    required int grade,
    required String semester,
    required String topic,
    required int count,
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
          )
        : WordProblemSkeletonGenerator.generate(
            grade: grade,
            semester: semester,
            topic: topic,
            count: quantity,
            random: r,
          );
    final initial = create(count);
    if (initial.length != count) throw StateError('题目结构生成数量不足');
    final plans = <WordProblemPlan>[];
    for (var i = 0; i < count; i++) {
      var candidate = initial[i];
      WordProblemPlan? plan;
      for (var attempt = 0; attempt < maxSkeletonCallsPerProblem; attempt++) {
        final relations =
            WordProblemPlanRules.relationsFor(candidate.operators);
        if (relations.isNotEmpty) {
          final relation = relations[r.nextInt(relations.length)];
          final scenes = WordProblemCatalog.forRelation(relation);
          final scene = scenes[r.nextInt(scenes.length)];
          final bound = withScene(candidate, relation, scene.id);
          if (WordProblemPlanRules.validateContext(
            bound,
            grade: grade,
            semester: semester,
            topic: topic,
          ).canSave) {
            plan = bound;
            break;
          }
        }
        if (attempt + 1 < maxSkeletonCallsPerProblem) {
          candidate = create(1).single;
        }
      }
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
    );
  }
}
