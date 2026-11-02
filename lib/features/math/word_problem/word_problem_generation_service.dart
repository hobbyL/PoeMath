import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class GeneratedWordProblem {
  GeneratedWordProblem({
    required this.plan,
    required this.topic,
    required this.source,
    required this.text,
    required this.explanation,
    required this.validation,
  });

  final WordProblemPlan plan;
  final WordProblemTopic topic;
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
    required List<WordProblemTopic> topics,
    required int count,
    DifficultyLevel difficulty = DifficultyLevel.medium,
    required bool Function() isActive,
    String? promptOverride,
  }) async {
    if (!isActive()) throw const LlmGenerationCancelled();
    final selectedTopics = topics.toSet().toList(growable: false);
    if (selectedTopics.isEmpty) throw ArgumentError('请至少选择一个知识点');
    if (count < selectedTopics.length || count > 20) {
      throw ArgumentError('生成数量不能少于知识点数量，且不能超过 20 题');
    }
    final plansByTopic = <WordProblemTopic, List<WordProblemPlan>>{
      for (var i = 0; i < selectedTopics.length; i++)
        selectedTopics[i]: WordProblemPlanGenerator.generate(
          grade: grade,
          semester: semester,
          topic: selectedTopics[i].name,
          count: count ~/ selectedTopics.length +
              (i < count % selectedTopics.length ? 1 : 0),
          difficulty: difficulty,
          skeletonFactory: skeletonFactory,
        ),
    };
    final plans = [
      for (var i = 0; i < count; i++)
        plansByTopic[selectedTopics[i % selectedTopics.length]]![
            i ~/ selectedTopics.length],
    ];
    final result = await client.chooseWordProblemScenes(
      config: config,
      plans: plans,
      grade: grade,
      semester: semester,
      topic: selectedTopics.map((topic) => topic.label).join('、'),
      isActive: isActive,
      promptOverride: promptOverride,
    );
    if (!isActive()) throw const LlmGenerationCancelled();
    final choices = {for (final choice in result.choices) choice.index: choice};
    return List.unmodifiable([
      for (var i = 0; i < plans.length; i++)
        _render(
          plans[i],
          choices[i + 1],
          selectedTopics[i % selectedTopics.length],
        ),
    ]);
  }

  GeneratedWordProblem _render(
    WordProblemPlan initial,
    LlmWordProblemSceneChoice? choice,
    WordProblemTopic topic,
  ) {
    final plan = choice == null
        ? initial
        : WordProblemPlanGenerator.withScene(
            initial.skeleton,
            initial.relation,
            choice.sceneId,
            variantId: choice.variantId,
            version: initial.version,
          );
    final validation = WordProblemPlanRules.validate(plan);
    final rendered = WordProblemRenderer.render(plan);
    return GeneratedWordProblem(
      plan: plan,
      topic: topic,
      source: choice == null
          ? WordProblemSource.localTemplate
          : WordProblemSource.aiScene,
      text: rendered.text,
      explanation: rendered.explanation,
      validation: validation,
    );
  }
}
