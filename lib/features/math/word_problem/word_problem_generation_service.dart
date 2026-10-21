import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class GeneratedWordProblem {
  GeneratedWordProblem({
    required this.plan,
    required this.source,
    required this.text,
    required this.explanation,
    required this.validation,
  });

  final WordProblemPlan plan;
  final WordProblemSource source;
  final String text;
  final String explanation;
  final WordProblemValidationResult validation;
  String get metadataJson =>
      WordProblemMetadata(plan: plan, source: source).encode();
}

/// 共用生成流程，不导航、不入库。
class WordProblemGenerationService {
  const WordProblemGenerationService({
    required this.client,
    required this.skeletonFactory,
  });
  final LlmClient client;
  final WordProblemSkeletonFactory skeletonFactory;

  Future<List<GeneratedWordProblem>> generate({
    required LlmConfig config,
    required int grade,
    required String semester,
    required WordProblemTopic topic,
    required int count,
    required bool Function() isActive,
  }) async {
    if (!isActive()) throw const LlmGenerationCancelled();
    final plans = WordProblemPlanGenerator.generate(
      grade: grade,
      semester: semester,
      topic: topic.name,
      count: count,
      skeletonFactory: skeletonFactory,
    );
    final result = await client.chooseWordProblemScenes(
      config: config,
      plans: plans,
      grade: grade,
      semester: semester,
      topic: topic.label,
      isActive: isActive,
    );
    if (!isActive()) throw const LlmGenerationCancelled();
    final choices = {for (final choice in result.choices) choice.index: choice};
    return List.unmodifiable([
      for (var i = 0; i < plans.length; i++) _render(plans[i], choices[i + 1]),
    ]);
  }

  GeneratedWordProblem _render(
    WordProblemPlan initial,
    LlmWordProblemSceneChoice? choice,
  ) {
    final plan = choice == null
        ? initial
        : WordProblemPlanGenerator.withScene(
            initial.skeleton,
            initial.relation,
            choice.sceneId,
            variantId: choice.variantId,
          );
    final validation = WordProblemPlanRules.validate(plan);
    final rendered = WordProblemRenderer.render(plan);
    return GeneratedWordProblem(
      plan: plan,
      source: choice == null
          ? WordProblemSource.localTemplate
          : WordProblemSource.aiScene,
      text: rendered.text,
      explanation: rendered.explanation,
      validation: validation,
    );
  }
}
