// lib/core/services/llm/llm_scenario.dart
//
// 层级：core/services/llm
// 职责：LLM 使用场景枚举 — 每个场景可独立绑定一条厂商配置。
//
// 绑定关系存于 settings box（key 见 [LlmScenario.settingsKey]），
// 值为 llm_providers 中某条配置的 id；未绑定 = 跟随默认生效配置。
//
// 这些 key 指向外部服务配置（依赖 llm_providers 存在），与
// llm_active_provider_id 同类，一律不入备份白名单（设备绑定，换机重配）。

/// LLM 使用场景。
enum LlmScenario {
  /// AI 出题（应用题生成）。
  wordProblem('llm_provider_word_problem', 'AI 出题'),

  /// 诗词 AI 讲解。
  poemExplain('llm_provider_poem_explain', '诗词讲解'),

  /// 算数题 AI 解析。
  mathExplain('llm_provider_math_explain', '口算解析');

  const LlmScenario(this.settingsKey, this.label);

  /// 该场景在 settings box 中的存储键。
  final String settingsKey;

  /// 面向用户的场景名称。
  final String label;
}
