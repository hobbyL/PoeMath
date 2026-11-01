// lib/core/services/llm/llm_scenario.dart
//
// 层级：core/services/llm
// 职责：LLM 使用场景枚举 — 每个场景可独立绑定一条厂商配置。
//
// 绑定关系存于 settings box（key 见 [LlmScenario.settingsKey]），
// 值为 llm_providers 中某条配置的 id；未绑定 = 跟随默认生效配置。
//
// 这些 key 随厂商配置备份；恢复前通过服务地址确认闸门检查端点变更。

/// LLM 使用场景。
enum LlmScenario {
  /// AI 出题（应用题生成）。
  wordProblem('llm_provider_word_problem', 'llm_model_word_problem', 'AI 出题'),

  pictureStory(
    'llm_provider_picture_story',
    'llm_model_picture_story',
    '看图说话出题',
  ),

  /// 诗词 AI 讲解。
  poemExplain('llm_provider_poem_explain', 'llm_model_poem_explain', '诗词讲解'),

  /// 算数题 AI 解析。
  mathExplain('llm_provider_math_explain', 'llm_model_math_explain', '口算解析'),

  /// AI 助手（App 内对话助手）。
  assistant('llm_provider_assistant', 'llm_model_assistant', 'AI 助手');

  const LlmScenario(this.settingsKey, this.modelKey, this.label);

  /// 该场景绑定的「厂商配置 id」在 settings box 中的存储键。
  final String settingsKey;

  /// 该场景选中的「模型名」在 settings box 中的存储键（须 ∈ 该配置 models，
  /// 悬空回落配置默认 model）。与 settingsKey 一起随厂商配置备份。
  final String modelKey;

  /// 面向用户的场景名称。
  final String label;
}
